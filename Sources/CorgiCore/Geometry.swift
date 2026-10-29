#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

public struct WindowInfo: Equatable {
    public let id: Int
    public let frame: CGRect

    public init(id: Int, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

public struct FloorSegment: Equatable {
    public enum Kind: Equatable {
        case ground(screen: Int)
        case window(id: Int)
    }

    public var kind: Kind
    public var y: CGFloat
    public var minX: CGFloat
    public var maxX: CGFloat

    public init(kind: Kind, y: CGFloat, minX: CGFloat, maxX: CGFloat) {
        self.kind = kind
        self.y = y
        self.minX = minX
        self.maxX = maxX
    }

    public var width: CGFloat { maxX - minX }

    public var windowID: Int? {
        if case .window(let id) = kind { return id }
        return nil
    }

    public func contains(x: CGFloat) -> Bool { x >= minX && x <= maxX }

    public func clampX(_ x: CGFloat) -> CGFloat { min(max(x, minX), maxX) }
}

/// CGWindowList bounds use a top-left origin on the primary screen; AppKit uses bottom-left.
public func appKitRect(fromCGBounds b: CGRect, primaryScreenHeight h: CGFloat) -> CGRect {
    CGRect(x: b.minX, y: h - b.maxY, width: b.width, height: b.height)
}

public func subtractIntervals(_ base: ClosedRange<CGFloat>,
                              _ cuts: [ClosedRange<CGFloat>]) -> [ClosedRange<CGFloat>] {
    var pieces = [base]
    for cut in cuts {
        pieces = pieces.flatMap { piece -> [ClosedRange<CGFloat>] in
            guard cut.overlaps(piece) else { return [piece] }
            var out: [ClosedRange<CGFloat>] = []
            if cut.lowerBound > piece.lowerBound { out.append(piece.lowerBound...cut.lowerBound) }
            if cut.upperBound < piece.upperBound { out.append(cut.upperBound...piece.upperBound) }
            return out
        }
    }
    return pieces
}

/// Screens shrunk by a side margin and a top headroom, so a free-moving corgi or ball stays fully visible.
public func insetRects(_ screens: [CGRect], side: CGFloat, top: CGFloat) -> [CGRect] {
    screens.map { CGRect(x: $0.minX + side, y: $0.minY,
                         width: max(0, $0.width - 2 * side), height: max(0, $0.height - top)) }
}

public func rects(_ rects: [CGRect], contain p: CGPoint) -> Bool {
    rects.contains { $0.minX <= p.x && p.x <= $0.maxX && $0.minY <= p.y && p.y <= $0.maxY }
}

/// Closest point to `p` inside any of `rects`. Returns `p` when `rects` is empty.
public func nearestPoint(to p: CGPoint, in rects: [CGRect]) -> CGPoint {
    rects.map { CGPoint(x: min(max(p.x, $0.minX), $0.maxX), y: min(max(p.y, $0.minY), $0.maxY)) }
        .min { hypot($0.x - p.x, $0.y - p.y) < hypot($1.x - p.x, $1.y - p.y) } ?? p
}

/// Legal positions for an origin whose local `bounds` must fit inside one screen.
/// A screen smaller than the sprite keeps it centered on that axis.
public func placementRects(_ screens: [CGRect], bounds: CGRect) -> [CGRect] {
    screens.map { screen in
        let width = max(0, screen.width - bounds.width)
        let height = max(0, screen.height - bounds.height)
        return CGRect(x: screen.width >= bounds.width ? screen.minX - bounds.minX : screen.midX - bounds.midX,
                      y: screen.height >= bounds.height ? screen.minY - bounds.minY : screen.midY - bounds.midY,
                      width: width, height: height)
    }
}

/// Where two displays touch side by side: `left` ends and `right` begins at `x`, sharing heights `minY...maxY`.
public struct ScreenSeam: Equatable {
    public var left: Int
    public var right: Int
    public var x: CGFloat
    public var minY: CGFloat
    public var maxY: CGFloat

    public init(left: Int, right: Int, x: CGFloat, minY: CGFloat, maxY: CGFloat) {
        self.left = left
        self.right = right
        self.x = x
        self.minY = minY
        self.maxY = maxY
    }
}

/// Side-by-side display edges (within `tolerance` points) that share some height.
public func screenSeams(_ screens: [CGRect], tolerance: CGFloat = 2) -> [ScreenSeam] {
    var seams: [ScreenSeam] = []
    for i in screens.indices {
        for j in screens.indices where i != j && abs(screens[i].maxX - screens[j].minX) <= tolerance {
            let lo = max(screens[i].minY, screens[j].minY), hi = min(screens[i].maxY, screens[j].maxY)
            guard hi > lo else { continue }
            seams.append(ScreenSeam(left: i, right: j, x: (screens[i].maxX + screens[j].minX) / 2, minY: lo, maxY: hi))
        }
    }
    return seams
}

/// What the pet does where its floor ends at a display edge and the next display's floor continues.
public enum SeamCrossing: Equatable {
    /// The next floor is lower: step off and drop.
    case drop
    /// The next floor is higher, within jumping range: hop up onto it.
    case jump(to: CGPoint)
}

/// A display sitting directly on top of another: `upper`'s bottom edge meets `lower`'s top edge over `minX...maxX`.
public struct StackedDisplays: Equatable {
    public var lower: Int
    public var upper: Int
    public var minX: CGFloat
    public var maxX: CGFloat

    public init(lower: Int, upper: Int, minX: CGFloat, maxX: CGFloat) {
        self.lower = lower
        self.upper = upper
        self.minX = minX
        self.maxX = maxX
    }
}

/// Displays stacked on top of each other (full frames, within `tolerance`), overlapping at least `minWidth`.
public func stackedDisplays(_ frames: [CGRect], tolerance: CGFloat = 2, minWidth: CGFloat = 160) -> [StackedDisplays] {
    var out: [StackedDisplays] = []
    for i in frames.indices {
        for j in frames.indices where i != j && abs(frames[i].maxY - frames[j].minY) <= tolerance {
            let lo = max(frames[i].minX, frames[j].minX), hi = min(frames[i].maxX, frames[j].maxX)
            if hi - lo >= minWidth { out.append(StackedDisplays(lower: i, upper: j, minX: lo, maxX: hi)) }
        }
    }
    return out
}

