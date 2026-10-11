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
