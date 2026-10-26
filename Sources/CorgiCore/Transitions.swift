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
        // A bridge counts as where it's heading, so a change of plan halfway turns back sensibly.
        .standToSit: .sit, .sitToStand: .stand, .sitToLie: .lie, .lieToSit: .sit,
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
    public var direct: Set<[AnimState]> = [[.drink, .refreshed], [.read, .readSleep], [.readSleep, .read]]
    /// Bridge animations this pet has art for (`standToSit` and friends).
    public var bridges: Set<AnimState>

    public init(postures: [AnimState: Posture] = Posture.defaults, bridges: Set<AnimState> = []) {
        self.postures = postures
        self.bridges = bridges
    }

    private func bridge(_ a: Posture, _ b: Posture) -> AnimState? {
        let s: AnimState?
        switch (a, b) {
        case (.stand, .sit): s = .standToSit
        case (.sit, .stand): s = .sitToStand
        case (.sit, .lie): s = .sitToLie
        case (.lie, .sit): s = .lieToSit
        default: s = nil
        }
        return s.flatMap { bridges.contains($0) ? $0 : nil }
    }

    /// Steps to show before `to` starts looping. Empty means switch straight away.
    /// Poses without a posture (falling, clinging, reactions) always switch directly.
    public func plan(from: AnimState, to: AnimState) -> [TransitionStep] {
        guard from != to, let a = postures[from], let b = postures[to], !direct.contains([from, to]) else { return [] }
        var steps: [TransitionStep] = []
        if finishParts[from] != nil { steps.append(.finish(from)) }
        let bedtime = to == .sleep, waking = from == .sleep && to != .yawn
        // Sit and yawn before lying down to sleep. Already lying (watching TV, say) it just dozes off.
        if bedtime && a == .sit && from != .yawn { steps.append(.once(.yawn)) }

        // Standing to lying and back goes through a sit.
        var path = [a]
        if (a == .stand && b == .lie) || (a == .lie && b == .stand) { path.append(.sit) }
        if a != b { path.append(b) }
        for i in 1..<path.count {
            let (p, q) = (path[i - 1], path[i])
            let via = bridge(p, q)
            if let via { steps.append(.once(via)) }
            guard q == .sit else { continue }
            let waypoint = i < path.count - 1
            if waking {
                steps.append(.once(.yawn))           // wake with a sitting yawn, then get up
            } else if waypoint && bedtime {
                steps.append(.once(.yawn))
            } else if waypoint && via == nil && bridge(q, path[i + 1]) == nil {
                steps.append(.hold(.sit, bridgeHold))
            }
        }
        return steps
    }
}
