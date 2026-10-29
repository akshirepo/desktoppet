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
    /// Highest step up to the next display's floor that the pet will hop; higher than this it turns back.
    public var maxSeamStepUp: CGFloat = 420

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
    /// Where displays touch side by side, so the pet can walk from one to the next.
    public private(set) var seams: [ScreenSeam] = []
    /// Displays stacked on top of each other, so the pet can leap up or hop down between them.
    public private(set) var stacks: [StackedDisplays] = []
    /// Full display frames (menu bar and Dock included), used to see which displays sit on top of which.
    public private(set) var fullFrames: [CGRect] = []

    public init(provider: WindowListProvider, screens: [CGRect], config: WorldConfig = .init(), bodyBounds: CGRect = .zero) {
        self.provider = provider
        self.screens = screens
        self.fullFrames = screens
        self.config = config
        self.bodyBounds = bodyBounds
        rebuildSegments()
    }

    /// Legal feet positions; `screens` itself remains the unmodified visible area.
    /// Where displays touch, a corridor lets the pet straddle the seam on its way across.
    public var movementScreens: [CGRect] { placementRects(screens, bounds: bodyBounds) + seamCorridors(bodyBounds) }

    public func roamingScreens(headroom: CGFloat) -> [CGRect] {
        let clearance = CGRect(x: -20, y: 0, width: 40, height: max(0, headroom))
        let bounds = bodyBounds.union(clearance)
        return placementRects(screens, bounds: bounds) + seamCorridors(bounds)
    }

    /// Feet positions where a sprite with `bounds` straddles a seam and stays on the two displays:
    /// side-by-side seams, and the edge between a display and the one stacked on top of it.
    private func seamCorridors(_ bounds: CGRect) -> [CGRect] {
        let side: [CGRect] = seams.compactMap { seam in
            let minY = seam.minY - bounds.minY, maxY = seam.maxY - bounds.maxY
            guard maxY >= minY else { return nil }
            return CGRect(x: seam.x - bounds.maxX, y: minY, width: max(0, bounds.width), height: maxY - minY)
        }
        return side + stackCorridors(bounds)
    }

    /// Feet positions linking a display's area to the area of the display stacked on top of it.
    private func stackCorridors(_ bounds: CGRect) -> [CGRect] {
        stacks.compactMap { corridor(for: $0, bounds: bounds) }
    }

    private func corridor(for link: StackedDisplays, bounds: CGRect) -> CGRect? {
        guard screens.indices.contains(link.lower), screens.indices.contains(link.upper) else { return nil }
        let rects = placementRects([screens[link.lower], screens[link.upper]], bounds: bounds)
        let minX = link.minX - bounds.minX, maxX = link.maxX - bounds.maxX
        let minY = min(rects[0].maxY, rects[1].minY), maxY = max(rects[0].maxY, rects[1].minY)
        guard maxX >= minX else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Where a roaming pet should head next to reach `target`: straight there on the same display, or via the
    /// corridor to a display stacked above or below.
    public func roamWaypoint(from p: CGPoint, to target: CGPoint, headroom: CGFloat) -> CGPoint {
        guard let here = display(at: p), let there = display(at: target), here != there,
              let link = stacks.first(where: { ($0.lower == here && $0.upper == there) || ($0.upper == here && $0.lower == there) })
        else { return target }
        let clearance = CGRect(x: -20, y: 0, width: 40, height: max(0, headroom))
        let bounds = bodyBounds.union(clearance)
        guard let corridor = corridor(for: link, bounds: bounds) else { return target }
        let x = min(max(p.x, corridor.minX + 10), corridor.maxX - 10)
        if abs(x - p.x) > 2 { return CGPoint(x: x, y: p.y) }            // line up under/over the other display first
        let goingDown = link.upper == here
        return CGPoint(x: x, y: goingDown ? corridor.minY - 20 : corridor.maxY + 20)
    }

    public func setScreens(_ screens: [CGRect], fullFrames: [CGRect]? = nil) {
        self.screens = screens
        self.fullFrames = fullFrames ?? screens
        rebuildSegments()
    }

    /// True when some floor lies under `p` (at or below it) for a falling pet to land on.
    public func hasFloor(below p: CGPoint) -> Bool {
        segments.contains { $0.contains(x: p.x) && $0.y <= p.y + 2 }
    }

    /// The display containing `p`, preferring the one whose floor it's standing on.
    public func display(at p: CGPoint) -> Int? {
        let lifted = CGPoint(x: p.x, y: p.y + 1)
        if let i = screens.firstIndex(where: { $0.contains(lifted) }) { return i }
        return screens.indices.min { hypot(nearestPoint(to: p, in: [screens[$0]]).x - p.x, nearestPoint(to: p, in: [screens[$0]]).y - p.y)
            < hypot(nearestPoint(to: p, in: [screens[$1]]).x - p.x, nearestPoint(to: p, in: [screens[$1]]).y - p.y) }
    }

    /// The floor along the bottom of display `i`.
    public func ground(of i: Int) -> FloorSegment? {
        guard screens.indices.contains(i) else { return nil }
        let area = placementRects([screens[i]], bounds: bodyBounds)[0]
        return segments.first {
            guard case .ground = $0.kind else { return false }
            return abs($0.y - area.minY) <= 1 && $0.maxX > area.minX && $0.minX < area.maxX
        }
    }

    /// How to get from `segment` onto the next display's floor when walking off its end in `direction`,
    /// or nil when there's no display there or its floor is out of reach.
    public func crossing(from segment: FloorSegment, direction: CGFloat, maxJumpUp: CGFloat) -> SeamCrossing? {
        guard case .ground = segment.kind, direction != 0 else { return nil }
        let edge = direction > 0 ? segment.maxX : segment.minX
        guard seams.contains(where: { abs($0.x - edge) <= 2 }) else { return nil }
        let next = segments.filter {
            guard case .ground = $0.kind, $0 != segment else { return false }
            return abs((direction > 0 ? $0.minX : $0.maxX) - edge) <= 2
        }.min { abs($0.y - segment.y) < abs($1.y - segment.y) }
        guard let n = next else { return nil }
        if n.y < segment.y - 1 { return .drop }
        guard n.y - segment.y <= maxJumpUp else { return nil }
        let x = direction > 0 ? min(n.maxX, n.minX + 40) : max(n.minX, n.maxX - 40)
        return .jump(to: CGPoint(x: x, y: n.y))
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
        // Measured on full display frames: a Dock or menu bar shouldn't hide where two displays meet.
        let frames = fullFrames.count == screens.count ? fullFrames : screens
        seams = screenSeams(frames)
        stacks = stackedDisplays(frames)
        let areas = placementRects(screens, bounds: bodyBounds)
        let headroom = max(config.headroom, bodyBounds.maxY)
        var result = groundSegments(areas)
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

    /// One floor per display, running right up to any seam. Floors that meet at the same height become one,
    /// so the pet walks straight across; floors at different heights stay separate and are crossed by a hop.
    private func groundSegments(_ areas: [CGRect]) -> [FloorSegment] {
        var floors = areas.enumerated().map { i, a in
            FloorSegment(kind: .ground(screen: i), y: a.minY, minX: a.minX, maxX: a.maxX)
        }
        // A floor runs up to the seam only when the other side is reachable (lower, or a small step up).
        let base = floors
        for seam in seams {
            let l = base[seam.left], r = base[seam.right]
            if r.y <= l.y + config.maxSeamStepUp { floors[seam.left].maxX = seam.x }
            if l.y <= r.y + config.maxSeamStepUp { floors[seam.right].minX = seam.x }
        }
        var merged = true
        while merged {
            merged = false
            outer: for i in floors.indices {
                for j in floors.indices where i != j
                    && abs(floors[i].maxX - floors[j].minX) <= 2 && abs(floors[i].y - floors[j].y) <= 1 {
                    floors[i].maxX = floors[j].maxX
                    floors.remove(at: j)
                    merged = true
                    break outer
                }
            }
        }
        return floors
    }
}
