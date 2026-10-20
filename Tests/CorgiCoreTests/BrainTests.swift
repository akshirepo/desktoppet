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
        XCTAssertGreaterThan(sleeps, 200)   // expected share is about 49%
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

    func testSleepLikeBehaviorsCountAsSleepAndFinishWakes() {
        XCTAssertEqual(Behavior.allCases.filter(\.countsAsSleep), [.sleep, .readSleep, .idleSleep])
        let b = brain()
        b.interrupt(with: .readSleep, duration: 60)
        b.finishCurrent()
        XCTAssertEqual(b.current, .idle)
        XCTAssertNotNil(b.update(dt: 0, ctx()))
    }

    func homeCtx(atHome: Bool, away: TimeInterval = 0, bored: Bool = false,
                 energy: Double = 70) -> BrainContext {
        var c = ctx(energy: energy)
        c.atHome = atHome
        c.secondsAwayFromHome = away
        c.bored = bored
        c.secondsSinceInteraction = 300   // between "just interacted" and "left alone"
        return c
    }

    func testIdleActivitiesWeightedHigherAtHome() {
        let away = brain().weights(homeCtx(atHome: false))
        let home = brain().weights(homeCtx(atHome: true))
        for b in [Behavior.read, .music, .watchTV, .playBallHome] {
            XCTAssertEqual(home[b]!, away[b]! * 3, accuracy: 0.001, "\(b)")
        }
        for b in [Behavior.wave, .turnAround] { XCTAssertEqual(home[b]!, away[b]! * 2, accuracy: 0.001, "\(b)") }
        for b in [Behavior.walk, .zoomies, .hopToWindow] { XCTAssertEqual(home[b]!, away[b]! * 0.5, accuracy: 0.001, "\(b)") }
    }

    func testGoHomeGrowsWithTimeAwayAndCapsAtEight() {
        XCTAssertEqual(brain().weights(homeCtx(atHome: false, away: 0))[.goHome], 0)
        XCTAssertEqual(brain().weights(homeCtx(atHome: false, away: 120))[.goHome]!, 2, accuracy: 0.001)
        XCTAssertEqual(brain().weights(homeCtx(atHome: false, away: 3600))[.goHome], 8)
        XCTAssertEqual(brain().weights(homeCtx(atHome: true, away: 3600))[.goHome], 0)
    }

    func testBoredomAddsBallChaseUnlessTired() {
        XCTAssertEqual(brain().weights(homeCtx(atHome: true))[.ballChase], 0)
        XCTAssertEqual(brain().weights(homeCtx(atHome: true, bored: true))[.ballChase], 6)
        XCTAssertEqual(brain().weights(homeCtx(atHome: true, bored: true, energy: 10))[.ballChase], 0)
    }

    func testReadTurnsIntoReadSleepRightAwayWhenTired() {
        let b = brain()
        b.interrupt(with: .read, duration: 40)
        XCTAssertEqual(b.update(dt: 0.1, ctx(energy: 10)), .readSleep)
        XCTAssertTrue(b.current.countsAsSleep)
    }

    func testReadDozesOnceAfterFifteenSecondsAboutThirtyPercent() {
        var dozed = 0
        for seed in UInt64(1)...200 {
            let b = brain(seed: seed)
            b.interrupt(with: .read, duration: 60)
            XCTAssertNil(b.update(dt: 14.9, ctx()))
            if b.update(dt: 0.2, ctx()) == .readSleep {
                dozed += 1
            } else {
                XCTAssertNil(b.update(dt: 10, ctx()))   // the roll happens only once
                XCTAssertEqual(b.current, .read)
            }
        }
        XCTAssertTrue((40...80).contains(dozed), "\(dozed)")   // expected about 60
    }
}
