#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

public enum ClingEdge: String, Codable, Equatable {
    case top, bottom, left, right
}

/// Where the pet is holding on to a window. `along` is 0...1 along the edge
/// (left to right for top/bottom, bottom to top for the sides), so it rides along when the window moves or resizes.
public struct ClingSpot: Equatable {
    public var windowID: Int
    public var edge: ClingEdge
    public var along: CGFloat
    /// Top edge only: sitting on the edge (true) or hanging below it (false).
    public var above: Bool

    public init(windowID: Int, edge: ClingEdge, along: CGFloat, above: Bool) {
        self.windowID = windowID
        self.edge = edge
        self.along = along
        self.above = above
    }

    public var animState: AnimState {
        switch edge {
        case .top: return above ? .clingSit : .clingHang
        case .bottom: return .clingHang
        case .left: return .clingLeft
        case .right: return .clingRight
        }
    }
}

public enum ClingFinder {
    /// Edges shorter than this aren't worth holding on to.
    public static let minEdgeLength: CGFloat = 80

    /// The nearest visible window edge within `reach` of `p` (AppKit coords). `windows` is front to back,
    /// so a front window both wins ties and hides the parts of edges behind it.
    public static func find(_ p: CGPoint, windows: [WindowInfo], reach: CGFloat = 40) -> ClingSpot? {
        var best: (distance: CGFloat, spot: ClingSpot)?
        for (k, w) in windows.enumerated() {
            let f = w.frame
            guard f.width >= minEdgeLength, f.height >= minEdgeLength else { continue }
            var candidates: [(CGFloat, ClingSpot, CGPoint)] = []
            if p.y >= f.minY && p.y <= f.maxY {
                let along = (p.y - f.minY) / f.height
                candidates.append((abs(p.x - f.minX), ClingSpot(windowID: w.id, edge: .left, along: along, above: false),
                                   CGPoint(x: f.minX, y: p.y)))
                candidates.append((abs(p.x - f.maxX), ClingSpot(windowID: w.id, edge: .right, along: along, above: false),
                                   CGPoint(x: f.maxX, y: p.y)))
            }
            if p.x >= f.minX && p.x <= f.maxX {
                let along = (p.x - f.minX) / f.width
                candidates.append((abs(p.y - f.maxY), ClingSpot(windowID: w.id, edge: .top, along: along, above: p.y >= f.maxY),
                                   CGPoint(x: p.x, y: f.maxY)))
                candidates.append((abs(p.y - f.minY), ClingSpot(windowID: w.id, edge: .bottom, along: along, above: false),
                                   CGPoint(x: p.x, y: f.minY)))
            }
            for (d, spot, contact) in candidates where d <= reach {
                let hidden = windows[..<k].contains { $0.frame.insetBy(dx: 1, dy: 1).contains(contact) }
                if hidden { continue }
                if best == nil || d < best!.distance { best = (d, spot) }
            }
            // A window in front covers anything behind it at this point, so stop once we're inside one.
            if f.contains(p) && best != nil { break }
        }
        return best?.spot
    }

    /// The point on the edge the pet holds, or nil if the window is gone.
    public static func contact(_ s: ClingSpot, windows: [WindowInfo]) -> CGPoint? {
        guard let f = windows.first(where: { $0.id == s.windowID })?.frame else { return nil }
        switch s.edge {
        case .left: return CGPoint(x: f.minX, y: f.minY + s.along * f.height)
        case .right: return CGPoint(x: f.maxX, y: f.minY + s.along * f.height)
        case .top: return CGPoint(x: f.minX + s.along * f.width, y: f.maxY)
        case .bottom: return CGPoint(x: f.minX + s.along * f.width, y: f.minY)
        }
    }
}
