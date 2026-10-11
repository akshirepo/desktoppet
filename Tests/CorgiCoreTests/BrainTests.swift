import XCTest
@testable import CorgiCore

final class BrainTests: XCTestCase {
    func ctx(hunger: Double = 70, happiness: Double = 70, energy: Double = 70,
             asleep: Bool = false, canHop: Bool = true) -> BrainContext {
        var s = NeedsState.fresh(at: Date(timeIntervalSince1970: 0))
        s.hunger = hunger
        s.happiness = happiness
        s.energy = energy
        s.isAsleep = asleep
        return BrainContext(needs: s, lowThreshold: 30, canHop: canHop)
    }

    func brain(seed: UInt64 = 1) -> Brain { Brain(rng: SeededRandom(seed: seed)) }

    func testSeededRandomIsDeterministic() {
        var a = SeededRandom(seed: 42), b = SeededRandom(seed: 42)
        XCTAssertEqual((0..<5).map { _ in a.next() }, (0..<5).map { _ in b.next() })
    }

    func testOnlyAutonomousBehaviorsHaveWeight() {
        let w = brain().weights(ctx())
        for b in Behavior.allCases where !Behavior.autonomous.contains(b) {
            XCTAssertNil(w[b], "\(b)")
        }
    }

    func testLowEnergyFavorsSleepAndBlocksActiveBehaviors() {
        let w = brain().weights(ctx(energy: 10))
        XCTAssertEqual(w[.zoomies], 0)
        XCTAssertEqual(w[.chaseCursor], 0)
        XCTAssertEqual(w[.hopToWindow], 0)
        XCTAssertGreaterThan(w[.sleep]!, w.values.filter { $0 != w[.sleep]! }.max()!)
    }

    func testLowHungerFavorsBeg() {
        XCTAssertEqual(brain().weights(ctx())[.beg], 0)
        XCTAssertGreaterThan(brain().weights(ctx(hunger: 10))[.beg]!, 5)
    }

    func testHappyAndRestedBoostsPlayfulBehaviors() {
        let normal = brain().weights(ctx(happiness: 50, energy: 50))
        let happy = brain().weights(ctx(happiness: 90, energy: 90))
        for b in [Behavior.zoomies, .chaseCursor, .hopToWindow] {
            XCTAssertGreaterThan(happy[b]!, normal[b]!, "\(b)")
        }
    }

    func testCannotHopWhenNoPerchReachable() {
        XCTAssertEqual(brain().weights(ctx(canHop: false))[.hopToWindow], 0)
    }

    func testChoiceFollowsWeightsOverManyPicks() {
        let b = brain(seed: 7)
        let c = ctx(energy: 5)
        let picks = (0..<500).map { _ in b.choose(c) }
        let sleeps = picks.filter { $0 == .sleep }.count
        XCTAssertGreaterThan(sleeps, 200)   // expected share is about 54%
        XCTAssertFalse(picks.contains(.zoomies))
    }

    func testUpdateSwitchesWhenDurationEnds() {
        let b = brain()
        let rested = ctx(energy: 100)                    // rested, so sleep is never picked
        XCTAssertNotNil(b.update(dt: 0, rested))         // first pick
        let first = b.current
        XCTAssertNil(b.update(dt: 0.5, rested))
        XCTAssertEqual(b.current, first)
        XCTAssertNotNil(b.update(dt: 1000, rested))
    }

    func testInterruptOverridesAndFinishCurrentRepicks() {
        let b = brain()
        b.update(dt: 0, ctx())
        b.interrupt(with: .eat, duration: 3)
        XCTAssertEqual(b.current, .eat)
        XCTAssertNil(b.update(dt: 1, ctx()))
        XCTAssertEqual(b.current, .eat)
        b.finishCurrent()
        XCTAssertNotNil(b.update(dt: 0, ctx()))
        XCTAssertTrue(Behavior.autonomous.contains(b.current))
    }

    func testKeepsSleepingUntilRested() {
        let b = brain()
        b.interrupt(with: .sleep, duration: 1)
        XCTAssertNil(b.update(dt: 2, ctx(energy: 60, asleep: true)))
        XCTAssertEqual(b.current, .sleep)
        XCTAssertNotNil(b.update(dt: 20, ctx(energy: 96, asleep: true)))
        XCTAssertNotEqual(b.current, .sleep)
    }
}
