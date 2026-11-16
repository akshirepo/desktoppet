import XCTest
@testable import CorgiCore

final class FrameLayoutTests: XCTestCase {
    let canvas = CGSize(width: 420, height: 320)
    let anchor = CGPoint(x: 0.5, y: 0.075)

    func testNoCropKeepsTheCanvasAndItsAnchor() {
        let layout = FrameLayout(canvas: canvas, crop: nil, anchor: anchor)
        XCTAssertEqual(layout.crop, CGRect(x: 0, y: 0, width: 420, height: 320))
        XCTAssertEqual(layout.anchor.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(layout.anchor.y, 0.075, accuracy: 1e-9)
    }

    func testCroppedFrameLandsWhereTheCanvasWould() {
        // Art in a 200x150 box whose top-left is at (100, 150): its bottom edge is 20px above the canvas bottom.
        let layout = FrameLayout(canvas: canvas, crop: [100, 150, 200, 150], anchor: anchor)
        // The feet are at canvas (210, 24 from the bottom): 110px into the crop, 4px above its bottom edge.
        XCTAssertEqual(layout.anchor.x * 200, 110, accuracy: 1e-9)
        XCTAssertEqual(layout.anchor.y * 150, 4, accuracy: 1e-9)
        // Drawn at any scale, the crop covers the same rect it had inside the canvas.
        let k: CGFloat = 0.2971
        let full = FrameLayout.canvasBounds(canvas: canvas, anchor: anchor, scale: k)
        let drawn = CGRect(x: -layout.anchor.x * 200 * k, y: -layout.anchor.y * 150 * k, width: 200 * k, height: 150 * k)
        XCTAssertEqual(drawn.minX, full.minX + 100 * k, accuracy: 1e-9)
        XCTAssertEqual(drawn.minY, full.minY + 20 * k, accuracy: 1e-9)
    }

    func testFeetBelowTheArtGiveANegativeAnchor() {
        // A pose hanging above its feet point (clinging): the crop ends above the anchor.
        let layout = FrameLayout(canvas: canvas, crop: [100, 50, 200, 100], anchor: anchor)
        XCTAssertLessThan(layout.anchor.y, 0)
    }

    func testBadCropFallsBackToTheCanvas() {
        for crop in [[1, 2, 3], [500, 500, 10, 10], [10, 10, 0, 0]] as [[Double]] {
            XCTAssertEqual(FrameLayout(canvas: canvas, crop: crop, anchor: anchor).crop.size, canvas)
        }
        XCTAssertEqual(FrameLayout(canvas: canvas, crop: [400, 300, 100, 100], anchor: anchor).crop,
                       CGRect(x: 400, y: 300, width: 20, height: 20))
    }

    func testCanvasBoundsMatchASpriteShowingTheWholeCanvas() {
        XCTAssertEqual(FrameLayout.canvasBounds(canvas: canvas, anchor: CGPoint(x: 0.5, y: 0), scale: 0.5),
                       CGRect(x: -105, y: 0, width: 210, height: 160))
    }

    func testBudgetDropsTheLeastRecentlyUsedFirst() {
        var budget = FrameBudget<String>(limit: 100)
        XCTAssertEqual(budget.use("idle", bytes: 40), [])
        XCTAssertEqual(budget.use("walk", bytes: 40), [])
        XCTAssertEqual(budget.use("idle", bytes: 40), [])          // idle is now the most recent
        XCTAssertEqual(budget.use("read", bytes: 40), ["walk"])
        XCTAssertEqual(budget.keys, ["idle", "read"])
        XCTAssertEqual(budget.total, 80)
    }

    func testBudgetKeepsPinnedAndTheOneInUse() {
        var budget = FrameBudget<String>(limit: 100)
        budget.pinned = ["idle"]
        _ = budget.use("idle", bytes: 60)
        _ = budget.use("walk", bytes: 30)
        XCTAssertEqual(budget.use("watch", bytes: 500), ["walk"])   // over the limit alone, still kept
        XCTAssertEqual(budget.keys, ["idle", "watch"])
    }
}
