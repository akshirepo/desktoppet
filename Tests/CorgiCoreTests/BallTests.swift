import XCTest
@testable import CorgiCore

final class BallTests: XCTestCase {
    let dt = 1.0 / 60

    func testBallStaysOnScreenAndKeepsPickingWaypoints() {
        let ball = Ball(start: CGPoint(x: 700, y: 400), screens: [screen0], rng: SeededRandom(seed: 5))
        var waypoints = Set<String>()
        var travelled: CGFloat = 0
        var last = ball.position
        for _ in 0..<Int(29 / dt) {
            ball.step(dt: dt)
            XCTAssertTrue(rects(ball.area, contain: ball.position))
            waypoints.insert("\(ball.waypoint)")
            travelled += hypot(ball.position.x - last.x, ball.position.y - last.y)
            last = ball.position
        }
        XCTAssertGreaterThanOrEqual(waypoints.count, 14)   // a new one every 1-2s
        XCTAssertGreaterThan(travelled, 1500)
        XCTAssertFalse(ball.popped)
    }

    func testBallPopsAfterThirtySeconds() {
        let ball = Ball(start: CGPoint(x: 700, y: 400), screens: [screen0], rng: SeededRandom(seed: 1))
        for _ in 0..<Int(30 / dt) + 1 { ball.step(dt: dt) }
        XCTAssertTrue(ball.popped)
    }

    func testBallComesBackWhenItsMonitorIsUnplugged() {
        let screen1 = CGRect(x: 1440, y: 0, width: 1920, height: 1000)
        let ball = Ball(start: CGPoint(x: 2500, y: 600), screens: [screen0, screen1], rng: SeededRandom(seed: 2))
        ball.step(dt: dt)
        ball.setScreens([screen0])
        XCTAssertTrue(rects(ball.area, contain: ball.position))
        XCTAssertTrue(rects(ball.area, contain: ball.waypoint))
        for _ in 0..<120 {
            ball.step(dt: dt)
            XCTAssertTrue(rects(ball.area, contain: ball.position))
        }
    }
}

final class RoamSteeringTests: XCTestCase {
    var world: World!
    let dt = 1.0 / 60

    override func setUp() {
        world = World(provider: FakeWindows(), screens: [screen0])
        world.refresh()
    }

    func tick(_ ex: BehaviorExecutor, _ b: Behavior, _ body: Body, cursor: CGPoint) -> Bool {
        if ex.step(b, body: body, world: world, cursor: cursor) { return true }
        if let e = body.step(dt: dt, world: world), ex.handle(e, behavior: b, body: body) { return true }
        return false
    }

    func testChaseMeFollowsTheCursorAndWaitsBesideIt() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 4))
        let body = Body(position: CGPoint(x: 700, y: 400))
        ex.begin(.chaseMe, body: body, world: world, cursor: .zero)
        XCTAssertEqual(body.mode, .roaming)
        let cursor = CGPoint(x: 300, y: 400)
        for _ in 0..<Int(3 / dt) {
            XCTAssertFalse(tick(ex, .chaseMe, body, cursor: cursor))
            XCTAssertGreaterThan(body.position.x, cursor.x)   // never runs past it
        }
        XCTAssertLessThan(hypot(body.position.x - cursor.x, body.position.y - cursor.y), ex.followDistance)
        XCTAssertGreaterThan(body.position.x, cursor.x + 100)
        XCTAssertFalse(body.facingRight)
        let waiting = body.position
        for _ in 0..<Int(1 / dt) { _ = tick(ex, .chaseMe, body, cursor: cursor) }
        XCTAssertEqual(body.position, waiting)
        XCTAssertEqual(body.mode, .roaming)
    }

    func testChaseMeTurnsToFaceTheCursorWhileWaiting() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 4))
        let body = Body(position: CGPoint(x: 700, y: 400))
        ex.begin(.chaseMe, body: body, world: world, cursor: .zero)
        body.face(right: false)
        for _ in 0..<5 { _ = tick(ex, .chaseMe, body, cursor: CGPoint(x: 750, y: 400)) }
        XCTAssertEqual(body.position, CGPoint(x: 700, y: 400))
        XCTAssertTrue(body.facingRight)
        for _ in 0..<5 { _ = tick(ex, .chaseMe, body, cursor: CGPoint(x: 650, y: 400)) }
        XCTAssertEqual(body.position, CGPoint(x: 700, y: 400))
        XCTAssertFalse(body.facingRight)
    }

    func testChaseMeStaysInsideTheScreensWhenTheCursorIsOff() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 4))
        let body = Body(position: CGPoint(x: 700, y: 300))
        ex.begin(.chaseMe, body: body, world: world, cursor: .zero)
        let area = insetRects(world.screens, side: 20, top: body.config.roamHeadroom)
        let cursor = CGPoint(x: -500, y: -500)
        for _ in 0..<Int(10 / dt) {
            XCTAssertFalse(tick(ex, .chaseMe, body, cursor: cursor))
            XCTAssertTrue(rects(area, contain: body.position))
        }
        let corner = nearestPoint(to: cursor, in: area)
        XCTAssertLessThan(hypot(body.position.x - corner.x, body.position.y - corner.y), ex.followDistance)
        XCTAssertEqual(body.mode, .roaming)
    }

    func testBallChaseCatchesCarriesHomeAndDrops() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        ex.home = CGPoint(x: 1360, y: 0)
        var catches = 0
        ex.onBallCaught = { catches += 1 }
        let ball = Ball(start: CGPoint(x: 200, y: 600), screens: [screen0], rng: SeededRandom(seed: 9))
        let body = Body(position: CGPoint(x: 1000, y: 0))
        _ = body.step(dt: dt, world: world)
        ex.begin(.ballChase, body: body, world: world, cursor: .zero)
        var done = false
        for _ in 0..<Int(30 / dt) {
            ball.step(dt: dt)
            ex.ballPosition = catches == 0 ? ball.position : nil
            if tick(ex, .ballChase, body, cursor: .zero) {
                done = true
                break
            }
        }
        XCTAssertTrue(done)
        XCTAssertEqual(catches, 1)
        XCTAssertTrue(ex.carryingBall)
        XCTAssertEqual(body.mode, .grounded)
        XCTAssertEqual(body.position.x, 1360, accuracy: 15)
    }

    func testBallChaseEndsWhenBallIsGone() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        let body = Body(position: CGPoint(x: 700, y: 300))
        ex.begin(.ballChase, body: body, world: world, cursor: .zero)
        ex.ballPosition = nil
        XCTAssertTrue(ex.step(.ballChase, body: body, world: world, cursor: .zero))
    }
}
