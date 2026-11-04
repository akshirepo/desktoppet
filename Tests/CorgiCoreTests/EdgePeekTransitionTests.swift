import XCTest
@testable import CorgiCore

private final class BridgeBackend: AnimationPlaybackBackend {
    var played: [String] = []
    var bridges: [(name: String, done: () -> Void)] = []
    var once: [(state: AnimState, done: () -> Void)] = []
    func play(_ state: AnimState) { played.append(state.rawValue) }
    func playOnce(_ state: AnimState, completion: @escaping () -> Void) -> TimeInterval? {
        once.append((state, completion))
        played.append("once:\(state.rawValue)")
        return 1
    }
    func playBridge(_ name: String, completion: @escaping () -> Void) -> TimeInterval? {
        bridges.append((name, completion))
        played.append(name)
        return 1
    }
}

final class EdgePeekTransitionTests: XCTestCase {
    let edgeBridges: Set<String> = ["enter:peekEdge", "exit:peekEdge", "enter:holdEdge", "exit:holdEdge", "stand>sit", "sit>stand"]
    var graph: TransitionGraph { TransitionGraph(bridges: edgeBridges) }

    func testFloorPeekIsEnteredFromStandingThroughItsBridge() {
        XCTAssertEqual(graph.plan(from: .idle, to: .peekEdge), [.bridge("enter:peekEdge", endsAt: .peekEdge)])
        // A walk finishes its step first.
        XCTAssertEqual(graph.plan(from: .walk, to: .peekEdge), [.finish(.walk), .bridge("enter:peekEdge", endsAt: .peekEdge)])
        // A sitting pet stands up first.
        XCTAssertEqual(graph.plan(from: .sit, to: .peekEdge),
                       [.bridge("sit>stand", endsAt: .idle), .bridge("enter:peekEdge", endsAt: .peekEdge)])
    }

    func testFloorPeekLeavesThroughItsExitThenRoutesOn() {
        XCTAssertEqual(graph.plan(from: .peekEdge, to: .idle), [.finish(.peekEdge), .bridge("exit:peekEdge", endsAt: .idle)])
        XCTAssertEqual(graph.plan(from: .peekEdge, to: .sit),
                       [.finish(.peekEdge), .bridge("exit:peekEdge", endsAt: .idle), .bridge("stand>sit", endsAt: .sit)])
    }

    func testHoldIsEnteredStraightFromTheDropPoseAndEndsInIt() {
        XCTAssertEqual(graph.plan(from: .scared, to: .holdEdge), [.bridge("enter:holdEdge", endsAt: .holdEdge)])
        XCTAssertEqual(graph.plan(from: .holdEdge, to: .scared), [.finish(.holdEdge), .bridge("exit:holdEdge", endsAt: .scared)])
    }

    func testWithoutArtItSwitchesDirectly() {
        let bare = TransitionGraph()
        XCTAssertEqual(bare.plan(from: .idle, to: .peekEdge), [])
        XCTAssertEqual(bare.plan(from: .peekEdge, to: .idle), [])
        XCTAssertEqual(bare.plan(from: .scared, to: .holdEdge), [])
    }

    func testPlaybackRunsTheEntryBridgeWhilePeeking() {
        let backend = BridgeBackend()
        let playback = AnimationPlayback(backend: backend, graph: graph)
        playback.update(.idle, mode: .grounded)
        playback.update(.peekEdge, mode: .peeking)
        XCTAssertEqual(backend.played, ["idle", "enter:peekEdge"])
        XCTAssertEqual(playback.transitionTarget, .peekEdge)
        backend.bridges.last?.done()
        XCTAssertEqual(backend.played.last, "peekEdge")
        XCTAssertNil(playback.transitionTarget)
        // Coming out again.
        playback.update(.idle, mode: .peeking)
        XCTAssertEqual(backend.played.last, "exit:peekEdge")
        backend.bridges.last?.done()
        XCTAssertEqual(playback.currentState, .idle)
        XCTAssertNil(playback.transitionTarget)
    }

    func testHoldEntryPlaysFromTheHeldPose() {
        let backend = BridgeBackend()
        let playback = AnimationPlayback(backend: backend, graph: graph)
        playback.update(.scared, mode: .held)
        playback.update(.holdEdge, mode: .peeking)
        XCTAssertEqual(backend.played, ["scared", "enter:holdEdge"])
    }

    func testPettingWhilePeekingDoesNotPopOutForAReaction() {
        let backend = BridgeBackend()
        let playback = AnimationPlayback(backend: backend, graph: graph)
        playback.update(.peekEdge, mode: .peeking)
        XCTAssertFalse(playback.requestReaction(.wiggle, mode: .peeking))
        XCTAssertFalse(playback.requestReaction(.happy, mode: .grounded))
        XCTAssertTrue(backend.once.isEmpty)
        // Dropped off the edge, the let-go reaction still plays.
        XCTAssertTrue(playback.requestReaction(.letGo, mode: .airborne))
    }

    func testPickedUpMidEntrySwitchesStraightToTheHeldPose() {
        let backend = BridgeBackend()
        let playback = AnimationPlayback(backend: backend, graph: graph)
        playback.update(.idle, mode: .grounded)
        playback.update(.peekEdge, mode: .peeking)
        playback.update(.scared, mode: .held)
        XCTAssertEqual(backend.played.last, "scared")
        XCTAssertNil(playback.transitionTarget)
    }

    func testPeekingModeMapsToThePeekPose() {
        XCTAssertEqual(animState(for: .peek, mode: .peeking, isMoving: false), .peekEdge)
        XCTAssertEqual(animState(for: .peek, mode: .grounded, isMoving: true), .walk)
    }
}
