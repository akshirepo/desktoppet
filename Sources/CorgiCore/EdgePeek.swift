#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// Which side of a display the pet hides behind.
public enum EdgeSide: String, Codable, Equatable {
    case left, right
}

/// On the floor it peeks round the edge (`peekEdge`); higher up it hangs on to the edge (`holdEdge`).
public enum EdgePeekKind: String, Codable, Equatable {
    case floor, hold
}

/// A spot just past a display's outer left or right edge where the pet hides and peeks back in.
///
/// Art convention for `peekEdge`, `holdEdge` and their bridges: frames face right, peeking in from the LEFT edge,
/// and canvas column 0 (the canvas's left border) is the screen edge, so nothing can be drawn on the hidden side.
/// The anchor is the same as idle's, so the exit art can end on the exact idle frame. At a right edge the sprite
/// is mirrored, which puts column 0 on the right edge instead.
public struct EdgePeek: Equatable {
    public var screen: Int
    public var side: EdgeSide
    public var kind: EdgePeekKind
    /// x of the display edge (AppKit coordinates).
    public var edgeX: CGFloat
    /// Feet height: the floor for `.floor`, where it was let go for `.hold`.
    public var y: CGFloat
    /// The floor it peeks from (`.floor` only).
    public var floor: FloorSegment?

    public init(screen: Int, side: EdgeSide, kind: EdgePeekKind, edgeX: CGFloat, y: CGFloat, floor: FloorSegment? = nil) {
        self.screen = screen
        self.side = side
        self.kind = kind
        self.edgeX = edgeX
        self.y = y
        self.floor = floor
    }

    public var animState: AnimState { kind == .floor ? .peekEdge : .holdEdge }

    /// Faces into the screen.
    public var facingRight: Bool { side == .left }

    /// Feet x that puts canvas column 0 on the edge. `bounds` is the peek pose's canvas relative to the feet,
    /// facing right and unscaled (`bounds.minX` < 0); `scale` is the draw scale on that display.
    public func feetX(bounds: CGRect, scale: CGFloat = 1) -> CGFloat {
        side == .left ? edgeX - bounds.minX * scale : edgeX + bounds.minX * scale
    }

    public func feet(bounds: CGRect, scale: CGFloat = 1) -> CGPoint {
        CGPoint(x: feetX(bounds: bounds, scale: scale), y: y)
    }

    /// The end of the floor next to the edge, where a floor peek walks to before it hides.
    public var standX: CGFloat? {
        floor.map { side == .left ? $0.minX : $0.maxX }
    }
}

public enum EdgePeekFinder {
    /// Where a pet let go with its feet at `p` should hide, or nil when it isn't near a display's outer edge.
    /// - screens: visible display frames (`World.screens`).
    /// - seams: `World.seams`. Where another display carries on at the sprite's height there's no edge to hide behind.
    /// - floors: `World.segments`. Close above a floor that runs to the edge it peeks from the floor, otherwise it holds on.
    /// - bounds: the peek canvas relative to the feet (facing right, unscaled); `scale` is the display's draw scale.
    /// - reach: how far from the peek spot the feet may be (default one sprite width).
    /// - floorReach: how high above a floor still counts as on it (default three quarters of the sprite height).
    public static func find(feet p: CGPoint, screens: [CGRect], seams: [ScreenSeam], floors: [FloorSegment],
                            bounds: CGRect, scale: CGFloat = 1,
                            reach: CGFloat? = nil, floorReach: CGFloat? = nil) -> EdgePeek? {
        guard bounds.width > 0, bounds.height > 0, bounds.minX < 0, scale > 0 else { return nil }
        let reach = reach ?? bounds.width * scale
        let floorReach = floorReach ?? bounds.height * scale * 0.75
        let landing = floors.filter { $0.contains(x: p.x) && $0.y <= p.y + 2 }.max { $0.y < $1.y }
        var best: (distance: CGFloat, spot: EdgePeek)?
        for (i, s) in screens.enumerated() where p.x >= s.minX && p.x <= s.maxX && p.y >= s.minY - 2 && p.y <= s.maxY {
            for side in [EdgeSide.left, .right] {
                let edge = side == .left ? s.minX : s.maxX
                var spot = EdgePeek(screen: i, side: side, kind: .hold, edgeX: edge, y: p.y)
                let distance = abs(p.x - spot.feetX(bounds: bounds, scale: scale))
                guard distance <= reach else { continue }
                let bottom = p.y + bounds.minY * scale, top = p.y + bounds.maxY * scale
                if seams.contains(where: { abs($0.x - edge) <= 2 && $0.minY < top && $0.maxY > bottom }) { continue }
                if let f = landing, p.y - f.y <= floorReach {
                    let end = side == .left ? f.minX : f.maxX
                    // The floor has to run up to this edge (within half a sprite: the screen's own margin).
                    if abs(end - spot.feetX(bounds: bounds, scale: scale)) <= bounds.width * 0.5 {
                        spot.kind = .floor
                        spot.y = f.y
                        spot.floor = f
                    }
                }
                if spot.kind == .hold {
                    // Hanging on, the whole canvas stays on the display.
                    let lo = s.minY - bounds.minY * scale, hi = s.maxY - bounds.maxY * scale
                    spot.y = hi >= lo ? min(max(p.y, lo), hi) : lo
                }
                if best == nil || distance < best!.distance { best = (distance, spot) }
            }
        }
        return best?.spot
    }
}

/// One hide-and-peek, from being let go near an edge until it's back out.
public struct EdgePeekSession: Equatable {
    public enum Phase: Equatable {
        /// Floor peek: falling to the floor and walking to its end next to the edge.
        case approaching
        /// Behind the edge, peeking in.
        case peeking
        /// Coming back out: the exit art plays, then normal behaviour resumes.
        case leaving
    }

    /// How long it stays behind the edge.
    public static let stay: ClosedRange<TimeInterval> = 120...300
    /// A floor peek that hasn't reached the edge by then gives up.
    public static let approachTimeout: TimeInterval = 12

    public let spot: EdgePeek
    public private(set) var phase: Phase
    /// Seconds of peeking left.
    public private(set) var remaining: TimeInterval
    /// Seconds spent getting to the edge.
    public private(set) var approaching: TimeInterval = 0

    public init(spot: EdgePeek, stay: TimeInterval) {
        self.spot = spot
        remaining = stay
        phase = spot.kind == .floor ? .approaching : .peeking
    }

    /// The floor peek reached the end of the floor and hides now.
    public mutating func arrived() {
        if phase == .approaching { phase = .peeking }
    }

    /// Advances the clock. Returns true when it should give up (couldn't reach the edge in time).
    @discardableResult
    public mutating func update(dt: TimeInterval) -> Bool {
        switch phase {
        case .approaching:
            approaching += dt
            return approaching > Self.approachTimeout
        case .peeking:
            remaining -= dt
            if remaining <= 0 { phase = .leaving }
            return false
        case .leaving:
            return false
        }
    }

    /// Come out early.
    public mutating func leave() {
        phase = .leaving
    }

    /// The pose to show, or nil to animate normally (falling and walking up to the edge).
    public var animState: AnimState? {
        switch phase {
        case .approaching: return nil
        case .peeking: return spot.animState
        case .leaving: return Self.exitPose(spot.kind)
        }
    }

    /// Where the exit art leaves it: standing for the floor peek, the startled let-go pose for the hold (it drops after).
    public static func exitPose(_ kind: EdgePeekKind) -> AnimState {
        kind == .floor ? .idle : .scared
    }

    /// True once the exit art has played (or there's none) and the pet is back on screen.
    public func isOut(currentState: AnimState?, transitionTarget: AnimState?) -> Bool {
        phase == .leaving && transitionTarget == nil && currentState == Self.exitPose(spot.kind)
    }
}
