import XCTest
@testable import CorgiCore

private final class RecordingAnimationBackend: AnimationPlaybackBackend {
    var states: [AnimState] = []
    var once: [(state: AnimState, completion: () -> Void)] = []
    var duration: TimeInterval? = 2
    var completesSynchronously = false

    func play(_ state: AnimState) { states.append(state) }
    func playOnce(_ state: AnimState, completion: @escaping () -> Void) -> TimeInterval? {
        once.append((state, completion))
        if completesSynchronously { completion() }
        return duration
    }
}

final class AnimationPlaybackTests: XCTestCase {
    func testUnchangedBaseStateDoesNotRestartLoop() {
        let backend = RecordingAnimationBackend()
        let playback = AnimationPlayback(backend: backend)
        for _ in 0..<30 { playback.update(.run, mode: .grounded) }
        XCTAssertEqual(backend.states, [.run])
    }

    func testReactionWaitsForItsFullCycleInsteadOfOldLandingTimer() throws {
        let backend = RecordingAnimationBackend()
        let playback = AnimationPlayback(backend: backend)
        playback.update(.fall, mode: .airborne)
        XCTAssertTrue(playback.requestReaction(.land, mode: .grounded))
        let completion = try XCTUnwrap(backend.once.last?.completion)
        playback.advance(dt: 0.3, mode: .grounded)
        playback.update(.walk, mode: .grounded)
        XCTAssertEqual(playback.reactionState, .land)
        XCTAssertEqual(playback.currentState, .land)
        XCTAssertTrue(playback.holdsGroundedMotion(in: .grounded))
        playback.advance(dt: 1.69, mode: .grounded)
        XCTAssertEqual(playback.reactionState, .land)
        completion()
        playback.update(.walk, mode: .grounded)
        XCTAssertNil(playback.reactionState)
        XCTAssertFalse(playback.holdsGroundedMotion(in: .grounded))
        XCTAssertEqual(backend.states, [.fall, .walk])
    }

    func testRepeatedReactionDoesNotRestartItsCycle() throws {
        let backend = RecordingAnimationBackend()
        let playback = AnimationPlayback(backend: backend)
        XCTAssertTrue(playback.requestReaction(.happy, mode: .grounded))
        playback.advance(dt: 1, mode: .grounded)
        XCTAssertTrue(playback.requestReaction(.happy, mode: .grounded))
        XCTAssertEqual(backend.once.count, 1)
        try XCTUnwrap(backend.once.first?.completion)()
        XCTAssertNil(playback.reactionState)
    }

    func testLandingIsNotReplacedByHoverReaction() {
        let backend = RecordingAnimationBackend()
        let playback = AnimationPlayback(backend: backend)
        XCTAssertTrue(playback.requestReaction(.land, mode: .grounded))
        XCTAssertFalse(playback.requestReaction(.happy, mode: .grounded))
        XCTAssertEqual(playback.reactionState, .land)
        XCTAssertEqual(backend.once.map(\.state), [.land])
    }

    func testOldCompletionCannotClearNewReaction() throws {
        let backend = RecordingAnimationBackend()
        let playback = AnimationPlayback(backend: backend)
        playback.requestReaction(.happy, mode: .grounded)
        let oldCompletion = try XCTUnwrap(backend.once.last?.completion)
        playback.requestReaction(.land, mode: .grounded)
        oldCompletion()
        XCTAssertEqual(playback.reactionState, .land)
        XCTAssertEqual(playback.currentState, .land)
        try XCTUnwrap(backend.once.last?.completion)()
        XCTAssertNil(playback.reactionState)
    }

    func testPhysicalModesCancelGroundedReactionAndIgnoreItsLateCompletion() throws {
        for (mode, state): (BodyMode, AnimState) in [(.held, .scared), (.airborne, .fall),
                                                    (.clinging, .clingLeft), (.roaming, .roam)] {
            let backend = RecordingAnimationBackend()
            let playback = AnimationPlayback(backend: backend)
            playback.requestReaction(.wiggle, mode: .grounded)
            let completion = try XCTUnwrap(backend.once.last?.completion)
            playback.update(state, mode: mode)
            XCTAssertNil(playback.reactionState)
            XCTAssertFalse(playback.holdsGroundedMotion(in: mode))
            completion()
            playback.update(state, mode: mode)
            XCTAssertEqual(playback.currentState, state)
            XCTAssertEqual(backend.states, [state])
            XCTAssertFalse(playback.requestReaction(.happy, mode: mode))
        }
    }

    func testBehaviorChangeCancelsReactionWithoutRestartFromLateCompletion() throws {
        let backend = RecordingAnimationBackend()
        let playback = AnimationPlayback(backend: backend)
        playback.requestReaction(.happy, mode: .grounded)
        let completion = try XCTUnwrap(backend.once.last?.completion)
        playback.cancelReaction()
        playback.update(.eat, mode: .grounded)
        completion()
        playback.update(.eat, mode: .grounded)
        XCTAssertEqual(backend.states, [.eat])
        XCTAssertFalse(playback.holdsGroundedMotion(in: .grounded))
    }

    func testGroundedReactionHoldsTravelThenExecutorResumesItsCurrentTarget() throws {
        let provider = FakeWindows()
        let world = World(provider: provider, screens: [screen0])
        world.refresh()
        let body = Body(position: CGPoint(x: 400, y: 0))
        body.step(dt: 1.0 / 60, world: world)
        let executor = BehaviorExecutor(rng: SeededRandom(seed: 1))
        executor.begin(.fetch, body: body, world: world, cursor: .zero)
        executor.targetX = 1000
        _ = executor.step(.fetch, body: body, world: world, cursor: .zero)
        XCTAssertTrue(body.isMoving)
        let backend = RecordingAnimationBackend()
        let playback = AnimationPlayback(backend: backend)
        XCTAssertTrue(playback.requestReaction(.happy, mode: .grounded))
        let completion = try XCTUnwrap(backend.once.last?.completion)
        let start = body.position
        for _ in 0..<30 {
            playback.advance(dt: 1.0 / 30, mode: body.mode)
            if playback.holdsGroundedMotion(in: body.mode) { body.stop() }
            else { _ = executor.step(.fetch, body: body, world: world, cursor: .zero) }
            body.step(dt: 1.0 / 30, world: world)
        }
        XCTAssertEqual(body.position, start)
        XCTAssertFalse(body.isMoving)
        // A new target during the reaction must take effect; no saved velocity is restored.
        executor.targetX = 100
        completion()
        _ = executor.step(.fetch, body: body, world: world, cursor: .zero)
        body.step(dt: 1.0 / 30, world: world)
        XCTAssertLessThan(body.position.x, start.x)
        XCTAssertFalse(body.facingRight)
    }

    func testReleaseLeavesGravityActiveAndYieldsToLanding() throws {
        let provider = FakeWindows()
        let world = World(provider: provider, screens: [screen0])
        world.refresh()
        let body = Body(position: CGPoint(x: 400, y: 200))
        let backend = RecordingAnimationBackend()
        backend.duration = 3.45
        let playback = AnimationPlayback(backend: backend)
        XCTAssertTrue(playback.requestReaction(.letGo, mode: .airborne))
        let releaseCompletion = try XCTUnwrap(backend.once.last?.completion)
        XCTAssertFalse(playback.holdsGroundedMotion(in: body.mode))
        body.step(dt: 1.0 / 30, world: world)
        XCTAssertLessThan(body.position.y, 200)
        playback.update(.fall, mode: body.mode)
        XCTAssertEqual(playback.currentState, .letGo)
        for _ in 0..<60 where body.mode == .airborne { body.step(dt: 1.0 / 30, world: world) }
        XCTAssertEqual(body.mode, .grounded)
        XCTAssertTrue(playback.requestReaction(.land, mode: body.mode))
        releaseCompletion()
        XCTAssertEqual(playback.reactionState, .land)
        XCTAssertTrue(playback.holdsGroundedMotion(in: body.mode))
    }

    func testReleaseIsInterruptedByPickupOrClinging() throws {
        for (mode, state): (BodyMode, AnimState) in [(.held, .scared), (.clinging, .clingPeek)] {
            let backend = RecordingAnimationBackend()
            let playback = AnimationPlayback(backend: backend)
            playback.requestReaction(.letGo, mode: .airborne)
            let completion = try XCTUnwrap(backend.once.last?.completion)
            playback.update(state, mode: mode)
            completion()
            playback.update(state, mode: mode)
            XCTAssertNil(playback.reactionState)
            XCTAssertEqual(backend.states, [state])
        }
    }

    func testSynchronousCompletionCannotStrandReaction() {
        let backend = RecordingAnimationBackend()
        backend.completesSynchronously = true
        let playback = AnimationPlayback(backend: backend)
        playback.requestReaction(.happy, mode: .grounded)
        XCTAssertEqual(backend.once.count, 1)
        XCTAssertNil(playback.reactionState)
        XCTAssertFalse(playback.holdsGroundedMotion(in: .grounded))
        playback.update(.walk, mode: .grounded)
        XCTAssertEqual(backend.states, [.walk])
    }

    func testUnsupportedOrInvalidPlaybackDurationCannotHoldMotion() {
        for duration: TimeInterval? in [nil, 0, -1, .infinity, .nan, .greatestFiniteMagnitude] {
            let backend = RecordingAnimationBackend()
            backend.duration = duration
            let playback = AnimationPlayback(backend: backend)
            playback.requestReaction(.happy, mode: .grounded)
            XCTAssertEqual(backend.once.count, 1)
            XCTAssertNil(playback.reactionState)
            XCTAssertFalse(playback.holdsGroundedMotion(in: .grounded))
            playback.update(.walk, mode: .grounded)
            XCTAssertEqual(backend.states, [.walk])
        }
    }

    func testMissingCompletionRecoversAfterActualDurationAndGrace() throws {
        let backend = RecordingAnimationBackend()
        let playback = AnimationPlayback(backend: backend)
        playback.requestReaction(.happy, mode: .grounded)
        let oldCompletion = try XCTUnwrap(backend.once.last?.completion)
        playback.advance(dt: 2, mode: .grounded)
        XCTAssertEqual(playback.reactionState, .happy)
        playback.advance(dt: 1.1, mode: .grounded)
        XCTAssertNil(playback.reactionState)
        playback.update(.walk, mode: .grounded)
        XCTAssertEqual(backend.states, [.walk])
        playback.requestReaction(.land, mode: .grounded)
        oldCompletion()
        XCTAssertEqual(playback.reactionState, .land)
    }

    func testInvalidDeltaDoesNotExpireReaction() {
        let backend = RecordingAnimationBackend()
        let playback = AnimationPlayback(backend: backend)
        playback.requestReaction(.happy, mode: .grounded)
        for dt in [-1.0, .infinity, .nan] {
            playback.advance(dt: dt, mode: .grounded)
            XCTAssertEqual(playback.reactionState, .happy)
        }
    }
}
