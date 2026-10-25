#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// A ball that drifts around the visible screen area on a smooth random path and pops after `lifetime`.
public final class Ball {
    public var speed: CGFloat = 180
    public var lifetime: TimeInterval = 30
    public var waypointEvery: ClosedRange<Double> = 1...2
    public private(set) var position: CGPoint
    public private(set) var waypoint: CGPoint
    public private(set) var age: TimeInterval = 0
    public private(set) var area: [CGRect]
    private var velocity: CGVector = .zero
    private var untilNewWaypoint: TimeInterval = 0
    private var rng: any RandomNumberGenerator

    public init(start: CGPoint, screens: [CGRect], rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.rng = rng
        area = Ball.area(for: screens)
        position = nearestPoint(to: start, in: area)
        waypoint = position
    }

    /// Visible frames minus side and top margins, lifted 30pt off the floor.
    public static func area(for screens: [CGRect], reachableFrom feetAreas: [CGRect]? = nil) -> [CGRect] {
        let areas = insetRects(screens, side: 20, top: 40).map {
            CGRect(x: $0.minX, y: $0.minY + 30, width: $0.width, height: max(0, $0.height - 30))
        }
        guard let feetAreas else { return areas }
        // Ball chase targets the mouth, 30pt above the feet. Preserve the ball's existing margins.
        return zip(areas, feetAreas).map { $0.intersection($1.offsetBy(dx: 0, dy: 30)) }
            .filter { !$0.isNull }
    }

    public var popped: Bool { age >= lifetime }

    private func random() -> CGFloat {
        CGFloat(Double(rng.next() >> 11) / Double(1 << 53))
    }

    private func pickWaypoint() {
        guard !area.isEmpty else { return }
        let r = area[Int(random() * CGFloat(area.count)) % area.count]
        waypoint = CGPoint(x: r.minX + random() * r.width, y: r.minY + random() * r.height)
        let lo = waypointEvery.lowerBound, hi = waypointEvery.upperBound
        untilNewWaypoint = lo + Double(random()) * (hi - lo)
    }

    /// Monitors changed: pull the ball and its waypoint back inside what is left.
    public func setScreens(_ screens: [CGRect]) {
        setArea(Ball.area(for: screens))
    }

    public func setArea(_ area: [CGRect]) {
        self.area = area
        position = nearestPoint(to: position, in: area)
        if !rects(area, contain: waypoint) { pickWaypoint() }
    }

    public func step(dt: TimeInterval) {
        age += dt
        untilNewWaypoint -= dt
        if untilNewWaypoint <= 0 { pickWaypoint() }
        let dx = waypoint.x - position.x, dy = waypoint.y - position.y
        let dist = max(hypot(dx, dy), 0.001)
        let desired = CGVector(dx: dx / dist * speed, dy: dy / dist * speed)
        let k = min(1, CGFloat(dt) * 3)
        velocity = CGVector(dx: velocity.dx + (desired.dx - velocity.dx) * k,
                            dy: velocity.dy + (desired.dy - velocity.dy) * k)
        let next = CGPoint(x: position.x + velocity.dx * CGFloat(dt), y: position.y + velocity.dy * CGFloat(dt))
        position = nearestPoint(to: next, in: area)
    }
}
