import Foundation

public enum Behavior: String, CaseIterable {
    case idle, walk, sit, sleep, zoomies, chaseCursor, hopToWindow, beg
    case eat, fetch, bath, dangle, fall, greet
    case goHome, read, readSleep, music, watchTV, wave, turnAround, playBallHome
    case yawn, idleSleep, chaseMe, ballChase
    /// Came to the cursor to ask for something it needs (food, a bath, play or a nap).
    case askCare
    case cling

    /// Behaviors the brain picks on its own. The rest only happen through `interrupt`.
    public static let autonomous: [Behavior] = [
        .idle, .walk, .sit, .sleep, .zoomies, .chaseCursor, .hopToWindow, .beg,
        .goHome, .read, .music, .watchTV, .wave, .turnAround, .playBallHome, .ballChase,
    ]

    /// Behaviors during which energy refills at the asleep rate.
    public var countsAsSleep: Bool { self == .sleep || self == .readSleep || self == .idleSleep }

    /// Quiet things it does at home when nobody's around.
    public static let hobbies: Set<Behavior> = [.read, .music, .watchTV, .playBallHome]

    /// How hard the behavior works it, for the extra hunger, thirst and energy it costs.
    public var exertion: Exertion {
        switch self {
        case .zoomies, .chaseMe, .ballChase, .fetch, .chaseCursor: return .hard
        case .walk, .hopToWindow, .goHome, .playBallHome, .greet, .askCare: return .light
        default: return .rest
        }
    }
}

public struct BrainConfig {
    public var durations: [Behavior: ClosedRange<Double>] = [
        .idle: 3...8, .walk: 3...8, .sit: 4...10, .sleep: 60...180,
        .zoomies: 4...8, .chaseCursor: 5...5, .hopToWindow: 6...8, .beg: 6...10,
        .goHome: 30...30, .read: 20...60, .readSleep: 30...90, .music: 20...60, .watchTV: 30...90,
        .wave: 2...2, .turnAround: 3...5, .playBallHome: 8...15, .ballChase: 30...30,
        .cling: 180...360, .yawn: 2.5...3,
    ]
    public var wakeEnergy = 95.0
    /// Seconds of reading before the one-time doze roll, and the chance it dozes off.
    public var readDozeAfter = 15.0
    public var readDozeChance = 0.3
    /// Within this long of your last pet, click or care action it stays close and attentive.
    public var engagedFor: TimeInterval = 120
    /// After this long with no attention it settles at home into a hobby.
    public var aloneAfter: TimeInterval = 600
    /// Chance it keeps going with the same hobby instead of picking something new.
    public var hobbyStickiness = 0.6
    /// Below this energy it yawns and goes to sleep instead of picking something else.
    public var bedtimeEnergy = 25.0

    public init() {}
}

public struct BrainContext {
    public var needs: NeedsState
    public var lowThreshold: Double
    public var canHop: Bool
    public var atHome: Bool
    public var secondsAwayFromHome: TimeInterval
    public var bored: Bool
    public var secondsSinceInteraction: TimeInterval

    public init(needs: NeedsState, lowThreshold: Double, canHop: Bool,
                atHome: Bool = false, secondsAwayFromHome: TimeInterval = 0, bored: Bool = false,
                secondsSinceInteraction: TimeInterval = 0) {
        self.secondsSinceInteraction = secondsSinceInteraction
        self.needs = needs
        self.lowThreshold = lowThreshold
        self.canHop = canHop
        self.atHome = atHome
        self.secondsAwayFromHome = secondsAwayFromHome
        self.bored = bored
    }
}

public final class Brain {
    public let config: BrainConfig
    private var rng: any RandomNumberGenerator
    public private(set) var current: Behavior = .idle
    public private(set) var remaining: TimeInterval = 0
    private var readElapsed: TimeInterval = 0
    private var readRolled = false
    /// True while it sits down to catch its breath after running around.
    public private(set) var catchingBreath = false

    public init(config: BrainConfig = .init(), rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.config = config
        self.rng = rng
    }

    private func random() -> Double {
        Double(rng.next() >> 11) / Double(1 << 53)
    }

    public func weights(_ ctx: BrainContext) -> [Behavior: Double] {
        let n = ctx.needs
        var w: [Behavior: Double] = [
            .idle: 3, .walk: 4, .sit: 2, .sleep: 0.5,
            .zoomies: 0.5, .chaseCursor: 0.5, .hopToWindow: 1, .beg: 0,
            .read: 1, .music: 1, .watchTV: 1, .wave: 0.5, .turnAround: 0.5, .playBallHome: 0.5,
            .goHome: ctx.atHome ? 0 : min(8, max(0, ctx.secondsAwayFromHome) / 60),
            .ballChase: ctx.bored ? 6 : 0,
        ]
        if ctx.atHome {
            for b in [Behavior.read, .music, .watchTV, .playBallHome] { w[b]! *= 3 }
            for b in [Behavior.wave, .turnAround] { w[b]! *= 2 }
            for b in [Behavior.walk, .zoomies, .hopToWindow] { w[b]! *= 0.5 }
        }
        if n.happiness > 70 && n.energy > 60 {
            w[.zoomies]! += 1.5
            w[.chaseCursor]! += 1.5
            w[.hopToWindow]! += 1.5
        }
        if n.happiness < ctx.lowThreshold {
            w[.zoomies] = 0
            w[.walk]! *= 0.5
            w[.sit]! += 2
        }
        let engaged = ctx.secondsSinceInteraction < config.engagedFor
        let alone = ctx.secondsSinceInteraction >= config.aloneAfter
        if engaged {
            // You're paying attention, so it hangs around you instead of wandering off to a hobby.
            w[.chaseCursor]! += 2
            w[.wave]! += 1
            w[.sit]! += 1
            for b in Behavior.hobbies { w[b]! *= 0.3 }
        } else if alone {
            for b in Behavior.hobbies { w[b]! *= 3 }
            if !ctx.atHome { w[.goHome]! += 4 }
            w[.walk]! *= 0.5
            w[.chaseCursor] = 0
            w[.wave] = 0
        }
        let peckish = n.hunger < ctx.lowThreshold || n.thirst < ctx.lowThreshold
        if peckish {
            w[.beg]! += 6
            w[.zoomies] = 0
            for b in Behavior.hobbies { w[b]! *= 0.3 }
        }
        // Only naps when it's actually getting tired.
        w[.sleep] = n.energy < 50 ? (50 - n.energy) / 5 : 0
        if n.energy < ctx.lowThreshold {
            w[.sleep]! += 10
            w[.zoomies] = 0
            w[.chaseCursor] = 0
            w[.hopToWindow] = 0
            w[.music] = 0
            w[.wave] = 0
            w[.turnAround] = 0
            w[.playBallHome] = 0
            w[.ballChase] = 0
        }
        if n.energy >= config.wakeEnergy { w[.sleep] = 0 }
        if !ctx.canHop { w[.hopToWindow] = 0 }
        return w
    }

    public func choose(_ ctx: BrainContext) -> Behavior {
        let w = weights(ctx)
        let total = Behavior.autonomous.reduce(0) { $0 + (w[$1] ?? 0) }
        var roll = random() * total
        for b in Behavior.autonomous {
            roll -= w[b] ?? 0
            if roll < 0 { return b }
        }
        return .idle
    }

    @discardableResult
    public func update(dt: TimeInterval, _ ctx: BrainContext) -> Behavior? {
        remaining -= dt
        if current == .read {
            readElapsed += dt
            if ctx.needs.energy < ctx.lowThreshold || (!readRolled && readElapsed >= config.readDozeAfter) {
                let doze = ctx.needs.energy < ctx.lowThreshold || random() < config.readDozeChance
                readRolled = true
                if doze { return start(.readSleep) }
            }
        }
        guard remaining <= 0 else { return nil }
        if current == .sleep && ctx.needs.energy < config.wakeEnergy {
            remaining = 10
            return nil
        }
        if let next = followUp(after: current, ctx) {
            let breather = current.exertion == .hard && next == .sit
            let picked = start(next)
            catchingBreath = breather
            return picked
        }
        let pick = choose(ctx)
        return start(pick == .read && ctx.needs.energy < ctx.lowThreshold ? .readSleep : pick)
    }

    /// What naturally comes next, if anything: a breather after running, a sit after eating,
    /// a yawn before bed and after waking, or more of the same hobby.
    func followUp(after b: Behavior, _ ctx: BrainContext) -> Behavior? {
        let n = ctx.needs
        if b.exertion == .hard { return .sit }
        if b == .eat { return .sit }
        if b == .yawn { return n.energy < 40 ? .sleep : nil }
        if b == .sleep { return .yawn }
        if n.energy < config.bedtimeEnergy && !b.countsAsSleep { return .yawn }
        if Behavior.hobbies.contains(b), ctx.secondsSinceInteraction >= config.aloneAfter,
           n.hunger >= ctx.lowThreshold, n.thirst >= ctx.lowThreshold, random() < config.hobbyStickiness {
            return b
        }
        return nil
    }

    private func start(_ next: Behavior) -> Behavior {
        current = next
        catchingBreath = false
        readElapsed = 0
        readRolled = false
        let range = config.durations[next] ?? 3...8
        remaining = range.lowerBound + random() * (range.upperBound - range.lowerBound)
        return next
    }

    public func interrupt(with behavior: Behavior, duration: TimeInterval) {
        current = behavior
        catchingBreath = false
        remaining = duration
        readElapsed = 0
        readRolled = false
    }

    public func finishCurrent() {
        remaining = 0
        if current.countsAsSleep { current = .idle }
    }
}

public enum Exertion: Comparable {
    case rest, light, hard
}
