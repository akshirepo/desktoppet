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
