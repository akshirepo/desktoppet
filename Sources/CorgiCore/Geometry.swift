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
