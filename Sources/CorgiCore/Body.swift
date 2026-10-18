#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

public struct BodyConfig {
    public var gravity: CGFloat = 2200
    public var walkSpeed: CGFloat = 70
    public var runSpeed: CGFloat = 240
    public var maxJumpUp: CGFloat = 420
    public var maxJumpAcross: CGFloat = 520
    public var jumpClearance: CGFloat = 50
    public var maxFallSpeed: CGFloat = 1800
    /// Room kept free above a roaming corgi's feet so it never slides under the menu bar.
    public var roamHeadroom: CGFloat = 80

    public init() {}
}

public enum BodyMode: Equatable { case grounded, airborne, held, roaming, clinging }

public enum BodyEvent: Equatable { case landed, hitEdge, startedFalling }

public final class Body {
    public let config: BodyConfig
    public private(set) var position: CGPoint
    public private(set) var velocity: CGVector = .zero
    public private(set) var mode: BodyMode = .airborne
    public private(set) var standingOn: FloorSegment?
    public private(set) var facingRight = true
    /// Set while `mode == .clinging`.
    public private(set) var cling: ClingSpot?
    private var walkVelocity: CGFloat = 0

    public init(position: CGPoint, config: BodyConfig = .init()) {
        self.position = position
        self.config = config
    }

    public var isMoving: Bool {
        mode == .airborne || walkVelocity != 0 || (mode == .roaming && velocity != .zero)
    }

    /// True when walking faster than a stroll, so the animation should be `run`.
    public var isRunning: Bool { abs(walkVelocity) > config.walkSpeed * 1.6 }

    public func walk(direction: CGFloat, speed: CGFloat) {
        guard mode == .grounded else { return }
        walkVelocity = direction.sign == .minus ? -speed : (direction == 0 ? 0 : speed)
        if direction != 0 { facingRight = direction > 0 }
    }

    public func stop() { walkVelocity = 0 }

    public func face(right: Bool) { facingRight = right }

    public func jump(to target: CGPoint) {
        guard mode == .grounded else { return }
        let g = config.gravity
        let apex = max(target.y, position.y) - position.y + config.jumpClearance
        let vy = (2 * g * apex).squareRoot()
        let tUp = vy / g
        let tDown = (2 * (position.y + apex - target.y) / g).squareRoot()
        velocity = CGVector(dx: (target.x - position.x) / (tUp + tDown), dy: vy)
        facingRight = target.x >= position.x
        walkVelocity = 0
        standingOn = nil
        mode = .airborne
    }

    /// Small hop off the end of the current segment, used to get down from a perch.
    public func leap(direction: CGFloat) {
        guard mode == .grounded, let s = standingOn else { return }
        position.x = direction < 0 ? s.minX - 1 : s.maxX + 1
        velocity = CGVector(dx: direction < 0 ? -150 : 150, dy: 250)
        facingRight = direction > 0
        walkVelocity = 0
        standingOn = nil
        mode = .airborne
    }

    /// Free flight with no gravity or floors (Chase Me and ball chase).
    public func startRoaming() {
        guard mode != .held else { return }
        mode = .roaming
        standingOn = nil
        velocity = .zero
        walkVelocity = 0
    }

    /// Sets the roaming velocity toward `target`. Stops when within 1pt of it.
    public func roam(toward target: CGPoint, speed: CGFloat) {
        guard mode == .roaming else { return }
        let dx = target.x - position.x, dy = target.y - position.y
        let dist = hypot(dx, dy)
        guard dist > 1 else {
            velocity = .zero
            return
        }
        velocity = CGVector(dx: dx / dist * speed, dy: dy / dist * speed)
        if abs(dx) > 1 { facingRight = dx > 0 }
    }

    /// Holds still in the air while roaming.
    public func hover() {
        guard mode == .roaming else { return }
        velocity = .zero
    }

    /// Ends roaming. The body falls to whatever floor is below.
    public func stopRoaming() {
        guard mode == .roaming else { return }
        startFalling()
    }

    /// Hold on to a window edge at `contact`. No gravity until `letGo()` or the window goes away.
    public func startClinging(_ spot: ClingSpot, at contact: CGPoint) {
        mode = .clinging
        cling = spot
        position = contact
        velocity = .zero
        walkVelocity = 0
        standingOn = nil
        if spot.edge == .left { facingRight = true }
        if spot.edge == .right { facingRight = false }
    }

    /// Keep holding the same spot as the window moves; falls off if the window is gone.
    @discardableResult
    public func followCling(_ world: World) -> BodyEvent? {
        guard mode == .clinging, let spot = cling else { return nil }
        if let p = ClingFinder.contact(spot, windows: world.windows) {
            position = p
            return nil
        }
        cling = nil
        return startFalling()
    }

    @discardableResult
    public func letGo() -> BodyEvent? {
        guard mode == .clinging else { return nil }
        cling = nil
        return startFalling()
    }

    public func pickUp() {
        mode = .held
        cling = nil
        standingOn = nil
        velocity = .zero
        walkVelocity = 0
    }

    public func moveHeld(to point: CGPoint) {
        guard mode == .held else { return }
        position = point
    }

    public func release() {
        guard mode == .held else { return }
        mode = .airborne
        velocity = .zero
    }

    @discardableResult
    public func apply(_ update: WorldUpdate) -> BodyEvent? {
        guard mode == .grounded, let id = standingOn?.windowID else { return nil }
        if update.vanished.contains(id) {
            return startFalling()
        }
        if let delta = update.moved[id] {
            position.x += delta.dx
            position.y += delta.dy
        }
        return nil
    }

    @discardableResult
    public func step(dt: TimeInterval, world: World) -> BodyEvent? {
        let dt = CGFloat(dt)
        switch mode {
        case .clinging:
            return nil
        case .held:
            return nil
        case .grounded:
            guard let segment = world.segment(under: position) else { return startFalling() }
            standingOn = segment
            position.y = segment.y
            let nextX = position.x + walkVelocity * dt
            if segment.contains(x: nextX) {
                position.x = nextX
                return nil
            }
            position.x = segment.clampX(nextX)
            walkVelocity = 0
            return .hitEdge
        case .roaming:
            let area = insetRects(world.screens, side: 20, top: config.roamHeadroom)
            let next = CGPoint(x: position.x + velocity.dx * dt, y: position.y + velocity.dy * dt)
            if area.isEmpty || rects(area, contain: next) {
                position = next
                return nil
            }
            position = nearestPoint(to: next, in: area)
            velocity = .zero
            return .hitEdge
        case .airborne:
            velocity.dy = max(velocity.dy - config.gravity * dt, -config.maxFallSpeed)
            let next = CGPoint(x: position.x + velocity.dx * dt, y: position.y + velocity.dy * dt)
            if velocity.dy <= 0,
               let landing = world.segments
                .filter({ $0.contains(x: next.x) && position.y >= $0.y && next.y <= $0.y })
                .max(by: { $0.y < $1.y }) {
                position = CGPoint(x: next.x, y: landing.y)
                velocity = .zero
                standingOn = landing
                mode = .grounded
                return .landed
            }
            position = next
            return nil
        }
    }

    /// Pulls the body back onto the nearest screen if it ended up outside every screen.
    public func clamp(to screens: [CGRect]) {
        guard !screens.isEmpty, mode != .clinging else { return }
        let p = position
        if screens.contains(where: { $0.minX <= p.x && p.x <= $0.maxX && $0.minY <= p.y && p.y <= $0.maxY }) {
            return
        }
        let screen = screens.first { $0.minX <= p.x && p.x <= $0.maxX }
            ?? screens.min { abs($0.midX - p.x) < abs($1.midX - p.x) }!
        let clamped = CGPoint(x: min(max(position.x, screen.minX + 20), screen.maxX - 20),
                              y: min(max(position.y, screen.minY), screen.maxY - 10))
        guard clamped != position else { return }
        position = clamped
        if mode == .grounded || mode == .airborne { startFalling() }
    }

    @discardableResult
    private func startFalling() -> BodyEvent {
        mode = .airborne
        standingOn = nil
        velocity = .zero
        walkVelocity = 0
        return .startedFalling
    }
}
