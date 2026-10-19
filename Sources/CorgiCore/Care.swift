import Foundation

/// Decides when the pet should come to the cursor and ask for something it needs.
/// Each need asks at most once per `cooldown`, and any two requests are at least `minGap` apart.
public struct CareAsker {
    public var cooldown: TimeInterval = 30 * 60
    public var minGap: TimeInterval = 5 * 60
    public var lowThreshold: Double = NeedsConfig.default.lowThreshold
    private var lastAsked: [Need: Date] = [:]
    private var lastAny: Date?

    public init() {}

    /// The need to ask about now, or nil. `blocked` covers everything that should keep it from interrupting.
    public func next(needs: NeedsState, now: Date, blocked: Bool) -> Need? {
        guard !blocked else { return nil }
        if let any = lastAny, !(now.timeIntervalSince(any) >= minGap) { return nil }
        let candidates = Need.allCases.filter { need in
            guard needs[need] < lowThreshold else { return false }
            guard let last = lastAsked[need] else { return true }
            return now.timeIntervalSince(last) >= cooldown
        }
        return candidates.min { needs[$0] < needs[$1] }
    }

    public mutating func markAsked(_ need: Need, at time: Date) {
        lastAsked[need] = time
        lastAny = time
    }
}
