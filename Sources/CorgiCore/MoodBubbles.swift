import Foundation

/// Decides when to show a "💭" thought bubble for a low need. Pure timing, driven by `dt`.
public struct MoodBubbles {
    public var firstDelay: TimeInterval
    public var repeatInterval: TimeInterval
    public var lowThreshold: Double

    private var lowFor: TimeInterval = 0
    private var nextAt: TimeInterval

    public init(firstDelay: TimeInterval = 10, repeatInterval: TimeInterval = 60,
                lowThreshold: Double = NeedsConfig.default.lowThreshold) {
        self.firstDelay = firstDelay
        self.repeatInterval = repeatInterval
        self.lowThreshold = lowThreshold
        self.nextAt = firstDelay
    }

    /// Call every frame. `blocked` is true while asleep, held, or roaming; it suppresses and resets.
    /// Returns the need to show a bubble for, or nil.
    public mutating func update(dt: TimeInterval, needs: NeedsState, blocked: Bool) -> Need? {
        guard !blocked, let need = MoodBubbles.lowestLowNeed(in: needs, threshold: lowThreshold) else {
            reset()
            return nil
        }
        lowFor += max(0, dt)
        guard lowFor >= nextAt else { return nil }
        nextAt = lowFor + repeatInterval
        return need
    }

    public mutating func reset() {
        lowFor = 0
        nextAt = firstDelay
    }

    /// The lowest need below `threshold`, ties going to `Need.allCases` order.
    public static func lowestLowNeed(in needs: NeedsState,
                                     threshold: Double = NeedsConfig.default.lowThreshold) -> Need? {
        var best: Need?
        for need in Need.allCases where needs[need] < threshold {
            if best == nil || needs[need] < needs[best!] { best = need }
        }
        return best
    }

    public static func emoji(for need: Need) -> String {
        switch need {
        case .hunger: return "🍖"
        case .cleanliness: return "🛁"
        case .energy: return "💤"
        case .happiness: return "🎾"
        }
    }

    public static func bubbleText(for need: Need) -> String { "💭" + emoji(for: need) }
}
