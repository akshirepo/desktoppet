#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

public protocol WindowListProvider: AnyObject {
    /// Visible normal windows, front to back, in AppKit global coordinates.
    func visibleWindows() -> [WindowInfo]
}

public struct WorldConfig {
    public var minSegmentWidth: CGFloat = 80
    /// Space the corgi needs above an edge. Edges closer than this to the screen top,
    /// or with another window this close above them, are not perches.
    public var headroom: CGFloat = 90

    public init() {}
}

public struct WorldUpdate: Equatable {
    public var moved: [Int: CGVector] = [:]
    public var vanished: Set<Int> = []

    public init(moved: [Int: CGVector] = [:], vanished: Set<Int> = []) {
        self.moved = moved
        self.vanished = vanished
    }

    public var isEmpty: Bool { moved.isEmpty && vanished.isEmpty }
}

public final class World {
    let provider: WindowListProvider
    public let config: WorldConfig
    /// Stable canvas envelope relative to the feet, including either facing direction.
    public let bodyBounds: CGRect
    public private(set) var screens: [CGRect]
    public private(set) var windows: [WindowInfo] = []
    public private(set) var segments: [FloorSegment] = []

    public init(provider: WindowListProvider, screens: [CGRect], config: WorldConfig = .init(), bodyBounds: CGRect = .zero) {
        self.provider = provider
        self.screens = screens
        self.config = config
        self.bodyBounds = bodyBounds
        rebuildSegments()
    }

    /// Legal feet positions; `screens` itself remains the unmodified visible area.
    public var movementScreens: [CGRect] { placementRects(screens, bounds: bodyBounds) }

    public func roamingScreens(headroom: CGFloat) -> [CGRect] {
        let clearance = CGRect(x: -20, y: 0, width: 40, height: max(0, headroom))
        return placementRects(screens, bounds: bodyBounds.union(clearance))
    }

    public func setScreens(_ screens: [CGRect]) {
        self.screens = screens
        rebuildSegments()
    }

    @discardableResult
    public func refresh() -> WorldUpdate {
        let old = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.frame) })
        windows = provider.visibleWindows()
        var update = WorldUpdate()
        var seen = Set<Int>()
        for window in windows {
            seen.insert(window.id)
            guard let before = old[window.id] else { continue }
            let delta = CGVector(dx: window.frame.minX - before.minX, dy: window.frame.maxY - before.maxY)
            if delta.dx != 0 || delta.dy != 0 { update.moved[window.id] = delta }
        }
        update.vanished = Set(old.keys).subtracting(seen)
        rebuildSegments()
        return update
    }

    public func segment(under p: CGPoint, tolerance: CGFloat = 2) -> FloorSegment? {
        segments
            .filter { $0.contains(x: p.x) && abs($0.y - p.y) <= tolerance }
            .max { $0.y < $1.y }
    }

    public func reachableSegments(from p: CGPoint, maxJumpUp: CGFloat, maxJumpAcross: CGFloat) -> [FloorSegment] {
        let current = segment(under: p)
        return segments
            .filter { $0 != current }
            .filter { $0.y - p.y <= maxJumpUp }
            .filter { abs($0.clampX(p.x) - p.x) <= maxJumpAcross }
            .sorted { $0.y > $1.y }
    }

    public func screenIndex(containing p: CGPoint) -> Int? {
        if let i = screens.firstIndex(where: { $0.minX <= p.x && p.x < $0.maxX }) { return i }
        return screens.indices.min { abs(screens[$0].midX - p.x) < abs(screens[$1].midX - p.x) }
    }

    func rebuildSegments() {
        let areas = movementScreens
        let headroom = max(config.headroom, bodyBounds.maxY)
        var result = areas.enumerated().map { i, s in
            FloorSegment(kind: .ground(screen: i), y: s.minY, minX: s.minX, maxX: s.maxX)
        }
        for (k, window) in windows.enumerated() {
            let top = window.frame.maxY
            guard let index = screens.indices.first(where: {
                screens[$0].minX <= window.frame.midX && window.frame.midX <= screens[$0].maxX
                    && top > areas[$0].minY && top <= screens[$0].maxY - headroom
            }) else { continue }
            let screen = areas[index]
            let left = max(window.frame.minX, screen.minX), right = min(window.frame.maxX, screen.maxX)
            guard left <= right else { continue }
            let base = left...right
            let cuts = windows[..<k]
                .filter { $0.frame.minY <= top + headroom && $0.frame.maxY >= top }
                .map { $0.frame.minX...$0.frame.maxX }
            for piece in subtractIntervals(base, cuts)
            where piece.upperBound - piece.lowerBound >= config.minSegmentWidth {
                result.append(FloorSegment(kind: .window(id: window.id), y: top,
                                           minX: piece.lowerBound, maxX: piece.upperBound))
            }
        }
        segments = result
    }
}
