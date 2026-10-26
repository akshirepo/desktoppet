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
    func timeToCycleBoundary(parts: Int) -> TimeInterval? {
        asked.append(parts)
        return boundary
    }
}

final class TransitionTests: XCTestCase {
    let graph = TransitionGraph()

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
        let g = TransitionGraph(bridges: [.standToSit, .sitToStand, .sitToLie, .lieToSit])
        XCTAssertEqual(g.plan(from: .idle, to: .sit), [.once(.standToSit)])
        XCTAssertEqual(g.plan(from: .sit, to: .walk), [.once(.sitToStand)])
        XCTAssertEqual(g.plan(from: .idle, to: .watch), [.once(.standToSit), .once(.sitToLie)])
        XCTAssertEqual(g.plan(from: .watch, to: .idle), [.once(.lieToSit), .once(.sitToStand)])
        XCTAssertEqual(g.plan(from: .walk, to: .sleep),
                       [.finish(.walk), .once(.standToSit), .once(.yawn), .once(.sitToLie)])
        XCTAssertEqual(g.plan(from: .sit, to: .sleep), [.once(.yawn), .once(.sitToLie)])
        XCTAssertEqual(g.plan(from: .yawn, to: .sleep), [.once(.sitToLie)])
        XCTAssertEqual(g.plan(from: .sleep, to: .walk), [.once(.lieToSit), .once(.yawn), .once(.sitToStand)])
        XCTAssertEqual(g.plan(from: .sleep, to: .sit), [.once(.lieToSit), .once(.yawn)])
        XCTAssertEqual(g.plan(from: .drink, to: .refreshed), [])
    }

    func testOnlyBridgesThePackHasAreUsed() {
        let g = TransitionGraph(bridges: [.standToSit, .sitToStand])
        XCTAssertEqual(g.plan(from: .idle, to: .watch), [.once(.standToSit)])
        XCTAssertEqual(g.plan(from: .walk, to: .sleep), [.finish(.walk), .once(.standToSit), .once(.yawn)])
    }

    func testReversedSpecDecodesAndAvailableListsStates() throws {
        let json = #"{"states":{"idle":{"folder":"idle","fps":5,"loop":true,"anchor":[0.5,0]},"#
            + #""sitToStand":{"folder":"stand-to-sit","fps":10,"loop":false,"anchor":[0.5,0],"reversed":true}}}"#
        let m = try JSONDecoder().decode(AnimationManifest.self, from: Data(json.utf8))
        XCTAssertEqual(m.states["sitToStand"]?.reversed, true)
        XCTAssertEqual(m.available, [.idle, .sitToStand])
    }

    func testOneShotStepsHoldMotionAndRetargetingMidBridgeTurnsBack() throws {
        let b = TimelineBackend()
        let p = AnimationPlayback(backend: b, graph: TransitionGraph(bridges: [.standToSit, .sitToStand]))
        p.update(.idle, mode: .grounded)
        p.update(.sit, mode: .grounded)
        XCTAssertEqual(b.played, [.idle, .standToSit])
        XCTAssertTrue(p.holdsGroundedMotion(in: .grounded))
        p.update(.walk, mode: .grounded)                    // changed its mind while sitting down
        XCTAssertEqual(b.played, [.idle, .standToSit, .sitToStand])
        try XCTUnwrap(b.once.last).completion()
        XCTAssertEqual(b.played.last, .walk)
        XCTAssertFalse(p.holdsGroundedMotion(in: .grounded))
        p.update(.idle, mode: .grounded)
        p.update(.watch, mode: .grounded)                   // no sitToLie art: brief sit hold, motion not held
        XCTAssertFalse(p.holdsGroundedMotion(in: .grounded))
    }
}
