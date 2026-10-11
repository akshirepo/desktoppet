import XCTest
@testable import CorgiCore

final class NeedsTests: XCTestCase {
    func makeEngine(_ clock: FakeClock, state: NeedsState? = nil) -> NeedsEngine {
        NeedsEngine(state: state ?? .fresh(at: clock.now), config: .default, clock: clock)
    }

    func testFreshStateIsSeventy() {
        let s = NeedsState.fresh(at: Date(timeIntervalSince1970: 0))
        for need in Need.allCases { XCTAssertEqual(s[need], 70) }
        XCTAssertFalse(s.isAsleep)
        XCTAssertEqual(s.careXP, 0)
    }

    func testTickDecaysByHourlyRates() {
        let clock = FakeClock()
        let engine = makeEngine(clock)
        clock.advance(3600)
        engine.tick()
        XCTAssertEqual(engine.state.hunger, 62, accuracy: 0.001)
        XCTAssertEqual(engine.state.happiness, 65, accuracy: 0.001)
        XCTAssertEqual(engine.state.energy, 64, accuracy: 0.001)
        XCTAssertEqual(engine.state.cleanliness, 67, accuracy: 0.001)
    }

    func testEnergyRisesWhileAsleepAndCapsAt100() {
        let clock = FakeClock()
        var s = NeedsState.fresh(at: clock.now)
        s.isAsleep = true
        let engine = makeEngine(clock, state: s)
        clock.advance(3600 * 3)
        engine.tick()
        XCTAssertEqual(engine.state.energy, 100)
    }

    func testLiveTickClampsAtZero() {
        let clock = FakeClock()
        let engine = makeEngine(clock)
        clock.advance(3600 * 20)
        engine.tick()
        XCTAssertEqual(engine.state.hunger, 0)
    }

    func testOfflineCatchUpStopsAtFloor() {
        let clock = FakeClock()
        let engine = makeEngine(clock)
        clock.advance(3600 * 48)
        let away = engine.catchUpOffline()
        XCTAssertEqual(away, 3600 * 48, accuracy: 0.001)
        for need in Need.allCases { XCTAssertEqual(engine.state[need], 15, accuracy: 0.001) }
    }

    func testOfflineCatchUpDoesNotRaiseStatsAlreadyBelowFloor() {
        let clock = FakeClock()
        var s = NeedsState.fresh(at: clock.now)
        s.hunger = 5
        let engine = makeEngine(clock, state: s)
        clock.advance(3600)
        engine.catchUpOffline()
        XCTAssertEqual(engine.state.hunger, 5)
    }

    func testClockGoingBackwardsChangesNothing() {
        let clock = FakeClock()
        let engine = makeEngine(clock)
        clock.advance(-3600)
        XCTAssertEqual(engine.catchUpOffline(), 0)
        engine.tick()
        for need in Need.allCases { XCTAssertEqual(engine.state[need], 70) }
    }

    func testIsLowUsesThreshold() {
        let clock = FakeClock()
        var s = NeedsState.fresh(at: clock.now)
        s.hunger = 29.9
        s.energy = 30
        let engine = makeEngine(clock, state: s)
        XCTAssertTrue(engine.isLow(.hunger))
        XCTAssertFalse(engine.isLow(.energy))
    }
}

final class CareActionTests: XCTestCase {
    func engine(_ clock: FakeClock) -> NeedsEngine {
        NeedsEngine(state: .fresh(at: clock.now), config: .default, clock: clock)
    }

    func testFeedPlayBathRestoreAndCapAt100() {
        let clock = FakeClock()
        let e = engine(clock)
        e.feed()
        XCTAssertEqual(e.state.hunger, 100)
        e.bath()
        XCTAssertEqual(e.state.cleanliness, 100)
        e.play()
        XCTAssertEqual(e.state.happiness, 95)
        XCTAssertEqual(e.state.careXP, 3)
    }

    func testPetIsRateLimitedToTenPerMinute() {
        let clock = FakeClock()
        var s = NeedsState.fresh(at: clock.now)
        s.happiness = 0
        let e = NeedsEngine(state: s, config: .default, clock: clock)
        for _ in 0..<10 { XCTAssertTrue(e.pet()); clock.advance(1) }
        XCTAssertFalse(e.pet())
        XCTAssertEqual(e.state.happiness, 50, accuracy: 0.1)
        XCTAssertEqual(e.state.careXP, 10)
        clock.advance(60)
        XCTAssertTrue(e.pet())
    }

    func testActionsApplyPendingDecayFirst() {
        let clock = FakeClock()
        let e = engine(clock)
        clock.advance(3600)
        e.bath()
        XCTAssertEqual(e.state.hunger, 62, accuracy: 0.001)
        XCTAssertEqual(e.state.cleanliness, 100)
    }

    func testSetAsleepSwitchesEnergyRate() {
        let clock = FakeClock()
        let e = engine(clock)
        e.setAsleep(true)
        clock.advance(3600)
        e.tick()
        XCTAssertEqual(e.state.energy, 90, accuracy: 0.001)
        e.setAsleep(false)
        clock.advance(3600)
        e.tick()
        XCTAssertEqual(e.state.energy, 84, accuracy: 0.001)
    }

    func testMarkSavedStampsNow() {
        let clock = FakeClock()
        let e = engine(clock)
        clock.advance(120)
        e.markSaved()
        XCTAssertEqual(e.state.lastSaved, clock.now)
    }

    func testLevelGrowsWithCareXP() {
        let clock = FakeClock()
        var s = NeedsState.fresh(at: clock.now)
        let cases: [(Int, Int)] = [(0, 1), (9, 1), (10, 2), (40, 3), (90, 4)]
        for (xp, level) in cases {
            s.careXP = xp
            XCTAssertEqual(NeedsEngine(state: s, clock: clock).level, level, "xp \(xp)")
        }
    }
}
