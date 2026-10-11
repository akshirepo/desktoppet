import XCTest
@testable import CorgiCore

final class BodyTests: XCTestCase {
    var windows: FakeWindows!
    var world: World!

    override func setUp() {
        windows = FakeWindows()
        windows.windows = [WindowInfo(id: 1, frame: CGRect(x: 100, y: 0, width: 400, height: 300))]  // top 300
        world = World(provider: windows, screens: [screen0])
        world.refresh()
    }

    @discardableResult
    func run(_ body: Body, seconds: Double, dt: Double = 1.0 / 60) -> [BodyEvent] {
        var events: [BodyEvent] = []
        for _ in 0..<Int(seconds / dt) {
            if let e = body.step(dt: dt, world: world) { events.append(e) }
        }
        return events
    }

    func testFallsAndLandsOnGround() {
        let body = Body(position: CGPoint(x: 800, y: 500))
        XCTAssertEqual(run(body, seconds: 2), [.landed])
        XCTAssertEqual(body.mode, .grounded)
        XCTAssertEqual(body.position.y, 0)
        XCTAssertEqual(body.standingOn?.kind, .ground(screen: 0))
    }

    func testFallingOntoWindowEdge() {
        let body = Body(position: CGPoint(x: 300, y: 700))
        run(body, seconds: 2)
        XCTAssertEqual(body.standingOn?.windowID, 1)
        XCTAssertEqual(body.position.y, 300)
    }

    func testWalkStopsAtSegmentEdge() {
        let body = Body(position: CGPoint(x: 450, y: 300))
        run(body, seconds: 0.1)
        body.walk(direction: 1, speed: 100)
        XCTAssertTrue(body.facingRight)
        let events = run(body, seconds: 1)
        XCTAssertEqual(events, [.hitEdge])
        XCTAssertEqual(body.position.x, 500)
        XCTAssertFalse(body.isMoving)
    }

    func testJumpLandsOnHigherWindow() {
        let body = Body(position: CGPoint(x: 50, y: 0))
        run(body, seconds: 0.1)
        body.jump(to: CGPoint(x: 300, y: 300))
        XCTAssertEqual(body.mode, .airborne)
        run(body, seconds: 2)
        XCTAssertEqual(body.standingOn?.windowID, 1)
        XCTAssertEqual(body.position.x, 300, accuracy: 15)
    }

    func testLeapOffEdgeFallsToGround() {
        let body = Body(position: CGPoint(x: 120, y: 300))
        run(body, seconds: 0.1)
        body.leap(direction: -1)
        XCTAssertEqual(body.mode, .airborne)
        XCTAssertLessThan(body.position.x, 100)
        run(body, seconds: 2)
        XCTAssertEqual(body.standingOn?.kind, .ground(screen: 0))
    }

    func testRidesAlongWhenWindowMoves() {
        let body = Body(position: CGPoint(x: 300, y: 300))
        run(body, seconds: 0.1)
        windows.windows = [WindowInfo(id: 1, frame: CGRect(x: 150, y: 50, width: 400, height: 300))]
        body.apply(world.refresh())
        XCTAssertEqual(body.position, CGPoint(x: 350, y: 350))
        run(body, seconds: 0.1)
        XCTAssertEqual(body.standingOn?.windowID, 1)
    }

    func testFallsWhenWindowCloses() {
        let body = Body(position: CGPoint(x: 300, y: 300))
        run(body, seconds: 0.1)
        windows.windows = []
        XCTAssertEqual(body.apply(world.refresh()), .startedFalling)
        XCTAssertEqual(body.mode, .airborne)
        run(body, seconds: 2)
        XCTAssertEqual(body.standingOn?.kind, .ground(screen: 0))
    }

    func testFallsWhenEdgeGetsCovered() {
        let body = Body(position: CGPoint(x: 300, y: 300))
        run(body, seconds: 0.1)
        windows.windows.insert(WindowInfo(id: 2, frame: CGRect(x: 0, y: 250, width: 1440, height: 200)), at: 0)
        world.refresh()
        XCTAssertEqual(body.step(dt: 1.0 / 60, world: world), .startedFalling)
    }

    func testHeldBodyIgnoresWindowChanges() {
        let body = Body(position: CGPoint(x: 300, y: 300))
        run(body, seconds: 0.1)
        body.pickUp()
        body.moveHeld(to: CGPoint(x: 700, y: 600))
        windows.windows = []
        XCTAssertNil(body.apply(world.refresh()))
        run(body, seconds: 1)
        XCTAssertEqual(body.mode, .held)
        XCTAssertEqual(body.position, CGPoint(x: 700, y: 600))
        body.release()
        run(body, seconds: 2)
        XCTAssertEqual(body.mode, .grounded)
        XCTAssertEqual(body.position.y, 0)
    }

    func testAirborneBodyIsNotCarried() {
        let body = Body(position: CGPoint(x: 300, y: 300))
        run(body, seconds: 0.1)
        body.jump(to: CGPoint(x: 800, y: 0))
        let before = body.position
        windows.windows = [WindowInfo(id: 1, frame: CGRect(x: 150, y: 50, width: 400, height: 300))]
        XCTAssertNil(body.apply(world.refresh()))
        XCTAssertEqual(body.position, before)
    }

    func testClampAfterMonitorUnplugged() {
        let screen1 = CGRect(x: 1440, y: 0, width: 1920, height: 1000)
        world.setScreens([screen0, screen1])
        let body = Body(position: CGPoint(x: 2000, y: 0))
        run(body, seconds: 0.1)
        world.setScreens([screen0])
        body.clamp(to: world.screens)
        XCTAssertLessThanOrEqual(body.position.x, 1440)
        run(body, seconds: 2)
        XCTAssertEqual(body.mode, .grounded)
        XCTAssertEqual(body.standingOn?.kind, .ground(screen: 0))
    }
}
