import XCTest
@testable import CorgiCore

final class RestTests: XCTestCase {
    let full0 = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let full1 = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    func testFullScreenDetection() {
        XCTAssertTrue(isFullScreen(frontWindow: full1, screenFrames: [full0, full1]))
        XCTAssertTrue(isFullScreen(frontWindow: CGRect(x: 0.5, y: 0, width: 1440, height: 900), screenFrames: [full0]))
        XCTAssertFalse(isFullScreen(frontWindow: CGRect(x: 0, y: 0, width: 1440, height: 875), screenFrames: [full0]))
        XCTAssertFalse(isFullScreen(frontWindow: nil, screenFrames: [full0]))
    }

    func testIdleYawnsThenSleepsAndWakesOnInput() {
        let r = RestMonitor()
        XCTAssertNil(r.update(dt: 0.1, idleSeconds: 89, fullScreen: false, busy: false))
        XCTAssertEqual(r.update(dt: 0.1, idleSeconds: 90, fullScreen: false, busy: false), .startYawn)
        XCTAssertNil(r.update(dt: 1.5, idleSeconds: 91.5, fullScreen: false, busy: false))
        XCTAssertEqual(r.update(dt: 0.6, idleSeconds: 92.1, fullScreen: false, busy: false), .fallAsleep)
        XCTAssertNil(r.update(dt: 60, idleSeconds: 152, fullScreen: false, busy: false))
        XCTAssertEqual(r.phase, .asleep)
        XCTAssertEqual(r.update(dt: 0.1, idleSeconds: 0, fullScreen: false, busy: false), .wake)
        XCTAssertEqual(r.phase, .awake)
    }

    func testFullScreenSleepsRightAwayAndWakesWhenItEnds() {
        let r = RestMonitor()
        XCTAssertEqual(r.update(dt: 0.1, idleSeconds: 0, fullScreen: true, busy: false), .fallAsleep)
        XCTAssertNil(r.update(dt: 0.1, idleSeconds: 0, fullScreen: true, busy: false))
        XCTAssertEqual(r.update(dt: 0.1, idleSeconds: 0, fullScreen: false, busy: false), .wake)
    }

    func testDraggingBlocksRestAndCancelsAYawn() {
        let r = RestMonitor()
        XCTAssertNil(r.update(dt: 0.1, idleSeconds: 200, fullScreen: false, busy: true))
        XCTAssertEqual(r.update(dt: 0.1, idleSeconds: 200, fullScreen: false, busy: false), .startYawn)
        XCTAssertEqual(r.update(dt: 0.1, idleSeconds: 200, fullScreen: false, busy: true), .wake)
        XCTAssertEqual(r.phase, .awake)
    }

    func testFullScreenDuringChaseMeWaitsUntilChaseEnds() {
        let r = RestMonitor()
        for _ in 0..<10 { XCTAssertNil(r.update(dt: 0.1, idleSeconds: 0, fullScreen: true, busy: true)) }
        XCTAssertNil(r.update(dt: 0.1, idleSeconds: 0, fullScreen: false, busy: true))
        XCTAssertNil(r.update(dt: 0.1, idleSeconds: 0, fullScreen: true, busy: true))
        XCTAssertEqual(r.update(dt: 0.1, idleSeconds: 0, fullScreen: true, busy: false), .fallAsleep)
        XCTAssertEqual(r.update(dt: 0.1, idleSeconds: 0, fullScreen: true, busy: true), .wake)
    }
}

final class AttentionTests: XCTestCase {
    func testHoverPetsAfterDelayThenRepeats() {
        let h = HoverPet()
        var pets: [Int] = []
        for i in 1...40 where h.update(dt: 0.1, hovering: true, blocked: false) { pets.append(i) }
        XCTAssertEqual(pets, [4, 19, 34])     // 0.4s, 1.9s, 3.4s
        XCTAssertFalse(h.update(dt: 0.1, hovering: false, blocked: false))
        XCTAssertFalse(h.update(dt: 0.3, hovering: true, blocked: false))
        XCTAssertTrue(h.update(dt: 0.1, hovering: true, blocked: false))
    }

    func testHoverWhileAsleepOrHeldNeverPets() {
        let h = HoverPet()
        for _ in 0..<50 { XCTAssertFalse(h.update(dt: 0.1, hovering: true, blocked: true)) }
        XCTAssertFalse(h.update(dt: 0.3, hovering: true, blocked: false))   // timer starts over
        XCTAssertTrue(h.update(dt: 0.1, hovering: true, blocked: false))
    }

    func testBoredAfterTenMinutesOnlyWhenHappyAndRested() {
        let clock = FakeClock()
        let b = BoredomTimer(clock: clock)
        var s = NeedsState.fresh(at: clock.now)
        clock.advance(599)
        XCTAssertFalse(b.isBored(s))
        clock.advance(1)
        XCTAssertTrue(b.isBored(s))
        s.happiness = 50
        XCTAssertFalse(b.isBored(s))
        s.happiness = 70
        s.energy = 40
        XCTAssertFalse(b.isBored(s))
    }

    func testInteractionResetsBoredomAndClockGoingBackIsSafe() {
        let clock = FakeClock()
        let b = BoredomTimer(clock: clock)
        let s = NeedsState.fresh(at: clock.now)
        clock.advance(700)
        b.noteInteraction()
        XCTAssertFalse(b.isBored(s))
        clock.advance(-5000)
        XCTAssertEqual(b.secondsSinceInteraction, 0)
        XCTAssertFalse(b.isBored(s))
    }

    func testCatchPetGivesTenAndSharesPetLimit() {
        let clock = FakeClock()
        var s = NeedsState.fresh(at: clock.now)
        s.happiness = 0
        let e = NeedsEngine(state: s, clock: clock)
        XCTAssertTrue(e.catchPet())
        XCTAssertEqual(e.state.happiness, 10, accuracy: 0.01)
        for _ in 0..<9 { XCTAssertTrue(e.pet()) }
        XCTAssertFalse(e.catchPet())
        XCTAssertFalse(e.pet())
    }
}
