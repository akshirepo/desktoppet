import XCTest
@testable import CorgiCore

final class FakeWindows: WindowListProvider {
    var windows: [WindowInfo] = []
    func visibleWindows() -> [WindowInfo] { windows }
}

let screen0 = CGRect(x: 0, y: 0, width: 1440, height: 875)

final class GeometryTests: XCTestCase {
    func testCGBoundsConvertToAppKit() {
        let r = appKitRect(fromCGBounds: CGRect(x: 10, y: 100, width: 200, height: 50),
                           primaryScreenHeight: 900)
        XCTAssertEqual(r, CGRect(x: 10, y: 750, width: 200, height: 50))
    }

    func testSubtractIntervals() {
        XCTAssertEqual(subtractIntervals(0...100, []), [0...100])
        XCTAssertEqual(subtractIntervals(0...100, [40...60]), [0...40, 60...100])
        XCTAssertEqual(subtractIntervals(0...100, [-10...20, 90...200]), [20...90])
        XCTAssertEqual(subtractIntervals(0...100, [-1...101]), [])
        XCTAssertEqual(subtractIntervals(0...100, [50...70, 30...55]), [0...30, 70...100])
    }
}

final class FloorSegmentTests: XCTestCase {
    func world(_ windows: [WindowInfo]) -> World {
        let p = FakeWindows()
        p.windows = windows
        let w = World(provider: p, screens: [screen0])
        w.refresh()
        return w
    }

    func testGroundSegmentPerScreen() {
        let p = FakeWindows()
        let w = World(provider: p, screens: [screen0, CGRect(x: 1440, y: 100, width: 1920, height: 1000)])
        w.refresh()
        XCTAssertEqual(w.segments, [
            FloorSegment(kind: .ground(screen: 0), y: 0, minX: 0, maxX: 1440),
            FloorSegment(kind: .ground(screen: 1), y: 100, minX: 1440, maxX: 3360),
        ])
    }

    func testWindowTopEdgeBecomesSegment() {
        let w = world([WindowInfo(id: 7, frame: CGRect(x: 100, y: 200, width: 600, height: 400))])
        XCTAssertTrue(w.segments.contains(FloorSegment(kind: .window(id: 7), y: 600, minX: 100, maxX: 700)))
    }

    func testFrontWindowHidesPartOfBackWindowEdge() {
        let w = world([
            WindowInfo(id: 2, frame: CGRect(x: 400, y: 500, width: 600, height: 200)),  // front, top 700
            WindowInfo(id: 1, frame: CGRect(x: 100, y: 200, width: 600, height: 400)),  // back, top 600
        ])
        let back = w.segments.filter { $0.windowID == 1 }
        XCTAssertEqual(back, [FloorSegment(kind: .window(id: 1), y: 600, minX: 100, maxX: 400)])
    }

    func testWindowJustAboveEdgeAlsoHidesIt() {
        // Front window starts 30pt above the back edge, inside the corgi's headroom.
        let w = world([
            WindowInfo(id: 2, frame: CGRect(x: 0, y: 630, width: 1440, height: 100)),
            WindowInfo(id: 1, frame: CGRect(x: 100, y: 200, width: 600, height: 400)),
        ])
        XCTAssertTrue(w.segments.filter { $0.windowID == 1 }.isEmpty)
    }

    func testMaximizedWindowHasNoPerch() {
        let w = world([WindowInfo(id: 3, frame: CGRect(x: 0, y: 0, width: 1440, height: 875))])
        XCTAssertTrue(w.segments.filter { $0.windowID == 3 }.isEmpty)
    }

    func testNarrowPiecesAreDropped() {
        let w = world([
            WindowInfo(id: 2, frame: CGRect(x: 150, y: 500, width: 600, height: 200)),
            WindowInfo(id: 1, frame: CGRect(x: 100, y: 200, width: 600, height: 400)),  // only 100..150 left
        ])
        XCTAssertTrue(w.segments.filter { $0.windowID == 1 }.isEmpty)
    }

    func testWindowEdgeClippedToScreen() {
        let w = world([WindowInfo(id: 4, frame: CGRect(x: -200, y: 100, width: 600, height: 300))])
        XCTAssertEqual(w.segments.filter { $0.windowID == 4 },
                       [FloorSegment(kind: .window(id: 4), y: 400, minX: 0, maxX: 400)])
    }
}
