import Foundation

/// How the pet is holding itself in a pose. Changes between postures go through the neighbouring
/// one (stand ↔ sit ↔ lie) so it never jumps from walking straight into a curled-up sleep.
public enum Posture: String, Codable {
    case stand, sit, lie

    /// Default postures shared by both pets. A pack can override one with `"posture"` in its manifest.
    public static let defaults: [AnimState: Posture] = [
        .idle: .stand, .walk: .stand, .run: .stand, .kick: .stand, .thirsty: .stand, .back: .stand,
        .wiggle: .stand, .fetch: .stand, .bath: .stand,
        .sit: .sit, .yawn: .sit, .beg: .sit, .read: .sit, .readSleep: .sit, .music: .sit, .happy: .sit,
        .wave: .sit, .refreshed: .sit,
        .sleep: .lie, .eat: .lie, .drink: .lie, .watch: .lie,
    ]
}

public enum TransitionStep: Equatable {
    /// Keep the current loop going until its next natural break (a footstep, a finished bite).
    case finish(AnimState)
    /// Show a stepping-stone pose briefly.
    case hold(AnimState, TimeInterval)
    /// Play one full cycle, like a yawn before lying down to sleep.
    case once(AnimState)

    public var state: AnimState {
        switch self {
        case .finish(let s), .hold(let s, _), .once(let s): return s
        }
    }
}

/// Plans the in-between poses from one looping animation to another.
public struct TransitionGraph {
    public var postures: [AnimState: Posture]
    /// How long a stepping-stone pose shows.
    public var bridgeHold: TimeInterval = 0.45
    /// Loops that finish their current cycle (or step) before changing, and into how many parts the cycle
    /// splits: a walk cycle has two footfalls, a bite or a lap is the whole cycle.
    public var finishParts: [AnimState: Int] = [.walk: 2, .run: 2, .eat: 1, .drink: 1, .kick: 1]
    /// Pairs drawn to follow each other directly.
    public var direct: Set<[AnimState]> = [[.drink, .refreshed], [.read, .readSleep], [.readSleep, .read],
                                           [.sleep, .yawn], [.yawn, .sleep]]

    public init(postures: [AnimState: Posture] = Posture.defaults) {
        self.postures = postures
    }

    /// Steps to show before `to` starts looping. Empty means switch straight away.
    /// Poses without a posture (falling, clinging, reactions) always switch directly.
    public func plan(from: AnimState, to: AnimState) -> [TransitionStep] {
        guard from != to, let a = postures[from], let b = postures[to], !direct.contains([from, to]) else { return [] }
        var steps: [TransitionStep] = []
        if finishParts[from] != nil { steps.append(.finish(from)) }
        if from == .sleep {
            // Wake with a sitting yawn, then get up.
            steps.append(.once(.yawn))
            return steps
        }
        if to == .sleep {
            // Sit and yawn before lying down. Already lying (watching TV, say) it just dozes off.
            if a != .lie && from != .yawn { steps.append(.once(.yawn)) }
            return steps
        }
        // Standing to lying and back goes through a sit.
        if (a == .stand && b == .lie) || (a == .lie && b == .stand) { steps.append(.hold(.sit, bridgeHold)) }
        return steps
    }
}
