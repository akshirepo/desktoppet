import XCTest
@testable import CorgiCore

final class ClingTests: XCTestCase {
    // AppKit coords: window 1 spans x 200...800, y 100...500 (top edge at y 500).
    let win = WindowInfo(id: 1, frame: CGRect(x: 200, y: 100, width: 600, height: 400))

    func testFindsEachEdge() {
        XCTAssertEqual(ClingFinder.find(CGPoint(x: 190, y: 300), windows: [win])?.edge, .left)
        XCTAssertEqual(ClingFinder.find(CGPoint(x: 815, y: 300), windows: [win])?.edge, .right)
        XCTAssertEqual(ClingFinder.find(CGPoint(x: 500, y: 90), windows: [win])?.edge, .bottom)
        let above = ClingFinder.find(CGPoint(x: 500, y: 520), windows: [win])
        XCTAssertEqual(above?.edge, .top)
        XCTAssertEqual(above?.above, true)
        let below = ClingFinder.find(CGPoint(x: 500, y: 480), windows: [win])
        XCTAssertEqual(below?.edge, .top)
        XCTAssertEqual(below?.above, false)
    }

    func testOutOfReachOrFarAlongTheEdgeFindsNothing() {
        XCTAssertNil(ClingFinder.find(CGPoint(x: 500, y: 300), windows: [win]))      // middle of the window
        XCTAssertNil(ClingFinder.find(CGPoint(x: 120, y: 300), windows: [win]))      // 80pt left of the edge
        XCTAssertNil(ClingFinder.find(CGPoint(x: 190, y: 700), windows: [win]))      // beside the edge line, too high
    }

    func testEdgeCoveredByAFrontWindowIsSkipped() {
        let front = WindowInfo(id: 2, frame: CGRect(x: 100, y: 200, width: 200, height: 200))  // covers win's left edge around y 300
        let spot = ClingFinder.find(CGPoint(x: 195, y: 300), windows: [front, win])
        XCTAssertNotEqual(spot?.windowID, 1)
    }

    func testFrontmostWindowWins() {
        let back = WindowInfo(id: 3, frame: CGRect(x: 190, y: 100, width: 600, height: 400))
        XCTAssertEqual(ClingFinder.find(CGPoint(x: 195, y: 300), windows: [win, back])?.windowID, 1)
    }

    func testContactFollowsTheWindowAndVanishes() {
        let spot = ClingFinder.find(CGPoint(x: 190, y: 300), windows: [win])!
        XCTAssertEqual(ClingFinder.contact(spot, windows: [win]), CGPoint(x: 200, y: 300))
        let moved = WindowInfo(id: 1, frame: CGRect(x: 250, y: 150, width: 600, height: 400))
        XCTAssertEqual(ClingFinder.contact(spot, windows: [moved]), CGPoint(x: 250, y: 350))
        XCTAssertNil(ClingFinder.contact(spot, windows: []))
    }

    func testAnimationStatePerEdge() {
        XCTAssertEqual(ClingSpot(windowID: 1, edge: .top, along: 0.5, above: true).animState, .clingSit)
        XCTAssertEqual(ClingSpot(windowID: 1, edge: .top, along: 0.5, above: false).animState, .clingHang)
        XCTAssertEqual(ClingSpot(windowID: 1, edge: .bottom, along: 0.5, above: false).animState, .clingHang)
        XCTAssertEqual(ClingSpot(windowID: 1, edge: .left, along: 0.5, above: false).animState, .clingLeft)
        XCTAssertEqual(ClingSpot(windowID: 1, edge: .right, along: 0.5, above: false).animState, .clingRight)
    }

    func testBodyClingsRidesAlongAndFallsWhenWindowCloses() {
        let provider = FakeWindows()
        provider.windows = [win]
        let world = World(provider: provider, screens: [CGRect(x: 0, y: 0, width: 1440, height: 875)])
        world.refresh()
        let body = Body(position: CGPoint(x: 190, y: 300))
        let spot = ClingFinder.find(body.position, windows: world.windows)!
        body.startClinging(spot, at: ClingFinder.contact(spot, windows: world.windows)!)
        XCTAssertEqual(body.mode, .clinging)
        XCTAssertFalse(body.isMoving)
        XCTAssertNil(body.step(dt: 0.5, world: world))
        XCTAssertEqual(body.position, CGPoint(x: 200, y: 300))   // no gravity while clinging

        provider.windows = [WindowInfo(id: 1, frame: CGRect(x: 300, y: 100, width: 600, height: 400))]
        world.refresh()
        XCTAssertNil(body.followCling(world))
        XCTAssertEqual(body.position, CGPoint(x: 300, y: 300))

        provider.windows = []
        world.refresh()
        XCTAssertEqual(body.followCling(world), .startedFalling)
        XCTAssertEqual(body.mode, .airborne)
        XCTAssertNil(body.cling)
    }

    func testLetGoFallsAndClampLeavesAClingingBodyAlone() {
        let body = Body(position: CGPoint(x: 200, y: 300))
        body.startClinging(ClingSpot(windowID: 1, edge: .left, along: 0.5, above: false), at: CGPoint(x: 200, y: 300))
        body.clamp(to: [CGRect(x: 0, y: 0, width: 1440, height: 875)])
        XCTAssertEqual(body.mode, .clinging)
        XCTAssertEqual(body.letGo(), .startedFalling)
        XCTAssertEqual(body.mode, .airborne)
        XCTAssertNil(body.letGo())
    }

    func testPickingUpAClingingBodyReleasesTheGrip() {
        let body = Body(position: CGPoint(x: 200, y: 300))
        body.startClinging(ClingSpot(windowID: 1, edge: .right, along: 0.5, above: false), at: CGPoint(x: 200, y: 300))
        XCTAssertFalse(body.facingRight)
        body.pickUp()
        XCTAssertEqual(body.mode, .held)
        XCTAssertNil(body.cling)
    }

    func testClingBehaviorLastsAFewMinutes() {
        XCTAssertEqual(BrainConfig().durations[.cling], 180...360)
        XCTAssertFalse(Behavior.autonomous.contains(.cling))
    }
}
