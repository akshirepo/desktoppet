import XCTest
@testable import CorgiCore

final class MoodBubblesTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 0)

    func needs(hunger: Double = 70, happiness: Double = 70,
               energy: Double = 70, cleanliness: Double = 70) -> NeedsState {
        var s = NeedsState.fresh(at: t0)
        s.hunger = hunger; s.happiness = happiness; s.energy = energy; s.cleanliness = cleanliness
        return s
    }

    /// Steps in 1s ticks and returns the elapsed second at which each bubble showed.
    func run(_ m: inout MoodBubbles, seconds: Int, _ n: NeedsState, blocked: Bool = false) -> [(Int, Need)] {
        var out: [(Int, Need)] = []
        for i in 1...seconds {
            if let need = m.update(dt: 1, needs: n, blocked: blocked) { out.append((i, need)) }
        }
        return out
    }

    func testDefaults() {
        let m = MoodBubbles()
        XCTAssertEqual(m.firstDelay, 10)
        XCTAssertEqual(m.repeatInterval, 60)
        XCTAssertEqual(m.lowThreshold, 30)
    }

    func testNoBubbleWhenAllNeedsFine() {
        var m = MoodBubbles()
        XCTAssertTrue(run(&m, seconds: 300, needs()).isEmpty)
        XCTAssertTrue(run(&m, seconds: 100, needs(hunger: 30)).isEmpty, "30 is not below 30")
    }

    func testFirstBubbleAfter10s() {
        var m = MoodBubbles()
        let shown = run(&m, seconds: 15, needs(hunger: 20))
        XCTAssertEqual(shown.map(\.0), [10])
        XCTAssertEqual(shown.map(\.1), [.hunger])
    }

    func testRepeatsEvery60s() {
        var m = MoodBubbles()
        let shown = run(&m, seconds: 200, needs(energy: 10))
        XCTAssertEqual(shown.map(\.0), [10, 70, 130, 190])
        XCTAssertTrue(shown.allSatisfy { $0.1 == .energy })
    }

    func testLowestNeedWins() {
        var m = MoodBubbles()
        let shown = run(&m, seconds: 10, needs(hunger: 25, happiness: 5, energy: 20, cleanliness: 15))
        XCTAssertEqual(shown.map(\.1), [.happiness])
        XCTAssertEqual(MoodBubbles.lowestLowNeed(in: needs(energy: 29, cleanliness: 2)), .cleanliness)
        XCTAssertNil(MoodBubbles.lowestLowNeed(in: needs()))
    }

    func testLowestNeedIsPickedAtShowTime() {
        var m = MoodBubbles()
        _ = run(&m, seconds: 5, needs(hunger: 20))
        let shown = run(&m, seconds: 5, needs(hunger: 20, cleanliness: 10))
        XCTAssertEqual(shown.map(\.1), [.cleanliness])
    }

    func testBlockedSuppressesAndResets() {
        var m = MoodBubbles()
        let low = needs(hunger: 10)
        XCTAssertTrue(run(&m, seconds: 9, low).isEmpty)
        XCTAssertTrue(run(&m, seconds: 120, low, blocked: true).isEmpty)
        let shown = run(&m, seconds: 15, low)
        XCTAssertEqual(shown.map(\.0), [10], "first delay restarts after unblocking")
    }

    func testBlockedAfterBubbleRestartsFirstDelay() {
        var m = MoodBubbles()
        let low = needs(hunger: 10)
        XCTAssertEqual(run(&m, seconds: 10, low).count, 1)
        _ = run(&m, seconds: 3, low, blocked: true)
        XCTAssertEqual(run(&m, seconds: 12, low).map(\.0), [10])
    }

    func testRecoveringResetsTimer() {
        var m = MoodBubbles()
        _ = run(&m, seconds: 8, needs(hunger: 10))
        _ = run(&m, seconds: 1, needs())
        XCTAssertEqual(run(&m, seconds: 12, needs(hunger: 10)).map(\.0), [10])
    }

    func testLargeDtShowsOnce() {
        var m = MoodBubbles()
        XCTAssertEqual(m.update(dt: 500, needs: needs(hunger: 1), blocked: false), .hunger)
        XCTAssertNil(m.update(dt: 1, needs: needs(hunger: 1), blocked: false))
    }

    func testCustomTiming() {
        var m = MoodBubbles(firstDelay: 2, repeatInterval: 5, lowThreshold: 50)
        XCTAssertEqual(run(&m, seconds: 12, needs(hunger: 45)).map(\.0), [2, 7, 12])
    }

    func testEmojiAndText() {
        XCTAssertEqual(MoodBubbles.emoji(for: .hunger), "🍖")
        XCTAssertEqual(MoodBubbles.emoji(for: .cleanliness), "🛁")
        XCTAssertEqual(MoodBubbles.emoji(for: .energy), "💤")
        XCTAssertEqual(MoodBubbles.emoji(for: .happiness), "🎾")
        XCTAssertEqual(MoodBubbles.bubbleText(for: .hunger), "💭🍖")
    }
}
