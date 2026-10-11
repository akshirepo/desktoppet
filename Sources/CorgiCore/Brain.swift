import Foundation

public enum Behavior: String, CaseIterable {
    case idle, walk, sit, sleep, zoomies, chaseCursor, hopToWindow, beg
    case eat, fetch, bath, dangle, fall, greet

    /// Behaviors the brain picks on its own. The rest only happen through `interrupt`.
    public static let autonomous: [Behavior] = [.idle, .walk, .sit, .sleep, .zoomies, .chaseCursor, .hopToWindow, .beg]
}

public struct BrainConfig {
    public var durations: [Behavior: ClosedRange<Double>] = [
        .idle: 3...8, .walk: 3...8, .sit: 4...10, .sleep: 60...180,
        .zoomies: 4...8, .chaseCursor: 5...5, .hopToWindow: 6...8, .beg: 6...10,
    ]
    public var wakeEnergy = 95.0

    public init() {}
}

public struct BrainContext {
    public var needs: NeedsState
    public var lowThreshold: Double
    public var canHop: Bool

    public init(needs: NeedsState, lowThreshold: Double, canHop: Bool) {
        self.needs = needs
        self.lowThreshold = lowThreshold
        self.canHop = canHop
    }
}

public final class Brain {
    public let config: BrainConfig
    private var rng: any RandomNumberGenerator
    public private(set) var current: Behavior = .idle
    public private(set) var remaining: TimeInterval = 0

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
        ]
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
        if n.hunger < ctx.lowThreshold {
            w[.beg]! += 6
        }
        if n.energy < ctx.lowThreshold {
            w[.sleep]! += 10
            w[.zoomies] = 0
            w[.chaseCursor] = 0
            w[.hopToWindow] = 0
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
        guard remaining <= 0 else { return nil }
        if current == .sleep && ctx.needs.energy < config.wakeEnergy {
            remaining = 10
            return nil
        }
        let next = choose(ctx)
        current = next
        let range = config.durations[next] ?? 3...8
        remaining = range.lowerBound + random() * (range.upperBound - range.lowerBound)
        return next
    }

    public func interrupt(with behavior: Behavior, duration: TimeInterval) {
        current = behavior
        remaining = duration
    }

    public func finishCurrent() {
        remaining = 0
        if current == .sleep { current = .idle }
    }
}
