#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

public final class BehaviorExecutor {
    public var targetX: CGFloat?
    public var speedScale: CGFloat = 1
    /// Home spot for `goHome`. Set by the caller whenever screens change.
    public var home: CGPoint?
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
        if body.mode == .roaming && b != .chaseMe && b != .ballChase { body.stopRoaming() }
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
        if !homePlanned {
            homePlanned = true
            if home.y > s.y + 2 {
                guard let hs = world.segment(under: home),
                      home.y - s.y <= body.config.maxJumpUp,
                      abs(hs.clampX(body.position.x) - body.position.x) <= body.config.maxJumpAcross
                else { return true }
                body.jump(to: CGPoint(x: min(max(body.position.x, hs.minX + 30), hs.maxX - 30), y: home.y))
                return false
            }
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
}
