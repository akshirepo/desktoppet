import XCTest
@testable import CorgiCore

final class BehaviorExecutorTests: XCTestCase {
    var windows: FakeWindows!
    var world: World!
    let dt = 1.0 / 60

    override func setUp() {
        windows = FakeWindows()
        windows.windows = [WindowInfo(id: 1, frame: CGRect(x: 600, y: 0, width: 400, height: 300))]  // top 300
        world = World(provider: windows, screens: [screen0])
        world.refresh()
    }

    func groundedBody(x: CGFloat, y: CGFloat = 0) -> Body {
        let body = Body(position: CGPoint(x: x, y: y))
        body.step(dt: dt, world: world)
        return body
    }

    /// Runs until the executor reports done or time runs out. Returns true if done.
    func run(_ ex: BehaviorExecutor, _ b: Behavior, _ body: Body, cursor: CGPoint = .zero,
             seconds: Double) -> Bool {
        for _ in 0..<Int(seconds / dt) {
            if ex.step(b, body: body, world: world, cursor: cursor) { return true }
            if let e = body.step(dt: dt, world: world), ex.handle(e, behavior: b, body: body) { return true }
        }
        return false
    }

    func testWalkReachesRandomTargetOnSegment() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 3))
        let body = groundedBody(x: 200)
        ex.begin(.walk, body: body, world: world, cursor: .zero)
        let target = try! XCTUnwrap(ex.targetX)
        XCTAssertTrue((20...1420).contains(target))
        XCTAssertTrue(run(ex, .walk, body, seconds: 30))
        XCTAssertEqual(body.position.x, target, accuracy: 4)
    }

    func testChaseRunsTowardCursorOnSameSegment() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        let body = groundedBody(x: 100)
        let cursor = CGPoint(x: 500, y: 400)
        ex.begin(.chaseCursor, body: body, world: world, cursor: cursor)
        _ = run(ex, .chaseCursor, body, cursor: cursor, seconds: 3)
        XCTAssertEqual(body.position.x, 500, accuracy: 31)
        XCTAssertTrue(body.facingRight)
    }

    func testChaseWithCursorOffSegmentJustFacesIt() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        let body = groundedBody(x: 800, y: 300)       // on window 1 (600...1000)
        let cursor = CGPoint(x: 100, y: 50)
        ex.begin(.chaseCursor, body: body, world: world, cursor: cursor)
        _ = run(ex, .chaseCursor, body, cursor: cursor, seconds: 1)
        XCTAssertEqual(body.position.x, 800)
        XCTAssertFalse(body.facingRight)
    }

    func testHopJumpsOntoReachableWindowAndFinishesOnLanding() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        let body = groundedBody(x: 400)
        ex.begin(.hopToWindow, body: body, world: world, cursor: .zero)
        XCTAssertEqual(body.mode, .airborne)
        XCTAssertTrue(run(ex, .hopToWindow, body, seconds: 3))
        XCTAssertEqual(body.standingOn?.windowID, 1)
    }

    func testHopFromWindowCanGoBackDown() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        let body = groundedBody(x: 800, y: 300)       // on window 1, only the ground is reachable
        ex.begin(.hopToWindow, body: body, world: world, cursor: .zero)
        XCTAssertTrue(run(ex, .hopToWindow, body, seconds: 6))
        XCTAssertEqual(body.standingOn?.kind, .ground(screen: 0))
    }

    func testHopWithNothingReachableFinishesImmediately() {
        windows.windows = []
        world.refresh()
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        let body = groundedBody(x: 400)
        ex.begin(.hopToWindow, body: body, world: world, cursor: .zero)
        XCTAssertTrue(ex.step(.hopToWindow, body: body, world: world, cursor: .zero))
    }

    func testZoomiesBounceBetweenEdges() {
        for tick in [1.0 / 30, 1.0 / 60] {
            let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
            let body = groundedBody(x: 800, y: 300)
            ex.begin(.zoomies, body: body, world: world, cursor: .zero)
            var facings = Set<Bool>()
            var edgeCount = 0
            for _ in 0..<Int(6 / tick) {
                _ = ex.step(.zoomies, body: body, world: world, cursor: .zero)
                if let event = body.step(dt: tick, world: world) {
                    let previousFacing = body.facingRight
                    _ = ex.handle(event, behavior: .zoomies, body: body)
                    if event == .hitEdge {
                        edgeCount += 1
                        XCTAssertTrue(body.isMoving, "The edge-event tick must keep running at dt=\(tick)")
                        XCTAssertTrue(body.isRunning)
                        XCTAssertNotEqual(body.facingRight, previousFacing)
                        XCTAssertEqual(animState(for: .zoomies, mode: body.mode, isMoving: body.isMoving,
                                                 isRunning: body.isRunning), .run)
                    }
                }
                facings.insert(body.facingRight)
                XCTAssertTrue((600...1000).contains(body.position.x))
            }
            XCTAssertGreaterThan(edgeCount, 2)
            XCTAssertEqual(facings, [true, false])
        }
    }

    func testFetchWalksToCallerTarget() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        let body = groundedBody(x: 100)
        ex.begin(.fetch, body: body, world: world, cursor: .zero)
        ex.targetX = 400
        XCTAssertTrue(run(ex, .fetch, body, seconds: 5))
        XCTAssertEqual(body.position.x, 400, accuracy: 4)
    }

    func testStationaryBehaviorsStop() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        let body = groundedBody(x: 100)
        body.walk(direction: 1, speed: 70)
        ex.begin(.sleep, body: body, world: world, cursor: .zero)
        XCTAssertFalse(run(ex, .sleep, body, seconds: 1))
        XCTAssertEqual(body.position.x, 100)
    }

    func homeExecutor() -> BehaviorExecutor {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        ex.home = CGPoint(x: 1360, y: 0)
        return ex
    }

    func testGoHomeRunsWhenFarAndArrives() {
        let ex = homeExecutor()
        let body = groundedBody(x: 100)
        ex.begin(.goHome, body: body, world: world, cursor: .zero)
        _ = ex.step(.goHome, body: body, world: world, cursor: .zero)
        XCTAssertTrue(body.isRunning)
        XCTAssertTrue(run(ex, .goHome, body, seconds: 10))
        XCTAssertEqual(body.position.x, 1360, accuracy: 4)
    }

    func testGoHomeFromPerchLeapsDownThenWalksHome() {
        let ex = homeExecutor()
        let body = groundedBody(x: 800, y: 300)        // on window 1 (600...1000)
        ex.begin(.goHome, body: body, world: world, cursor: .zero)
        XCTAssertTrue(run(ex, .goHome, body, seconds: 15))
        XCTAssertEqual(body.standingOn?.kind, .ground(screen: 0))
        XCTAssertEqual(body.position.x, 1360, accuracy: 4)
    }

    func testGoHomeFromOtherMonitorCrossesOver() {
        world.setScreens([screen0, CGRect(x: 1440, y: 0, width: 1920, height: 1000)])
        let ex = homeExecutor()
        let body = groundedBody(x: 2400)
        ex.begin(.goHome, body: body, world: world, cursor: .zero)
        XCTAssertTrue(run(ex, .goHome, body, seconds: 15))
        XCTAssertEqual(body.standingOn?.kind, .ground(screen: 0))
        XCTAssertEqual(body.position.x, 1360, accuracy: 4)
    }

    func testGoHomeFromFarSideOfLowerMonitorWalksOverThenJumpsUp() {
        // Dock only on the main screen, so its ground is higher than the second screen's.
        world.setScreens([CGRect(x: 0, y: 70, width: 1440, height: 830), CGRect(x: 1440, y: 0, width: 1920, height: 1000)])
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        ex.home = CGPoint(x: 1360, y: 70)
        let body = groundedBody(x: 2400)
        ex.begin(.goHome, body: body, world: world, cursor: .zero)
        XCTAssertTrue(run(ex, .goHome, body, seconds: 20))
        XCTAssertEqual(body.standingOn?.kind, .ground(screen: 0))
        XCTAssertEqual(body.position.x, 1360, accuracy: 4)
    }

    func testGoHomeAfterDropWaitsForLanding() {
        let ex = homeExecutor()
        let body = Body(position: CGPoint(x: 500, y: 600))   // just released, still in the air
        ex.begin(.goHome, body: body, world: world, cursor: .zero)
        XCTAssertFalse(ex.step(.goHome, body: body, world: world, cursor: .zero))
        XCTAssertTrue(run(ex, .goHome, body, seconds: 12))
        XCTAssertEqual(body.position.x, 1360, accuracy: 4)
    }

    func testGreetStandsAndFacesCursor() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        let body = groundedBody(x: 500)
        ex.begin(.greet, body: body, world: world, cursor: CGPoint(x: 100, y: 400))
        XCTAssertFalse(run(ex, .greet, body, cursor: CGPoint(x: 100, y: 400), seconds: 1))
        XCTAssertEqual(body.position.x, 500)
        XCTAssertFalse(body.facingRight)
    }

    func testNonRoamingBehaviorEndsRoaming() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        let body = Body(position: CGPoint(x: 300, y: 500))
        body.startRoaming()
        ex.begin(.chaseMe, body: body, world: world, cursor: .zero)
        XCTAssertEqual(body.mode, .roaming)
        ex.begin(.idle, body: body, world: world, cursor: .zero)
        XCTAssertEqual(body.mode, .airborne)
    }
}
