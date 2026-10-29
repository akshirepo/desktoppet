import XCTest
@testable import CorgiCore

final class MultiScreenTests: XCTestCase {
    let laptop = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let bounds = CGRect(x: -60, y: 0, width: 120, height: 100)

    func world(_ screens: [CGRect]) -> World {
        let w = World(provider: FakeWindows(), screens: screens, bodyBounds: bounds)
        w.refresh()
        return w
    }

    func testFindsSideBySideSeamsOnly() {
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let above = CGRect(x: 0, y: 875, width: 1440, height: 900)
        XCTAssertEqual(screenSeams([laptop, right]), [ScreenSeam(left: 0, right: 1, x: 1440, minY: 0, maxY: 875)])
        XCTAssertEqual(screenSeams([laptop, above]), [])
        XCTAssertEqual(screenSeams([right, laptop]).map(\.left), [1])
    }

    func testFloorsAtTheSameHeightBecomeOne() {
        let w = world([laptop, CGRect(x: 1440, y: 0, width: 1920, height: 1080)])
        let grounds = w.segments.filter { if case .ground = $0.kind { return true }; return false }
        XCTAssertEqual(grounds.count, 1)
        XCTAssertEqual(grounds[0].minX, 60)
        XCTAssertEqual(grounds[0].maxX, 1440 + 1920 - 60)
        XCTAssertTrue(rects(w.movementScreens, contain: CGPoint(x: 1440, y: 0)))   // straddling the seam is allowed
    }

    func testWalkingAcrossToALowerDisplayDropsOntoItsFloor() {
        let w = world([CGRect(x: 0, y: 200, width: 1440, height: 875), CGRect(x: 1440, y: 0, width: 1920, height: 1080)])
        let body = Body(position: CGPoint(x: 1430, y: 200))
        body.step(dt: 0.01, world: w)          // settles onto the floor
        body.walk(direction: 1, speed: body.config.runSpeed)
        var landed = false
        for _ in 0..<200 {
            if body.step(dt: 0.02, world: w) == .landed { landed = true; break }
        }
        XCTAssertTrue(landed)
        XCTAssertEqual(body.position.y, 0)
        XCTAssertGreaterThan(body.position.x, 1440)
    }

    func testWalkingToAHigherDisplayHopsUpWithinReach() {
        let w = world([laptop, CGRect(x: 1440, y: 150, width: 1920, height: 1080)])
        XCTAssertEqual(w.crossing(from: w.segment(under: CGPoint(x: 1000, y: 0))!, direction: 1, maxJumpUp: 420),
                       .jump(to: CGPoint(x: 1480, y: 150)))
        let body = Body(position: CGPoint(x: 1435, y: 0))
        body.step(dt: 0.01, world: w)
        body.walk(direction: 1, speed: body.config.walkSpeed)
        var landed = false
        for _ in 0..<300 {
            if body.step(dt: 0.02, world: w) == .landed { landed = true; break }
        }
        XCTAssertTrue(landed)
        XCTAssertEqual(body.position.y, 150)
    }

    func testTooHighAStepStopsAtItsOwnEdge() {
        let w = world([laptop, CGRect(x: 1440, y: 600, width: 1920, height: 1080)])
        let floor = w.segment(under: CGPoint(x: 1000, y: 0))!
        XCTAssertEqual(floor.maxX, 1440 - 60)                                // not extended into the void
        XCTAssertNil(w.crossing(from: floor, direction: 1, maxJumpUp: 420))
        let body = Body(position: CGPoint(x: 1370, y: 0))
        body.step(dt: 0.01, world: w)
        body.walk(direction: 1, speed: body.config.walkSpeed)
        XCTAssertEqual(body.step(dt: 0.5, world: w), .hitEdge)
    }

    func testRoamingCanCrossTheSeam() {
        let w = world([laptop, CGRect(x: 1440, y: 0, width: 1920, height: 1080)])
        XCTAssertTrue(rects(w.roamingScreens(headroom: 80), contain: CGPoint(x: 1440, y: 300)))
    }

    func testWalksSometimesHeadToTheNextDisplayAndCrossIt() {
        let w = world([CGRect(x: 0, y: 200, width: 1440, height: 875), CGRect(x: 1440, y: 0, width: 1920, height: 1080)])
        let e = BehaviorExecutor(rng: SeededRandom(seed: 3))
        e.crossScreenChance = 1
        let body = Body(position: CGPoint(x: 1300, y: 200))
        body.step(dt: 0.01, world: w)
        e.begin(.walk, body: body, world: w, cursor: .zero)
        var done = false
        for _ in 0..<2000 where !done {
            done = e.step(.walk, body: body, world: w, cursor: .zero)
            if let ev = body.step(dt: 0.02, world: w), e.handle(ev, behavior: .walk, body: body) { done = true }
        }
        XCTAssertTrue(done)
        XCTAssertGreaterThan(body.position.x, 1440)
        XCTAssertEqual(body.position.y, 0)
    }

    func testChasesTheCursorOntoTheNextDisplay() {
        let w = world([laptop, CGRect(x: 1440, y: 0, width: 1920, height: 1080)])
        let e = BehaviorExecutor()
        let body = Body(position: CGPoint(x: 1000, y: 0))
        body.step(dt: 0.01, world: w)
        e.begin(.chaseCursor, body: body, world: w, cursor: CGPoint(x: 2500, y: 500))
        for _ in 0..<400 {
            _ = e.step(.chaseCursor, body: body, world: w, cursor: CGPoint(x: 2500, y: 500))
            _ = body.step(dt: 0.02, world: w)
        }
        XCTAssertGreaterThan(body.position.x, 2400)
    }

    // The user's layout: laptop at the bottom, two monitors side by side on top of it.
    let mac = CGRect(x: 0, y: 0, width: 1728, height: 1084)
    let macFull = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let left = CGRect(x: -1201, y: 1117, width: 2560, height: 1440)
    let right = CGRect(x: 1359, y: 1207, width: 2560, height: 1350)
    let rightFull = CGRect(x: 1359, y: 1117, width: 2560, height: 1440)

    func stacked() -> World {
        let w = World(provider: FakeWindows(), screens: [mac, right, left], bodyBounds: bounds)
        w.setScreens([mac, right, left], fullFrames: [macFull, rightFull, left])
        w.refresh()
        return w
    }

    func run(_ b: Behavior, _ e: BehaviorExecutor, _ body: Body, _ w: World, cursor: CGPoint, steps: Int = 3000) {
        for _ in 0..<steps {
            if e.step(b, body: body, world: w, cursor: cursor) { break }
            if let ev = body.step(dt: 0.02, world: w) { _ = e.handle(ev, behavior: b, body: body) }
        }
    }

    func testFindsTheStackedMonitorsAndTheSeamBetweenThem() {
        let w = stacked()
        XCTAssertEqual(Set(w.stacks.map { [$0.lower, $0.upper] }), [[0, 1], [0, 2]])
        XCTAssertEqual(w.seams.map { [$0.left, $0.right] }, [[2, 1]])
        XCTAssertEqual(w.display(at: CGPoint(x: 500, y: 0)), 0)
        XCTAssertEqual(w.display(at: CGPoint(x: 500, y: 1117)), 2)
    }

    func testLeapsUpToTheMonitorAboveToChaseTheCursor() {
        let w = stacked()
        let e = BehaviorExecutor()
        let body = Body(position: CGPoint(x: 300, y: 0))
        body.step(dt: 0.01, world: w)
        run(.chaseCursor, e, body, w, cursor: CGPoint(x: 200, y: 1800), steps: 600)
        XCTAssertEqual(w.display(at: body.position), 2)
        XCTAssertEqual(body.position.y, 1117, accuracy: 1)
    }

    func testHopsDownToTheLaptopAndWalksOverTheDockStep() {
        let w = stacked()
        let e = BehaviorExecutor()
        let body = Body(position: CGPoint(x: -500, y: 1117))
        body.step(dt: 0.01, world: w)
        run(.chaseCursor, e, body, w, cursor: CGPoint(x: 900, y: 400), steps: 600)
        XCTAssertEqual(w.display(at: body.position), 0)
        XCTAssertEqual(body.position.y, 0, accuracy: 1)
        let body2 = Body(position: CGPoint(x: 1000, y: 1117))
        body2.step(dt: 0.01, world: w)
        run(.chaseCursor, e, body2, w, cursor: CGPoint(x: 3000, y: 2000), steps: 900)
        XCTAssertEqual(w.display(at: body2.position), 1)
        XCTAssertEqual(body2.position.y, 1207, accuracy: 1)
    }
}
