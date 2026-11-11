import XCTest
@testable import CorgiCore

final class SpaceArrivalTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let floor = FloorSegment(kind: .ground(screen: 0), y: 0, minX: 0, maxX: 1440)

    func testMovingToTheSpaceOnTheRightComesInFromTheLeft() throws {
        let plan = try XCTUnwrap(SpaceArrival.plan(step: 1, screen: screen, floor: floor, feetX: 1200, reach: 80, depth: 0.25))
        XCTAssertTrue(plan.fromLeft)
        XCTAssertEqual(plan.startX, -80)
        XCTAssertEqual(plan.stopX, 360)
    }

    func testMovingLeftComesInFromTheRight() throws {
        let plan = try XCTUnwrap(SpaceArrival.plan(step: -2, screen: screen, floor: floor, feetX: 100, reach: 80, depth: 0.25))
        XCTAssertFalse(plan.fromLeft)
        XCTAssertEqual(plan.startX, 1520)
        XCTAssertEqual(plan.stopX, 1080)
    }

    func testUnknownDirectionUsesTheNearerSide() throws {
        XCTAssertTrue(try XCTUnwrap(SpaceArrival.plan(step: nil, screen: screen, floor: floor, feetX: 300, reach: 80, depth: 0.3)).fromLeft)
        XCTAssertFalse(try XCTUnwrap(SpaceArrival.plan(step: nil, screen: screen, floor: floor, feetX: 1300, reach: 80, depth: 0.3)).fromLeft)
    }

    func testNoArrivalWhenItsDisplayKeptItsSpace() {
        XCTAssertNil(SpaceArrival.plan(step: 0, screen: screen, floor: floor, feetX: 300, reach: 80, depth: 0.3))
    }

    func testRunsInFromPastTheEdgeAndKeepsRunningOnTheFloor() {
        let world = World(provider: FakeWindows(), screens: [screen])
        world.refresh()
        let ground = world.ground(of: 0)!
        let body = Body(position: CGPoint(x: 700, y: 0))
        body.startEntering(onto: ground, from: ground.minX - 80)
        XCTAssertEqual(body.mode, .entering)
        XCTAssertTrue(body.facingRight)
        XCTAssertTrue(body.isRunning)
        // No floor out there, but it doesn't fall or get pulled back while it's coming in.
        XCTAssertNil(body.step(dt: 0.1, world: world))
        XCTAssertEqual(body.mode, .entering)
        XCTAssertNil(body.clamp(to: [screen]))
        // A stop from a behavior starting meanwhile doesn't strand it out of sight.
        body.stop()
        for _ in 0..<10 { body.step(dt: 0.1, world: world) }
        XCTAssertEqual(body.mode, .grounded)
        XCTAssertEqual(body.standingOn, ground)
        XCTAssertTrue(body.isRunning)
        XCTAssertGreaterThan(body.position.x, ground.minX)
    }

    func testArriveRunsToItsSpotAndFinishes() {
        let world = World(provider: FakeWindows(), screens: [screen])
        world.refresh()
        let ground = world.ground(of: 0)!
        let body = Body(position: CGPoint(x: 700, y: 0))
        let executor = BehaviorExecutor()
        executor.begin(.arrive, body: body, world: world, cursor: .zero)
        executor.arriveX = 400
        body.startEntering(onto: ground, from: ground.minX - 80)
        var finished = false
        for _ in 0..<300 where !finished {
            finished = executor.step(.arrive, body: body, world: world, cursor: .zero)
            body.step(dt: 1.0 / 60, world: world)
        }
        XCTAssertTrue(finished)
        XCTAssertEqual(body.position.x, 400, accuracy: 6)
        XCTAssertEqual(body.mode, .grounded)
        XCTAssertFalse(body.isMoving)
    }
}
