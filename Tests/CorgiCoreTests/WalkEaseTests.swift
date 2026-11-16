import XCTest
@testable import CorgiCore

final class WalkEaseTests: XCTestCase {
    private func world() -> World {
        let w = World(provider: FakeWindows(), screens: [CGRect(x: 0, y: 0, width: 1440, height: 900)])
        w.refresh()
        return w
    }

    private func grounded(_ world: World, ease: CGFloat?) -> Body {
        var config = BodyConfig()
        config.walkEase = ease
        let body = Body(position: CGPoint(x: 400, y: 200), config: config)
        for _ in 0..<120 where body.mode != .grounded { body.step(dt: 1.0 / 60, world: world) }
        XCTAssertEqual(body.mode, .grounded)
        return body
    }

    func testWithoutEasingSpeedChangesAtOnce() {
        let w = world(), body = grounded(w, ease: nil)
        body.walk(direction: 1, speed: 70)
        body.step(dt: 1.0 / 60, world: w)
        XCTAssertEqual(body.groundSpeed, 70)
        body.stop()
        let x = body.position.x
        body.step(dt: 1.0 / 60, world: w)
        XCTAssertEqual(body.position.x, x)
    }

    func testEasesUpToSpeedAndGlidesToAStop() {
        let w = world(), body = grounded(w, ease: 12)
        body.walk(direction: 1, speed: 240)
        body.step(dt: 1.0 / 60, world: w)
        XCTAssertGreaterThan(body.groundSpeed, 0)
        XCTAssertLessThan(body.groundSpeed, 120, "not at speed on the first tick")
        for _ in 0..<40 { body.step(dt: 1.0 / 60, world: w) }
        XCTAssertEqual(body.groundSpeed, 240, "reaches the asked speed")
        body.stop()
        XCTAssertFalse(body.isMoving, "legs stop being driven at once")
        let x = body.position.x
        for _ in 0..<60 { body.step(dt: 1.0 / 60, world: w) }
        XCTAssertEqual(body.groundSpeed, 0)
        XCTAssertGreaterThan(body.position.x, x + 5, "glides on a little")
        XCTAssertLessThan(body.position.x, x + 30, "and not far")
    }

    func testEasingTurnsRoundThroughZero() {
        let w = world(), body = grounded(w, ease: 12)
        body.walk(direction: 1, speed: 70)
        for _ in 0..<40 { body.step(dt: 1.0 / 60, world: w) }
        body.walk(direction: -1, speed: 70)
        body.step(dt: 1.0 / 60, world: w)
        XCTAssertGreaterThan(body.groundSpeed, -70)
        for _ in 0..<40 { body.step(dt: 1.0 / 60, world: w) }
        XCTAssertEqual(body.groundSpeed, -70)
    }

    func testLeavingTheGroundDropsTheGlide() {
        let w = world(), body = grounded(w, ease: 12)
        body.walk(direction: 1, speed: 240)
        for _ in 0..<40 { body.step(dt: 1.0 / 60, world: w) }
        body.pickUp()
        body.step(dt: 1.0 / 60, world: w)
        XCTAssertEqual(body.groundSpeed, 0)
    }

    func testGlidingIntoTheEndOfTheFloorIsNotAnEdgeHit() {
        let w = world(), body = grounded(w, ease: 12)
        body.walk(direction: -1, speed: 240)
        var events: [BodyEvent] = []
        for _ in 0..<600 {
            if body.position.x < 12 { body.stop() }
            if let e = body.step(dt: 1.0 / 60, world: w) { events.append(e) }
        }
        XCTAssertEqual(events, [])
        XCTAssertEqual(body.groundSpeed, 0)
    }
}
