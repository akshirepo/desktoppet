import XCTest
@testable import CorgiCore

final class RoutineTests: XCTestCase {
    func ctx(hunger: Double = 70, thirst: Double = 70, energy: Double = 70, sinceInteraction: TimeInterval = 0,
             atHome: Bool = true) -> BrainContext {
        var s = NeedsState.fresh(at: Date(timeIntervalSince1970: 0))
        s.hunger = hunger
        s.thirst = thirst
        s.energy = energy
        s.happiness = 70
        return BrainContext(needs: s, lowThreshold: 30, canHop: true, atHome: atHome,
                            secondsSinceInteraction: sinceInteraction)
    }

    func brain(seed: UInt64 = 1) -> Brain { Brain(rng: SeededRandom(seed: seed)) }

    func testRunningMakesItThirstyFastestThenHungryAndTired() {
        let needs = NeedsEngine(state: .fresh(at: Date(timeIntervalSince1970: 0)), clock: FakeClock())
        let before = needs.state
        needs.exert(.hard, seconds: 5 * 60)
        XCTAssertEqual(before.thirst - needs.state.thirst, 25, accuracy: 0.01)
        XCTAssertEqual(before.hunger - needs.state.hunger, 7.5, accuracy: 0.01)
        XCTAssertEqual(before.energy - needs.state.energy, 10, accuracy: 0.01)
        let walked = needs.state
        needs.exert(.light, seconds: 60)
        XCTAssertLessThan(needs.state.thirst, walked.thirst)
        XCTAssertEqual(needs.state.energy, walked.energy)
        needs.exert(.rest, seconds: 600)
        XCTAssertEqual(needs.state.thirst, walked.thirst - 0.3, accuracy: 0.01)
        needs.exert(.hard, seconds: 3600)
        XCTAssertEqual(needs.state.thirst, 0)
    }

    func testCatchesItsBreathAfterRunning() {
        for hard in [Behavior.zoomies, .chaseMe, .ballChase, .fetch, .chaseCursor] {
            let b = brain()
            b.interrupt(with: hard, duration: 1)
            XCTAssertEqual(b.update(dt: 2, ctx()), .sit, "\(hard)")
            XCTAssertTrue(b.catchingBreath)
            b.update(dt: 30, ctx())
            XCTAssertFalse(b.catchingBreath)
        }
    }

    func testSitsAfterEating() {
        let b = brain()
        b.interrupt(with: .eat, duration: 1)
        XCTAssertEqual(b.update(dt: 2, ctx()), .sit)
        XCTAssertFalse(b.catchingBreath)
    }

    func testYawnsBeforeBedAndAfterWaking() {
        let b = brain()
        b.interrupt(with: .walk, duration: 1)
        XCTAssertEqual(b.update(dt: 2, ctx(energy: 20)), .yawn)
        XCTAssertEqual(b.update(dt: 5, ctx(energy: 20)), .sleep)
        XCTAssertEqual(b.update(dt: 500, ctx(energy: 100)), .yawn)
        XCTAssertNotEqual(b.update(dt: 5, ctx(energy: 100)), .sleep)
    }

    func testOnlyNapsWhenTired() {
        XCTAssertEqual(brain().weights(ctx(energy: 80))[.sleep], 0)
        XCTAssertGreaterThan(brain().weights(ctx(energy: 35))[.sleep]!, 0)
    }

    func testStaysCloseWhenYouJustInteractedAndTakesUpHobbiesWhenAlone() {
        let engaged = brain().weights(ctx(sinceInteraction: 10))
        let alone = brain().weights(ctx(sinceInteraction: 900))
        for h in Behavior.hobbies { XCTAssertGreaterThan(alone[h]!, engaged[h]! * 5, "\(h)") }
        XCTAssertGreaterThan(engaged[.chaseCursor]!, 2)
        XCTAssertEqual(alone[.chaseCursor], 0)
        XCTAssertGreaterThan(brain().weights(ctx(sinceInteraction: 900, atHome: false))[.goHome]!, 3)
    }

    func testSticksWithAHobbyWhileAlone() {
        var repeats = 0
        for seed in UInt64(1)...200 {
            let b = brain(seed: seed)
            b.interrupt(with: .watchTV, duration: 1)
            if b.update(dt: 2, ctx(sinceInteraction: 900)) == .watchTV { repeats += 1 }
        }
        XCTAssertGreaterThan(repeats, 120)   // 60% stick, plus the odd fresh pick of TV
    }

    func testHungryOrThirstyBegsAndSkipsHobbies() {
        for c in [ctx(hunger: 10, sinceInteraction: 900), ctx(thirst: 10, sinceInteraction: 900)] {
            let w = brain().weights(c)
            XCTAssertGreaterThan(w[.beg]!, 5)
            XCTAssertEqual(w[.zoomies], 0)
            XCTAssertLessThan(w[.watchTV]!, brain().weights(ctx(sinceInteraction: 900))[.watchTV]!)
        }
        let b = brain()
        b.interrupt(with: .watchTV, duration: 1)
        var thirsty = 0
        for _ in 0..<50 {
            b.interrupt(with: .watchTV, duration: 1)
            if b.update(dt: 2, ctx(thirst: 10, sinceInteraction: 900)) == .watchTV { thirsty += 1 }
        }
        XCTAssertLessThan(thirsty, 15)
    }

    func testAsksForWaterSoonerAfterExercise() {
        var s = NeedsState.fresh(at: Date(timeIntervalSince1970: 0))
        s.thirst = 50
        let asker = CareAsker()
        XCTAssertNil(asker.next(needs: s, now: Date(), blocked: false))
        XCTAssertEqual(asker.next(needs: s, now: Date(), blocked: false, afterExercise: true), .thirst)
        s.thirst = 70
        s.cleanliness = 50
        XCTAssertNil(asker.next(needs: s, now: Date(), blocked: false, afterExercise: true))
    }

    func testDrinkingIsItsOwnBehaviorAndShowsTheWaterBowl() {
        XCTAssertEqual(animState(for: .drink, mode: .grounded, isMoving: false), .drink)
        XCTAssertEqual(animState(for: .drink, mode: .airborne, isMoving: false), .fall)
        let b = brain()
        b.interrupt(with: .drink, duration: 1)
        XCTAssertEqual(b.update(dt: 2, ctx()), .sit)
        XCTAssertFalse(Behavior.autonomous.contains(.drink))
    }
}
