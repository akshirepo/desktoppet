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
        .eatHalf: .lie, .eatEmpty: .lie, .drinkHalf: .lie, .drinkEmpty: .lie,
    ]
}

/// Bridge animations a pack can provide, by name:
/// - between hub poses: `stand>sit`, `sit>stand`, `sit>sleep`, `sleep>sit` (idle, sit and sleep are the hubs);
/// - into and out of an activity from its hub: `enter:watch`, `exit:watch`. A pack without an exit can
///   point it at the entry's frames played backwards;
/// - straight between two activities drawn in the same view: `pair:walk>fetch`.
public enum Bridge {
    public static func hop(_ a: AnimState, _ b: AnimState) -> String { "\(hubName(a))>\(hubName(b))" }
    public static func enter(_ s: AnimState) -> String { "enter:\(s.rawValue)" }
    public static func exit(_ s: AnimState) -> String { "exit:\(s.rawValue)" }
    /// A direct bridge between two specific activities, e.g. "pair:walk>fetch".
    public static func pair(_ a: AnimState, _ b: AnimState) -> String { "pair:\(a.rawValue)>\(b.rawValue)" }

    static func hubName(_ s: AnimState) -> String { s == .idle ? "stand" : s.rawValue }
}

public enum TransitionStep: Equatable {
    /// Keep the current loop going until its next natural break (a footstep, a finished bite).
    case finish(AnimState)
    /// Show a stepping-stone pose briefly.
    case hold(AnimState, TimeInterval)
    /// Play one full cycle, like a yawn before lying down to sleep.
    case once(AnimState)
    /// Play a named bridge animation once. `endsAt` is the pose it finishes in, used if plans change halfway.
    case bridge(String, endsAt: AnimState)

    public var state: AnimState {
        switch self {
        case .finish(let s), .hold(let s, _), .once(let s), .bridge(_, let s): return s
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
    /// Pairs drawn to follow each other directly. Packs add their own with `directGroups`.
    public var direct: Set<[AnimState]> = []
    /// Bridge animations this pet has art for (see `Bridge`).
    public var bridges: Set<String>

    public init(postures: [AnimState: Posture] = Posture.defaults, bridges: Set<String> = [],
                direct extra: Set<[AnimState]> = []) {
        self.postures = postures
        self.bridges = bridges
        direct.formUnion(extra)
    }

    /// The hub pose an activity is entered from: idle for standing ones, sit for sitting ones and for
    /// lying activities like watching TV or eating, and sleep only for sleep itself.
    public func hub(_ s: AnimState) -> AnimState? {
        guard let p = postures[s] else { return nil }
        if s == .sleep { return .sleep }
        return p == .stand ? .idle : .sit
    }

    private static let hubs: [AnimState] = [.idle, .sit, .sleep]

    /// Steps to show before `to` starts looping. Empty means switch straight away.
    /// Poses without a posture (falling, clinging, reactions) always switch directly.
    public func plan(from: AnimState, to: AnimState) -> [TransitionStep] {
        guard from != to, postures[from] != nil, postures[to] != nil else { return [] }
        // Bowl versions of one loop swap in place.
        if from.base == to.base { return [] }
        if bridges.contains(Bridge.pair(from, to)) {
            return (finishParts[from] != nil ? [.finish(from)] : []) + [.bridge(Bridge.pair(from, to), endsAt: to)]
        }
        guard let a = postures[from], let b = postures[to], !direct.contains([from.base, to.base]),
              let hf = hub(from), let ht = hub(to) else { return [] }
        var steps: [TransitionStep] = []
        // Already lying down (watching TV, say) with no way to get up drawn, it just dozes off.
        if to == .sleep && a == .lie && !bridges.contains(Bridge.exit(from)) && !bridges.contains(Bridge.exit(from.base)) {
            return finishParts[from.base] != nil ? [.finish(from)] : []
        }
        // Leaving a bowl half or fully eaten uses the matching exit art when there is one.
        let exitName = bridges.contains(Bridge.exit(from)) ? Bridge.exit(from) : Bridge.exit(from.base)
        // Exit art starts on the loop's first frame, so finish the current cycle before leaving.
        if finishParts[from.base] != nil || (from != hf && bridges.contains(exitName)) { steps.append(.finish(from)) }

        var art = false
        func bridge(_ name: String, endsAt: AnimState) {
            guard bridges.contains(name) else { return }
            steps.append(.bridge(name, endsAt: endsAt))
            art = true
        }
        if from != hf { bridge(exitName, endsAt: hf) }
        var r = Self.hubs.firstIndex(of: hf)!
        let end = Self.hubs.firstIndex(of: ht)!
        while r != end {
            let next = r + (end > r ? 1 : -1)
            let (x, y) = (Self.hubs[r], Self.hubs[next])
            // Sit and yawn before lying down to sleep.
            if y == .sleep && from != .yawn { steps.append(.once(.yawn)) }
            bridge(Bridge.hop(x, y), endsAt: y)
            // Wake with a sitting yawn, then get up.
            if x == .sleep && to != .yawn { steps.append(.once(.yawn)) }
            r = next
        }
        if to != ht { bridge(Bridge.enter(to), endsAt: to) }
        // With no art for it at all, standing to lying (and back) still pauses in a sit.
        if !art && Set([a, b]) == [.stand, .lie] && !steps.contains(.once(.yawn)) {
            steps.append(.hold(.sit, bridgeHold))
        }
        return steps
    }
}
