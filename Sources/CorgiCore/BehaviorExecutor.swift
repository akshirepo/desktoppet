#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

public final class BehaviorExecutor {
    public var targetX: CGFloat?
    public var speedScale: CGFloat = 1
    /// Home spot for `goHome`. Set by the caller whenever screens change.
    public var home: CGPoint?
    /// Live ball position for `ballChase`. Set by the caller every tick; nil once the ball is gone.
    public var ballPosition: CGPoint?
    /// Called once when the corgi reaches the ball.
    public var onBallCaught: (() -> Void)?
    public private(set) var carryingBall = false
    /// How close `chaseMe` gets to the cursor before it waits. Must exceed the sprite's reach from its feet
    /// (about 113pt at the default scale) so a waiting corgi never sits under the cursor and takes its clicks.
    public var followDistance: CGFloat = 120
    public var catchRadius: CGFloat = 30
    private enum BallPhase { case chasing, carrying, dropping }
    private var ballPhase: BallPhase = .chasing
    private var rng: any RandomNumberGenerator
    private var zoomDirection: CGFloat = 1
    private var hopStarted = false
    private var hopDownDirection: CGFloat?
    private var homePlanned = false
    private var homeLeapDirection: CGFloat?

    public init(rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.rng = rng
    }

    private func random() -> CGFloat {
        CGFloat(Double(rng.next() >> 11) / Double(1 << 53))
    }

    public func begin(_ b: Behavior, body: Body, world: World, cursor: CGPoint) {
        targetX = nil
        hopStarted = false
        hopDownDirection = nil
        homePlanned = false
        homeLeapDirection = nil
        carryingBall = false
        ballPhase = .chasing
        if body.mode == .roaming && b != .chaseMe && b != .ballChase && b != .askCare { body.stopRoaming() }
        body.stop()
        let segment = body.standingOn ?? world.segment(under: body.position)
        switch b {
        case .walk:
            if let s = segment {
                let lo = s.minX + 20, hi = max(lo, s.maxX - 20)
                targetX = lo + random() * (hi - lo)
            }
        case .greet:
            body.face(right: cursor.x >= body.position.x)
        case .zoomies:
            zoomDirection = random() < 0.5 ? -1 : 1
        case .chaseMe, .ballChase, .askCare:
            body.startRoaming()
        case .hopToWindow:
            let options = world.reachableSegments(from: body.position,
                                                  maxJumpUp: body.config.maxJumpUp,
                                                  maxJumpAcross: body.config.maxJumpAcross)
                .prefix(3)
            guard !options.isEmpty else { return }
            let pick = options[options.startIndex + Int(random() * CGFloat(options.count)) % options.count]
            if let s = segment, pick.y < s.y {
                // Going down: walk to the edge on the side where the lower segment continues, then leap.
                let sides: [(dir: CGFloat, edge: CGFloat, landX: CGFloat)] = [(-1, s.minX, s.minX - 40), (1, s.maxX, s.maxX + 40)]
                guard let side = sides
                    .filter({ pick.contains(x: $0.landX) })
                    .min(by: { abs($0.edge - body.position.x) < abs($1.edge - body.position.x) })
                else { return }
                hopDownDirection = side.dir
                targetX = side.edge
            } else {
                let x = min(max(body.position.x, pick.minX + 30), pick.maxX - 30)
                body.jump(to: CGPoint(x: x, y: pick.y))
            }
            hopStarted = true
        default:
            break
        }
    }

    public func step(_ b: Behavior, body: Body, world: World, cursor: CGPoint) -> Bool {
        if b == .chaseMe || b == .askCare {
            stepChaseMe(body: body, world: world, cursor: cursor)
            return false
        }
        if b == .ballChase { return stepBallChase(body: body) }
        if b == .hopToWindow {
            guard hopStarted else { return true }
            if let dir = hopDownDirection, body.mode == .grounded, let target = targetX {
                if abs(target - body.position.x) < 4 {
                    body.leap(direction: dir)
                    hopDownDirection = nil
                } else {
                    body.walk(direction: target - body.position.x, speed: body.config.walkSpeed * 1.5)
                }
            }
            return false
        }
        guard body.mode == .grounded else { return false }
        switch b {
        case .goHome:
            return stepHome(body: body, world: world)
        case .walk, .fetch:
            guard let target = targetX else { return b == .walk }
            let dx = target - body.position.x
            if abs(dx) < 4 {
                body.stop()
                return true
            }
            let speed = b == .walk ? body.config.walkSpeed * speedScale : body.config.runSpeed
            body.walk(direction: dx, speed: speed)
        case .zoomies:
            body.walk(direction: zoomDirection, speed: body.config.runSpeed * 1.2)
        case .chaseCursor:
            let segment = body.standingOn ?? world.segment(under: body.position)
            let dx = cursor.x - body.position.x
            if let s = segment, s.contains(x: cursor.x), abs(dx) > 30 {
                body.walk(direction: dx, speed: body.config.runSpeed)
            } else {
                body.stop()
                body.face(right: dx >= 0)
            }
        default:
            body.stop()
        }
        return false
    }

    public func handle(_ event: BodyEvent, behavior: Behavior, body: Body) -> Bool {
        switch (behavior, event) {
        case (.zoomies, .hitEdge):
            zoomDirection = -zoomDirection
            return false
        case (.walk, .hitEdge):
            return true
        case (.hopToWindow, .landed):
            return true
        case (.ballChase, .landed):
            return ballPhase == .dropping
        case (.goHome, .landed):
            homePlanned = false
            return false
        case (.goHome, .hitEdge):
            if let dir = homeLeapDirection {
                body.leap(direction: dir)
                homeLeapDirection = nil
            }
            return false
        case (.hopToWindow, .hitEdge):
            if let dir = hopDownDirection {
                body.leap(direction: dir)
                hopDownDirection = nil
            }
            return false
        default:
            return false
        }
    }

    /// Walks (runs if far) to `home`. From another floor it leaps off the edge facing home,
    /// or jumps up if home is higher and in range, then re-plans after landing.
    private func stepHome(body: Body, world: World) -> Bool {
        guard let home else { return true }
        guard let s = body.standingOn ?? world.segment(under: body.position) else { return false }
        if s.contains(x: home.x) && abs(s.y - home.y) <= 2 {
            let dx = home.x - body.position.x
            if abs(dx) < 4 {
                body.stop()
                return true
            }
            body.walk(direction: dx, speed: abs(dx) > 300 ? body.config.runSpeed : body.config.walkSpeed)
            return false
        }
        if home.y > s.y + 2 {
            guard let hs = world.segment(under: home), home.y - s.y <= body.config.maxJumpUp else { return true }
            let gap = hs.clampX(body.position.x) - body.position.x
            if abs(gap) > body.config.maxJumpAcross {
                let x = s.clampX(hs.clampX(body.position.x))
                guard abs(hs.clampX(x) - x) <= body.config.maxJumpAcross else { return true }
                body.walk(direction: gap, speed: body.config.runSpeed)
                return false
            }
            body.jump(to: CGPoint(x: min(max(body.position.x, hs.minX + 30), hs.maxX - 30), y: home.y))
            return false
        }
        if !homePlanned {
            homePlanned = true
            if home.x < s.minX {
                homeLeapDirection = -1
            } else if home.x > s.maxX {
                homeLeapDirection = 1
            } else {
                homeLeapDirection = body.position.x - s.minX <= s.maxX - body.position.x ? -1 : 1
            }
        }
        if let dir = homeLeapDirection {
            let edge = dir < 0 ? s.minX : s.maxX
            if abs(edge - body.position.x) < 4 {
                body.leap(direction: dir)
                homeLeapDirection = nil
            } else {
                body.walk(direction: edge - body.position.x, speed: body.config.runSpeed)
            }
        }
        return false
    }

    /// Runs after the cursor (clamped to the screens) and waits facing it once within `followDistance`.
    private func stepChaseMe(body: Body, world: World, cursor: CGPoint) {
        guard body.mode == .roaming else { return }
        let area = insetRects(world.screens, side: 20, top: body.config.roamHeadroom)
        let target = nearestPoint(to: cursor, in: area)
        if hypot(target.x - body.position.x, target.y - body.position.y) < followDistance {
            body.hover()
            body.face(right: cursor.x >= body.position.x)
        } else {
            body.roam(toward: target, speed: body.config.runSpeed)
        }
    }

    /// Chase the ball (mouth 30pt above the feet), carry it above home, then drop to the floor.
    /// Returns true when the ball is gone before the catch, or after landing with it.
    private func stepBallChase(body: Body) -> Bool {
        switch ballPhase {
        case .chasing:
            guard body.mode == .roaming else { return false }
            guard let ball = ballPosition else { return true }
            let mouth = CGPoint(x: body.position.x, y: body.position.y + 30)
            if hypot(ball.x - mouth.x, ball.y - mouth.y) <= catchRadius {
                ballPhase = .carrying
                carryingBall = true
                onBallCaught?()
            } else {
                body.roam(toward: CGPoint(x: ball.x, y: ball.y - 30), speed: body.config.runSpeed)
            }
        case .carrying:
            guard body.mode == .roaming else { return false }
            let target = home.map { CGPoint(x: $0.x, y: $0.y + 60) } ?? body.position
            if hypot(target.x - body.position.x, target.y - body.position.y) < 10 {
                body.stopRoaming()
                ballPhase = .dropping
            } else {
                body.roam(toward: target, speed: body.config.runSpeed)
            }
        case .dropping:
            break
        }
        return false
    }
}
