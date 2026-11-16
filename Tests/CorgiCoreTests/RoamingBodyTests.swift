import XCTest
@testable import CorgiCore

final class RoamingBodyTests: XCTestCase {
    var world: World!

    override func setUp() {
        world = World(provider: FakeWindows(), screens: [screen0])
        world.refresh()
    }

    func run(_ body: Body, seconds: Double, dt: Double = 1.0 / 60) -> [BodyEvent] {
        var events: [BodyEvent] = []
        for _ in 0..<Int(seconds / dt) {
            if let e = body.step(dt: dt, world: world) { events.append(e) }
        }
        return events
    }

    func testRoamingFliesWithoutGravity() {
        let body = Body(position: CGPoint(x: 200, y: 400))
        body.startRoaming()
        body.roam(toward: CGPoint(x: 600, y: 400), speed: 240)
        XCTAssertTrue(body.isMoving)
        XCTAssertEqual(run(body, seconds: 1), [])
        XCTAssertEqual(body.mode, .roaming)
        XCTAssertEqual(body.position.x, 440, accuracy: 2)
        XCTAssertEqual(body.position.y, 400, accuracy: 0.001)
        XCTAssertTrue(body.facingRight)
    }

    func testRoamingStaysInsideScreenHeadroom() {
        let body = Body(position: CGPoint(x: 700, y: 700))
        body.startRoaming()
        body.roam(toward: CGPoint(x: 700, y: 5000), speed: 400)
        let events = run(body, seconds: 1)
        XCTAssertEqual(events.first, .hitEdge)
        XCTAssertEqual(body.position.y, 875 - body.config.roamHeadroom, accuracy: 0.001)
        XCTAssertEqual(body.mode, .roaming)
    }

    func testStopRoamingFallsToFloor() {
        let body = Body(position: CGPoint(x: 300, y: 500))
        body.startRoaming()
        body.stopRoaming()
        XCTAssertEqual(body.mode, .airborne)
        XCTAssertEqual(run(body, seconds: 2), [.landed])
        XCTAssertEqual(body.standingOn?.kind, .ground(screen: 0))
    }

    func testRoamingSurvivesMonitorUnplug() {
        let screen1 = CGRect(x: 1440, y: 0, width: 1920, height: 1000)
        world.setScreens([screen0, screen1])
        let body = Body(position: CGPoint(x: 2500, y: 600))
        body.startRoaming()
        world.setScreens([screen0])
        body.clamp(to: world.screens)
        XCTAssertEqual(body.mode, .roaming)
        _ = run(body, seconds: 0.1)
        XCTAssertLessThanOrEqual(body.position.x, 1420)
        XCTAssertLessThanOrEqual(body.position.y, 875 - body.config.roamHeadroom)
    }

    func testPickUpWhileRoamingThenReleaseFalls() {
        let body = Body(position: CGPoint(x: 300, y: 500))
        body.startRoaming()
        body.pickUp()
        XCTAssertEqual(body.mode, .held)
        body.startRoaming()
        XCTAssertEqual(body.mode, .held)
        body.release()
        XCTAssertEqual(run(body, seconds: 2), [.landed])
    }

    func testIsRunningOnlyAboveStrollPace() {
        let body = Body(position: CGPoint(x: 300, y: 0))
        _ = run(body, seconds: 0.1)
        body.walk(direction: 1, speed: body.config.walkSpeed)
        XCTAssertFalse(body.isRunning)
        body.walk(direction: 1, speed: body.config.runSpeed)
        XCTAssertTrue(body.isRunning)
    }

    func testFloatingDownIsSlowerThanFallingAndEndsOnLanding() {
        func descend(gently: Bool) -> (seconds: Double, floated: Bool) {
            let world = World(provider: FakeWindows(), screens: [CGRect(x: 0, y: 0, width: 1440, height: 900)])
            world.refresh()
            let body = Body(position: CGPoint(x: 700, y: 0))
            for _ in 0..<5 { body.step(dt: 1.0 / 60, world: world) }
            body.startRoaming()
            for _ in 0..<120 {
                body.roam(toward: CGPoint(x: 700, y: 500), speed: 400)
                body.step(dt: 1.0 / 60, world: world)
            }
            body.stopRoaming(gently: gently)
            let floated = body.isFloatingDown
            var t = 0.0
            while body.mode == .airborne && t < 10 {
                body.step(dt: 1.0 / 60, world: world)
                t += 1.0 / 60
            }
            XCTAssertEqual(body.mode, .grounded)
            XCTAssertFalse(body.isFloatingDown)
            return (t, floated)
        }
        let fall = descend(gently: false), float = descend(gently: true)
        XCTAssertFalse(fall.floated)
        XCTAssertTrue(float.floated)
        XCTAssertGreaterThan(float.seconds, fall.seconds * 1.5)
        XCTAssertLessThan(float.seconds, 2.5, "still gets down promptly")
    }

    func testBeingPickedUpEndsTheFloat() {
        let body = Body(position: CGPoint(x: 700, y: 400))
        body.startRoaming()
        body.stopRoaming(gently: true)
        XCTAssertTrue(body.isFloatingDown)
        body.pickUp()
        body.release()
        XCTAssertFalse(body.isFloatingDown, "let go after a drag, it's a real drop")
    }
}
