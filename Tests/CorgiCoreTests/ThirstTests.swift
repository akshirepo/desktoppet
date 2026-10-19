import XCTest
@testable import CorgiCore

final class ThirstTests: XCTestCase {
    func testThirstIsANeedThatStartsAtSeventy() {
        XCTAssertTrue(Need.allCases.contains(.thirst))
        XCTAssertEqual(NeedsState.fresh(at: Date(timeIntervalSince1970: 0)).thirst, 70)
    }

    func testThirstDropsFasterThanHunger() {
        let clock = FakeClock()
        let e = NeedsEngine(state: .fresh(at: clock.now), clock: clock)
        clock.advance(3600)
        e.tick()
        XCTAssertEqual(e.state.thirst, 60, accuracy: 0.001)
        XCTAssertLessThan(e.state.thirst, e.state.hunger)
    }

    func testDrinkRefillsThirstAndCountsAsCare() {
        let clock = FakeClock()
        var s = NeedsState.fresh(at: clock.now)
        s.thirst = 20
        let e = NeedsEngine(state: s, clock: clock)
        e.drink()
        XCTAssertEqual(e.state.thirst, 70, accuracy: 0.001)
        XCTAssertEqual(e.state.careXP, 1)
        e.drink()
        XCTAssertEqual(e.state.thirst, 100)
    }

    func testOfflineThirstStopsAtTheFloor() {
        let clock = FakeClock()
        let e = NeedsEngine(state: .fresh(at: clock.now), clock: clock)
        clock.advance(3600 * 48)
        e.catchUpOffline()
        XCTAssertEqual(e.state.thirst, 15, accuracy: 0.001)
    }

    func testOldSavesWithoutThirstLoadAtSeventy() throws {
        var s = NeedsState.fresh(at: Date(timeIntervalSince1970: 100))
        s.hunger = 33
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
        json.removeValue(forKey: "thirst")
        let old = try JSONDecoder().decode(NeedsState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.thirst, 70)
        XCTAssertEqual(old.hunger, 33)
    }

    func testThirstSpeaksAndAsksForCare() {
        XCTAssertEqual(SpeechLibrary.category(for: .thirst, variant: 0), "thirsty")
        var s = NeedsState.fresh(at: Date(timeIntervalSince1970: 0))
        s.thirst = 5
        XCTAssertEqual(CareAsker().next(needs: s, now: Date(timeIntervalSince1970: 0), blocked: false), .thirst)
    }
}
