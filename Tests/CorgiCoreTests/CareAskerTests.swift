import XCTest
@testable import CorgiCore

final class CareAskerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func needs(hunger: Double = 70, happiness: Double = 70, energy: Double = 70, cleanliness: Double = 70) -> NeedsState {
        var s = NeedsState.fresh(at: t0)
        s.hunger = hunger; s.happiness = happiness; s.energy = energy; s.cleanliness = cleanliness
        return s
    }

    func testAsksForTheLowestLowNeed() {
        var asker = CareAsker()
        XCTAssertNil(asker.next(needs: needs(), now: t0, blocked: false))
        XCTAssertEqual(asker.next(needs: needs(hunger: 20, cleanliness: 10), now: t0, blocked: false), .cleanliness)
    }

    func testNeverAsksWhileBlocked() {
        var asker = CareAsker()
        XCTAssertNil(asker.next(needs: needs(hunger: 5), now: t0, blocked: true))
    }

    func testEachNeedWaitsThirtyMinutesBeforeAskingAgain() {
        var asker = CareAsker()
        XCTAssertEqual(asker.cooldown, 30 * 60)
        let hungry = needs(hunger: 10)
        XCTAssertEqual(asker.next(needs: hungry, now: t0, blocked: false), .hunger)
        asker.markAsked(.hunger, at: t0)
        XCTAssertNil(asker.next(needs: hungry, now: t0.addingTimeInterval(29 * 60), blocked: false))
        XCTAssertEqual(asker.next(needs: hungry, now: t0.addingTimeInterval(30 * 60), blocked: false), .hunger)
    }

    func testOtherNeedsWaitAShortGapAfterAnyRequest() {
        var asker = CareAsker()
        asker.markAsked(.hunger, at: t0)
        let both = needs(hunger: 10, energy: 20)
        XCTAssertNil(asker.next(needs: both, now: t0.addingTimeInterval(asker.minGap - 1), blocked: false))
        XCTAssertEqual(asker.next(needs: both, now: t0.addingTimeInterval(asker.minGap), blocked: false), .energy)
    }

    func testClockGoingBackwardsDoesNotUnlockARequest() {
        var asker = CareAsker()
        asker.markAsked(.hunger, at: t0)
        XCTAssertNil(asker.next(needs: needs(hunger: 10), now: t0.addingTimeInterval(-3600), blocked: false))
    }

    func testAskForCareSettingIsOnByDefaultAndRemembered() throws {
        XCTAssertTrue(PetProfile().askForCare)
        let old = try JSONDecoder().decode(PetProfile.self, from: Data(#"{"character":"corgi"}"#.utf8))
        XCTAssertTrue(old.askForCare)
        var p = PetProfile()
        p.askForCare = false
        XCTAssertFalse(try JSONDecoder().decode(PetProfile.self, from: JSONEncoder().encode(p)).askForCare)
    }

    func testComesForAttentionAfterFifteenQuietMinutesThenEveryTwenty() {
        var a = CareAsker()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(a.wantsAttention(secondsSinceInteraction: 14 * 60, now: t0, blocked: false))
        XCTAssertFalse(a.wantsAttention(secondsSinceInteraction: 15 * 60, now: t0, blocked: true))
        XCTAssertTrue(a.wantsAttention(secondsSinceInteraction: 15 * 60, now: t0, blocked: false))
        a.markSoughtAttention(at: t0)
        XCTAssertFalse(a.wantsAttention(secondsSinceInteraction: 30 * 60, now: t0.addingTimeInterval(19 * 60), blocked: false))
        XCTAssertTrue(a.wantsAttention(secondsSinceInteraction: 35 * 60, now: t0.addingTimeInterval(20 * 60), blocked: false))
    }

    func testDoesNotSeekAttentionRightAfterACareRequest() {
        var a = CareAsker()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        a.markAsked(.hunger, at: t0)
        XCTAssertFalse(a.wantsAttention(secondsSinceInteraction: 20 * 60, now: t0.addingTimeInterval(30), blocked: false))
        XCTAssertTrue(a.wantsAttention(secondsSinceInteraction: 20 * 60, now: t0.addingTimeInterval(61), blocked: false))
    }
}
