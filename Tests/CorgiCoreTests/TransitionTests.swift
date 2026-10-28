import XCTest
@testable import CorgiCore

private final class TimelineBackend: AnimationPlaybackBackend {
    var played: [AnimState] = []
    var once: [(state: AnimState, completion: () -> Void)] = []
    var boundary: TimeInterval? = 0.3
    var asked: [Int] = []

    func play(_ state: AnimState) { played.append(state) }
    func playOnce(_ state: AnimState, completion: @escaping () -> Void) -> TimeInterval? {
        played.append(state)
        once.append((state, completion))
        return 2.5
    }
    var bridges: [String] = []
    var bridgeDone: [() -> Void] = []
    func playBridge(_ name: String, completion: @escaping () -> Void) -> TimeInterval? {
        bridges.append(name)
        bridgeDone.append(completion)
        return 0.6
    }
    func timeToCycleBoundary(parts: Int) -> TimeInterval? {
        asked.append(parts)
        return boundary
    }
}

final class TransitionTests: XCTestCase {
    let graph = TransitionGraph(direct: [[.drink, .refreshed], [.read, .readSleep], [.readSleep, .read]])

    func testWalkingToSleepFinishesTheStepSitsAndYawnsFirst() {
        XCTAssertEqual(graph.plan(from: .walk, to: .sleep), [.finish(.walk), .once(.yawn)])
        XCTAssertEqual(graph.plan(from: .idle, to: .sleep), [.once(.yawn)])
        XCTAssertEqual(graph.plan(from: .watch, to: .sleep), [])          // already lying down
        XCTAssertEqual(graph.plan(from: .yawn, to: .sleep), [])
    }

    func testWakingYawnsBeforeGettingUp() {
        XCTAssertEqual(graph.plan(from: .sleep, to: .walk), [.once(.yawn)])
        XCTAssertEqual(graph.plan(from: .sleep, to: .yawn), [])
    }

    func testEatingToDrinkingFinishesTheBite() {
        XCTAssertEqual(graph.plan(from: .eat, to: .drink), [.finish(.eat)])
        XCTAssertEqual(graph.plan(from: .drink, to: .refreshed), [])
        XCTAssertEqual(graph.plan(from: .drink, to: .sit), [.finish(.drink)])
    }

    func testStandingToLyingGoesThroughASit() {
        XCTAssertEqual(graph.plan(from: .idle, to: .watch), [.hold(.sit, 0.45)])
        XCTAssertEqual(graph.plan(from: .watch, to: .walk), [.hold(.sit, 0.45)])
        XCTAssertEqual(graph.plan(from: .walk, to: .eat), [.finish(.walk), .hold(.sit, 0.45)])
        XCTAssertEqual(graph.plan(from: .idle, to: .sit), [])
        XCTAssertEqual(graph.plan(from: .sit, to: .watch), [])
    }

    func testPosesWithoutAPostureSwitchDirectly() {
        XCTAssertEqual(graph.plan(from: .fall, to: .sleep), [])
        XCTAssertEqual(graph.plan(from: .walk, to: .clingSit), [])
    }

    func testSheepPackOverridesItsEatingPosture() throws {
        let json = #"{"scale":1,"states":{"idle":{"folder":"idle","fps":5,"loop":true,"anchor":[0.5,0]},"#
            + #""eat":{"folder":"eat","fps":5,"loop":true,"anchor":[0.5,0],"posture":"stand"}}}"#
        let m = try JSONDecoder().decode(AnimationManifest.self, from: Data(json.utf8))
        let sheep = TransitionGraph(postures: m.postures)
        XCTAssertEqual(sheep.plan(from: .eat, to: .drink), [.finish(.eat), .hold(.sit, 0.45)])
        XCTAssertEqual(m.postures[.drink], .lie)
    }

    func testPlaybackRunsStepsInOrderThenLoopsTheTarget() throws {
        let b = TimelineBackend()
        let p = AnimationPlayback(backend: b)
        p.update(.walk, mode: .grounded)
        p.update(.sleep, mode: .grounded)
        XCTAssertEqual(b.played, [.walk])           // finishing the step
        XCTAssertEqual(b.asked, [2])
        XCTAssertEqual(p.transitionTarget, .sleep)
        p.update(.sleep, mode: .grounded)           // same request again is a no-op
        p.advance(dt: 0.31, mode: .grounded)
        XCTAssertEqual(b.played, [.walk, .yawn])
        try XCTUnwrap(b.once.last).completion()
        XCTAssertEqual(b.played, [.walk, .yawn, .sleep])
        XCTAssertNil(p.transitionTarget)
        XCTAssertEqual(p.currentState, .sleep)
    }

    func testChangingTargetMidTransitionReplansAndIgnoresTheOldCompletion() throws {
        let b = TimelineBackend()
        let p = AnimationPlayback(backend: b)
        p.update(.idle, mode: .grounded)
        p.update(.sleep, mode: .grounded)
        XCTAssertEqual(b.played, [.idle, .yawn])
        let stale = try XCTUnwrap(b.once.last).completion
        p.update(.walk, mode: .grounded)            // yawn is a sit, so it gets up directly
        XCTAssertEqual(b.played, [.idle, .yawn, .walk])
        stale()
        XCTAssertEqual(b.played, [.idle, .yawn, .walk])
        XCTAssertEqual(p.currentState, .walk)
    }

    func testHoldTimesOutIntoTheTarget() {
        let b = TimelineBackend()
        let p = AnimationPlayback(backend: b)
        p.update(.idle, mode: .grounded)
        p.update(.watch, mode: .grounded)
        XCTAssertEqual(b.played, [.idle, .sit])
        p.advance(dt: 0.2, mode: .grounded)
        XCTAssertEqual(b.played, [.idle, .sit])
        p.advance(dt: 0.3, mode: .grounded)
        XCTAssertEqual(b.played, [.idle, .sit, .watch])
    }

    func testRapidChangesNeverFlashIdleOrStack() {
        let b = TimelineBackend()
        let p = AnimationPlayback(backend: b)
        p.update(.sit, mode: .grounded)
        for s in [AnimState.watch, .read, .watch, .music, .sit] { p.update(s, mode: .grounded) }
        XCTAssertFalse(b.played.contains(.idle))
        XCTAssertEqual(b.played.last, .sit)
    }

    func testLeavingTheGroundOrAReactionCancelsTheTransition() throws {
        let b = TimelineBackend()
        let p = AnimationPlayback(backend: b)
        p.update(.idle, mode: .grounded)
        p.update(.watch, mode: .grounded)
        p.update(.fall, mode: .airborne)
        XCTAssertNil(p.transitionTarget)
        XCTAssertEqual(b.played.last, .fall)
        p.update(.walk, mode: .grounded)
        p.update(.sleep, mode: .grounded)
        XCTAssertTrue(p.requestReaction(.happy, mode: .grounded))
        XCTAssertNil(p.transitionTarget)
        p.advance(dt: 5, mode: .grounded)
        XCTAssertFalse(b.played.contains(.yawn))
    }

    func testUnknownCycleBoundaryMovesOnRightAway() {
        let b = TimelineBackend()
        b.boundary = nil
        let p = AnimationPlayback(backend: b)
        p.update(.eat, mode: .grounded)
        p.update(.drink, mode: .grounded)
        XCTAssertEqual(b.played, [.eat, .drink])
    }

    func testBridgeArtReplacesCutsWhenThePackHasIt() {
        let g = TransitionGraph(bridges: ["stand>sit", "sit>stand", "sit>sleep", "sleep>sit"], direct: [[.drink, .refreshed]])
        XCTAssertEqual(g.plan(from: .idle, to: .sit), [.bridge("stand>sit", endsAt: .sit)])
        XCTAssertEqual(g.plan(from: .sit, to: .walk), [.bridge("sit>stand", endsAt: .idle)])
        XCTAssertEqual(g.plan(from: .idle, to: .watch), [.bridge("stand>sit", endsAt: .sit)])  // lie-down art is for sleep
        XCTAssertEqual(g.plan(from: .watch, to: .idle), [.bridge("sit>stand", endsAt: .idle)])
        XCTAssertEqual(g.plan(from: .sit, to: .eat), [])
        XCTAssertEqual(g.plan(from: .walk, to: .sleep),
                       [.finish(.walk), .bridge("stand>sit", endsAt: .sit), .once(.yawn), .bridge("sit>sleep", endsAt: .sleep)])
        XCTAssertEqual(g.plan(from: .sit, to: .sleep), [.once(.yawn), .bridge("sit>sleep", endsAt: .sleep)])
        XCTAssertEqual(g.plan(from: .yawn, to: .sleep), [.bridge("sit>sleep", endsAt: .sleep)])
        XCTAssertEqual(g.plan(from: .sleep, to: .walk),
                       [.bridge("sleep>sit", endsAt: .sit), .once(.yawn), .bridge("sit>stand", endsAt: .idle)])
        XCTAssertEqual(g.plan(from: .sleep, to: .sit), [.bridge("sleep>sit", endsAt: .sit), .once(.yawn)])
        XCTAssertEqual(g.plan(from: .drink, to: .refreshed), [])
    }

    func testOnlyBridgesThePackHasAreUsed() {
        let g = TransitionGraph(bridges: ["stand>sit", "sit>stand"])
        XCTAssertEqual(g.plan(from: .idle, to: .watch), [.bridge("stand>sit", endsAt: .sit)])
        XCTAssertEqual(g.plan(from: .walk, to: .sleep), [.finish(.walk), .bridge("stand>sit", endsAt: .sit), .once(.yawn)])
    }

    func testActivitiesAreEnteredAndLeftThroughTheirHub() {
        let g = TransitionGraph(bridges: ["stand>sit", "sit>stand", "enter:watch", "exit:watch", "enter:read", "exit:read",
                                          "enter:run", "exit:run", "enter:eat"])
        XCTAssertEqual(g.hub(.watch), .sit)
        XCTAssertEqual(g.hub(.run), .idle)
        XCTAssertEqual(g.hub(.sleep), .sleep)
        XCTAssertEqual(g.plan(from: .walk, to: .watch),
                       [.finish(.walk), .bridge("stand>sit", endsAt: .sit), .bridge("enter:watch", endsAt: .watch)])
        XCTAssertEqual(g.plan(from: .watch, to: .read),
                       [.finish(.watch), .bridge("exit:watch", endsAt: .sit), .bridge("enter:read", endsAt: .read)])
        XCTAssertEqual(g.plan(from: .read, to: .run),
                       [.finish(.read), .bridge("exit:read", endsAt: .sit), .bridge("sit>stand", endsAt: .idle),
                        .bridge("enter:run", endsAt: .run)])
        XCTAssertEqual(g.plan(from: .run, to: .idle), [.finish(.run), .bridge("exit:run", endsAt: .idle)])
        XCTAssertEqual(g.plan(from: .eat, to: .sit), [.finish(.eat)])          // no exit:eat art: cut back to the hub
        XCTAssertEqual(g.plan(from: .eat, to: .sleep), [.finish(.eat)])         // already lying, no exit art: dozes off
        XCTAssertEqual(g.plan(from: .watch, to: .sleep),                         // with exit art it gets up, yawns, lies down
                       [.finish(.watch), .bridge("exit:watch", endsAt: .sit), .once(.yawn)])
    }

    func testBridgesDecodeFromTheManifest() throws {
        let json = #"{"states":{"idle":{"folder":"idle","fps":5,"loop":true,"anchor":[0.5,0]}},"bridges":{"#
            + #""stand>sit":{"folder":"standToSit","fps":9,"loop":false,"anchor":[0.5,0]},"#
            + #""sit>stand":{"folder":"standToSit","fps":10,"loop":false,"anchor":[0.5,0],"reversed":true}}}"#
        let m = try JSONDecoder().decode(AnimationManifest.self, from: Data(json.utf8))
        XCTAssertEqual(Set(m.bridges!.keys), ["stand>sit", "sit>stand"])
        XCTAssertEqual(m.bridges?["sit>stand"]?.reversed, true)
        XCTAssertEqual(m.available, [.idle])
    }

    func testOneShotStepsHoldMotionAndRetargetingMidBridgeTurnsBack() throws {
        let b = TimelineBackend()
        let p = AnimationPlayback(backend: b, graph: TransitionGraph(bridges: ["stand>sit", "sit>stand"]))
        p.update(.idle, mode: .grounded)
        p.update(.sit, mode: .grounded)
        XCTAssertEqual(b.bridges, ["stand>sit"])
        XCTAssertTrue(p.holdsGroundedMotion(in: .grounded))
        p.update(.walk, mode: .grounded)                    // changed its mind while sitting down
        XCTAssertEqual(b.bridges, ["stand>sit", "sit>stand"])
        try XCTUnwrap(b.bridgeDone.last)()
        XCTAssertEqual(b.played.last, .walk)
        XCTAssertFalse(p.holdsGroundedMotion(in: .grounded))
        p.update(.idle, mode: .grounded)
        p.update(.watch, mode: .grounded)
        XCTAssertFalse(b.bridges.contains("sit>sleep"))
    }

    func testDirectGroupsSkipTheHub() throws {
        let json = #"{"states":{"idle":{"folder":"idle","fps":5,"loop":true,"anchor":[0.5,0]}},"directGroups":[["walk","run","kick"]]}"#
        let m = try JSONDecoder().decode(AnimationManifest.self, from: Data(json.utf8))
        XCTAssertEqual(m.directPairs.count, 6)
        let g = TransitionGraph(bridges: ["enter:walk", "exit:walk", "enter:run", "exit:run"], direct: m.directPairs)
        XCTAssertEqual(g.plan(from: .walk, to: .run), [])
        XCTAssertEqual(g.plan(from: .idle, to: .walk), [.bridge("enter:walk", endsAt: .walk)])
        XCTAssertEqual(g.plan(from: .walk, to: .idle), [.finish(.walk), .bridge("exit:walk", endsAt: .idle)])
    }

    func testPairBridgesBeatDirectSwitches() {
        let g = TransitionGraph(bridges: ["pair:walk>fetch"], direct: [[.walk, .fetch], [.fetch, .walk]])
        XCTAssertEqual(g.plan(from: .walk, to: .fetch), [.finish(.walk), .bridge("pair:walk>fetch", endsAt: .fetch)])
        XCTAssertEqual(g.plan(from: .fetch, to: .walk), [])
    }

    func testAfterAReactionTheNextChangeStillUsesBridges() throws {
        let b = TimelineBackend()
        let p = AnimationPlayback(backend: b, graph: TransitionGraph(bridges: ["stand>sit", "enter:wave"]))
        p.update(.fall, mode: .airborne)
        XCTAssertTrue(p.requestReaction(.land, mode: .grounded))
        p.cancelReaction()
        p.update(.wave, mode: .grounded)
        XCTAssertEqual(b.bridges, ["stand>sit"])
        try XCTUnwrap(b.bridgeDone.last)()
        XCTAssertEqual(b.bridges, ["stand>sit", "enter:wave"])
    }
}
