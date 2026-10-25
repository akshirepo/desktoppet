#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

public struct HomeConfig {
    /// Home sits this far left of the main screen's right edge.
    public var insetFromRight: CGFloat = 80
    /// Within this many points of the spot (on the same floor) counts as home.
    public var radius: CGFloat = 40

    public init() {}
}

/// Where home is and how long the corgi has been away from it.
public final class HomeTracker {
    public let config: HomeConfig
    let clock: Clock
    public private(set) var spot: CGPoint?
    private var awaySince: Date?

    public init(clock: Clock, config: HomeConfig = .init()) {
        self.clock = clock
        self.config = config
    }

    /// `visibleFrames` in the same order as `World.screens`; `mainIndex` is the main screen.
    /// Falls back to the first screen when the main one is gone.
    public func setScreens(_ visibleFrames: [CGRect], mainIndex: Int, bodyBounds: CGRect = .zero) {
        guard !visibleFrames.isEmpty else {
            spot = nil
            return
        }
        let vf = visibleFrames.indices.contains(mainIndex) ? visibleFrames[mainIndex] : visibleFrames[0]
        let desired = CGPoint(x: vf.maxX - config.insetFromRight, y: vf.minY)
        spot = nearestPoint(to: desired, in: placementRects([vf], bounds: bodyBounds))
    }

    /// The screen whose right edge is furthest right: the bottom-right corner of the whole desktop.
    public static func cornerScreenIndex(_ visibleFrames: [CGRect]) -> Int? {
        visibleFrames.indices.max { visibleFrames[$0].maxX < visibleFrames[$1].maxX }
    }

    public func isHome(_ p: CGPoint) -> Bool {
        guard let h = spot else { return false }
        return abs(p.x - h.x) <= config.radius && abs(p.y - h.y) <= 2
    }

    /// Call every tick with the corgi's feet.
    public func observe(_ p: CGPoint) {
        if isHome(p) {
            awaySince = nil
        } else if awaySince == nil {
            awaySince = clock.now
        }
    }

    public var secondsAway: TimeInterval {
        guard let since = awaySince else { return 0 }
        return max(0, clock.now.timeIntervalSince(since))
    }
}

public enum Greeting {
    public static let missedYouAfter: TimeInterval = 3600

    /// Speech bubbles shown at launch, in order.
    public static func lines(awaySeconds: TimeInterval) -> [String] {
        awaySeconds > missedYouAfter ? ["Hi!", "Missed you!"] : ["Hi!"]
    }
}
