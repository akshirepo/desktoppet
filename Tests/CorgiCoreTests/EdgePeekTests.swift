import XCTest
@testable import CorgiCore

final class EdgePeekTests: XCTestCase {
    let laptop = CGRect(x: 0, y: 0, width: 1440, height: 875)
    /// The pack canvas: 420x320 at scale 0.2971 with the idle anchor (0.5, 0.075).
    let canvas = CGRect(x: -62.391, y: -7.1304, width: 124.782, height: 95.072)

    /// Floors sit where the canvas bottom touches the screen bottom.
    var floorY: CGFloat { -canvas.minY }

    func world(_ screens: [CGRect], windows: [WindowInfo] = []) -> World {
        let provider = FakeWindows()
        provider.windows = windows
        let w = World(provider: provider, screens: screens, bodyBounds: canvas)
        w.refresh()
        return w
    }

    func find(_ p: CGPoint, in w: World, scale: CGFloat = 1) -> EdgePeek? {
        EdgePeekFinder.find(feet: p, screens: w.screens, seams: w.seams, floors: w.segments, bounds: canvas, scale: scale)
    }

    // MARK: finding a spot

    func testDroppedNearTheLeftEdgeOnTheFloorPeeksFromTheFloor() throws {
        let w = world([laptop])
        let spot = try XCTUnwrap(find(CGPoint(x: 70, y: 30), in: w))
        XCTAssertEqual(spot.side, .left)
        XCTAssertEqual(spot.kind, .floor)
        XCTAssertEqual(spot.animState, .peekEdge)
        XCTAssertTrue(spot.facingRight)
        XCTAssertEqual(spot.y, floorY)
        // Canvas column 0 sits exactly on the screen edge.
        XCTAssertEqual(spot.feetX(bounds: canvas) + canvas.minX, 0, accuracy: 1e-9)
        // It walks to the end of the floor, which is where the feet go anyway at full scale.
        XCTAssertEqual(try XCTUnwrap(spot.standX(bounds: canvas)), spot.feetX(bounds: canvas), accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(spot.floorEnd), spot.feetX(bounds: canvas), accuracy: 1e-9)
    }

    func testRightEdgeIsMirrored() throws {
        let w = world([laptop])
        let spot = try XCTUnwrap(find(CGPoint(x: 1440 - 70, y: 20), in: w))
        XCTAssertEqual(spot.side, .right)
        XCTAssertFalse(spot.facingRight)
        // Mirrored, column 0 lands on the right edge.
        XCTAssertEqual(spot.feetX(bounds: canvas) - canvas.minX, 1440, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(spot.floorEnd), 1440 + canvas.minX, accuracy: 1e-9)
    }

    func testHigherUpItHoldsOnAtThatHeight() throws {
        let w = world([laptop])
        let spot = try XCTUnwrap(find(CGPoint(x: 100, y: 400), in: w))
        XCTAssertEqual(spot.kind, .hold)
        XCTAssertEqual(spot.animState, .holdEdge)
        XCTAssertEqual(spot.y, 400)
        XCTAssertNil(spot.floor)
        XCTAssertNil(spot.floorEnd)
        XCTAssertNil(spot.standX(bounds: canvas))
    }

    func testHoldStaysBelowTheTopOfTheScreen() throws {
        let w = world([laptop])
        let spot = try XCTUnwrap(find(CGPoint(x: 70, y: 870), in: w))
        XCTAssertEqual(spot.y + canvas.maxY, 875, accuracy: 1e-9)
    }

    func testFarFromTheEdgesThereIsNoPeek() {
        let w = world([laptop])
        XCTAssertNil(find(CGPoint(x: 720, y: 0), in: w))
        // More than one sprite width from the peek spot.
        XCTAssertNil(find(CGPoint(x: 62.4 + 130, y: 0), in: w))
        XCTAssertNotNil(find(CGPoint(x: 62.4 + 120, y: 0), in: w))
    }

    func testNoPeekAtASeamBetweenSideBySideDisplays() throws {
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let w = world([laptop, right])
        XCTAssertNil(find(CGPoint(x: 1440 - 70, y: 20), in: w))
        XCTAssertNil(find(CGPoint(x: 1440 + 70, y: 20), in: w))
        // The outer edges still work.
        XCTAssertEqual(try XCTUnwrap(find(CGPoint(x: 70, y: 0), in: w)).side, .left)
        XCTAssertEqual(try XCTUnwrap(find(CGPoint(x: 3360 - 70, y: 0), in: w)).side, .right)
        XCTAssertEqual(try XCTUnwrap(find(CGPoint(x: 3360 - 70, y: 0), in: w)).screen, 1)
    }

    func testAboveTheShorterDisplayTheTallerOnesEdgeIsReal() throws {
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let w = world([laptop, right])
        // The laptop ends at 875; above that nothing continues past x = 1440.
        let spot = try XCTUnwrap(find(CGPoint(x: 1440 + 70, y: 950), in: w))
        XCTAssertEqual(spot.side, .left)
        XCTAssertEqual(spot.screen, 1)
        XCTAssertEqual(spot.kind, .hold)
    }

    func testLaptopBelowTwoMonitors() throws {
        // The user's desk: two monitors side by side on top, the laptop centred below them.
        let left = CGRect(x: -1200, y: 875, width: 2560, height: 1415)
        let right = CGRect(x: 1360, y: 875, width: 2560, height: 1415)
        let w = world([laptop, left, right])
        XCTAssertEqual(w.seams.count, 1)
        // Laptop edges are real edges (the monitors are above, not beside it).
        XCTAssertEqual(try XCTUnwrap(find(CGPoint(x: 70, y: 0), in: w)).screen, 0)
        XCTAssertEqual(try XCTUnwrap(find(CGPoint(x: 1440 - 70, y: 300), in: w)).kind, .hold)
        // The monitors' shared edge is a seam; their outer edges are not.
        XCTAssertNil(find(CGPoint(x: 1360 - 70, y: 900), in: w))
        XCTAssertNil(find(CGPoint(x: 1360 + 70, y: 900), in: w))
        let outer = try XCTUnwrap(find(CGPoint(x: -1200 + 70, y: 900), in: w))
        XCTAssertEqual(outer.screen, 1)
        XCTAssertEqual(outer.kind, .floor)
        XCTAssertEqual(outer.y, 875 + floorY)
    }

    func testSmallerDrawScaleKeepsColumnZeroOnTheEdge() throws {
        let w = world([laptop])
        let spot = try XCTUnwrap(find(CGPoint(x: 70, y: 20), in: w, scale: 0.86))
        XCTAssertEqual(spot.kind, .floor)
        XCTAssertEqual(spot.feetX(bounds: canvas, scale: 0.86) + canvas.minX * 0.86, 0, accuracy: 1e-9)
        // The floor still ends where an unscaled pet stands: it walks there and the body glides the rest.
        XCTAssertEqual(try XCTUnwrap(spot.floorEnd), -canvas.minX, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(spot.standX(bounds: canvas, scale: 0.86)), -canvas.minX, accuracy: 1e-9)
    }

    func testWindowTopThatDoesNotReachTheEdgeMeansHolding() throws {
        let w = world([laptop], windows: [WindowInfo(id: 1, frame: CGRect(x: 300, y: 0, width: 600, height: 300))])
        // Just above the window top but beside the edge: that floor doesn't run to the edge.
        let spot = try XCTUnwrap(find(CGPoint(x: 100, y: 300), in: w))
        XCTAssertEqual(spot.kind, .hold)
    }

    func testWindowTopRunningToTheEdgeIsAFloor() throws {
        let w = world([laptop], windows: [WindowInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 600, height: 300))])
        let spot = try XCTUnwrap(find(CGPoint(x: 80, y: 330), in: w))
        XCTAssertEqual(spot.kind, .floor)
        XCTAssertEqual(spot.y, 300)
        XCTAssertEqual(try XCTUnwrap(spot.floorEnd), -canvas.minX, accuracy: 1e-9)
        XCTAssertEqual(spot.floor?.windowID, 1)
    }

    // MARK: session

    func testFloorSessionWalksThenPeeksThenLeaves() {
        let spot = EdgePeek(screen: 0, side: .left, kind: .floor, edgeX: 0, y: 0,
                            floor: FloorSegment(kind: .ground(screen: 0), y: 0, minX: 62, maxX: 1378))
        var s = EdgePeekSession(spot: spot, stay: 120)
        XCTAssertEqual(s.phase, .approaching)
        XCTAssertNil(s.animState)
        XCTAssertFalse(s.update(dt: 5))
        XCTAssertEqual(s.phase, .approaching, "the stay clock doesn't run on the way to the edge")
        s.arrived()
        XCTAssertEqual(s.animState, .peekEdge)
        s.update(dt: 119)
        XCTAssertEqual(s.phase, .peeking)
        XCTAssertFalse(s.isOut(currentState: .peekEdge, transitionTarget: nil))
        s.update(dt: 2)
        XCTAssertEqual(s.phase, .leaving)
        XCTAssertEqual(s.animState, .idle)
        XCTAssertFalse(s.isOut(currentState: .idle, transitionTarget: .idle), "exit art still playing")
        XCTAssertTrue(s.isOut(currentState: .idle, transitionTarget: nil))
    }

    func testHoldSessionStartsHiddenAndEndsInTheDropPose() {
        var s = EdgePeekSession(spot: EdgePeek(screen: 0, side: .right, kind: .hold, edgeX: 1440, y: 400), stay: 10)
        XCTAssertEqual(s.phase, .peeking)
        XCTAssertEqual(s.animState, .holdEdge)
        s.leave()
        XCTAssertEqual(s.animState, .scared)
        XCTAssertTrue(s.isOut(currentState: .scared, transitionTarget: nil))
    }

    func testApproachGivesUpAfterTimeout() {
        let spot = EdgePeek(screen: 0, side: .left, kind: .floor, edgeX: 0, y: 0,
                            floor: FloorSegment(kind: .ground(screen: 0), y: 0, minX: 62, maxX: 1378))
        var s = EdgePeekSession(spot: spot, stay: 120)
        XCTAssertFalse(s.update(dt: EdgePeekSession.approachTimeout - 1))
        XCTAssertTrue(s.update(dt: 2))
    }

    func testStayIsAFewMinutes() {
        XCTAssertEqual(EdgePeekSession.stay.lowerBound, 120)
        XCTAssertEqual(EdgePeekSession.stay.upperBound, 300)
    }

    // MARK: body

    func testPeekingHasNoGravityAndGlidesOntoTheSpot() {
        let w = world([laptop])
        let body = Body(position: CGPoint(x: 120, y: 400))
        body.startPeeking(at: CGPoint(x: 53.7, y: 400), facingRight: true)
        XCTAssertEqual(body.mode, .peeking)
        XCTAssertTrue(body.facingRight)
        XCTAssertFalse(body.isMoving)
        for _ in 0..<30 { XCTAssertNil(body.step(dt: 1.0 / 30, world: w)) }
        XCTAssertEqual(body.position, CGPoint(x: 53.7, y: 400))
        body.movePeek(to: CGPoint(x: 60, y: 400))
        body.step(dt: 0.1, world: w)
        XCTAssertEqual(body.position.x, 60)
    }

    func testStopPeekingOntoTheFloorStandsOnIt() throws {
        let w = world([laptop])
        let floor = try XCTUnwrap(w.segment(under: CGPoint(x: 100, y: floorY)))
        let body = Body(position: CGPoint(x: 100, y: floorY))
        body.step(dt: 0.01, world: w)
        body.startPeeking(at: CGPoint(x: 53.7, y: floorY), facingRight: true)
        body.step(dt: 1, world: w)
        XCTAssertNil(body.stopPeeking(onto: floor))
        XCTAssertEqual(body.mode, .grounded)
        XCTAssertEqual(body.position.x, floor.minX)
        XCTAssertNil(body.step(dt: 0.1, world: w), "no fall, no landing bounce")
    }

    func testStopPeekingWithoutAFloorDrops() {
        let body = Body(position: CGPoint(x: 60, y: 400))
        body.startPeeking(at: CGPoint(x: 60, y: 400), facingRight: true)
        XCTAssertEqual(body.stopPeeking(onto: nil), .startedFalling)
        XCTAssertEqual(body.mode, .airborne)
    }

    func testPickingUpEndsThePeek() {
        let body = Body(position: CGPoint(x: 60, y: 400))
        body.startPeeking(at: CGPoint(x: 60, y: 400), facingRight: true)
        body.pickUp()
        XCTAssertEqual(body.mode, .held)
        XCTAssertNil(body.peekTarget)
    }

    func testPeekBehaviorWalksUpToTheSpotByTheWall() throws {
        let w = world([laptop])
        let body = Body(position: CGPoint(x: 150, y: floorY))
        body.step(dt: 0.01, world: w)
        let exec = BehaviorExecutor(rng: SeededRandom(seed: 1))
        let end = try XCTUnwrap(w.segment(under: body.position)).minX + 9
        exec.peekStandX = end
        exec.begin(.peek, body: body, world: w, cursor: .zero)
        for _ in 0..<200 {
            XCTAssertFalse(exec.step(.peek, body: body, world: w, cursor: .zero))
            if let e = body.step(dt: 1.0 / 30, world: w) { _ = exec.handle(e, behavior: .peek, body: body) }
        }
        XCTAssertEqual(body.position.x, end, accuracy: 1, "stops on the spot, the glide does the last point")
        XCTAssertFalse(body.isMoving)
    }

    // MARK: wall

    /// The pack wall: 44 px wide, inner face on frame column 16, top 272 px above the feet.
    let wall = EdgeWallSpec(folder: "edgeWall", width: 44, height: 272, faceColumn: 16)
    let packScale = 0.2971

    func testWithAWallTheFaceColumnSitsOnTheWallsInnerFace() throws {
        let w = world([laptop])
        let inset = wall.inset(packScale: packScale)
        XCTAssertEqual(inset, 28 * 0.2971, accuracy: 1e-9)
        let spot = try XCTUnwrap(EdgePeekFinder.find(feet: CGPoint(x: 80, y: 20), screens: w.screens, seams: w.seams,
                                                     floors: w.segments, bounds: canvas, inset: inset))
        XCTAssertEqual(spot.kind, .floor)
        XCTAssertEqual(spot.inset, inset)
        let column0 = spot.feetX(bounds: canvas) + canvas.minX
        XCTAssertEqual(column0 + 16 * 0.2971, 44 * 0.2971, accuracy: 1e-9, "face column on the inner face")
        // It walks right up to that spot: inside the floor, so coming out needs no snap.
        XCTAssertEqual(try XCTUnwrap(spot.standX(bounds: canvas)), spot.feetX(bounds: canvas), accuracy: 1e-9)
        XCTAssertGreaterThan(spot.feetX(bounds: canvas), try XCTUnwrap(spot.floorEnd))
    }

    func testWallMirrorsAtTheRightEdgeAndScales() throws {
        let w = world([laptop])
        let inset = wall.inset(packScale: packScale)
        let spot = try XCTUnwrap(EdgePeekFinder.find(feet: CGPoint(x: 1360, y: 20), screens: w.screens, seams: w.seams,
                                                     floors: w.segments, bounds: canvas, scale: 0.86, inset: inset))
        XCTAssertEqual(spot.side, .right)
        XCTAssertEqual(spot.feetX(bounds: canvas, scale: 0.86) - canvas.minX * 0.86, 1440 - inset * 0.86, accuracy: 1e-9)
        let f = spot.wallFrame(width: CGFloat(wall.width * packScale), height: CGFloat(wall.height * packScale),
                               scale: 0.86, groundY: floorY)
        XCTAssertEqual(f.maxX, 1440, accuracy: 1e-9)
        XCTAssertEqual(f.width, 44 * 0.2971 * 0.86, accuracy: 1e-9)
        XCTAssertEqual(f.minY, floorY, accuracy: 1e-9)
        XCTAssertEqual(f.maxY, floorY + 272 * 0.2971 * 0.86, accuracy: 1e-9)
    }

    func testHoldWallIsAShortSectionAroundTheGrip() throws {
        let spot = EdgePeek(screen: 0, side: .left, kind: .hold, edgeX: 0, y: 400, inset: 8)
        let f = spot.wallFrame(width: 13, height: 80, scale: 0.86, holdDepth: 1.2, groundY: floorY)
        XCTAssertEqual(f.minX, 0)
        XCTAssertEqual(f.width, 13 * 0.86, accuracy: 1e-9)
        XCTAssertEqual(f.minY, 400 - 1.2 * 0.86, accuracy: 1e-9, "just below the feet, not down to the floor")
        XCTAssertEqual(f.maxY, 400 + 80 * 0.86, accuracy: 1e-9)
        // Without a depth the old behaviour stays: a wall from the display's floor.
        let tall = spot.wallFrame(width: 13, height: 80, groundY: floorY)
        XCTAssertEqual(tall.minY, floorY)
        XCTAssertEqual(tall.maxY, 480)
    }

    func testFloorWallIgnoresTheHoldDepth() {
        let spot = EdgePeek(screen: 0, side: .left, kind: .floor, edgeX: 0, y: floorY)
        XCTAssertEqual(spot.wallFrame(width: 13, height: 77, holdDepth: 1.2, groundY: 0).minY, floorY)
    }

    func testManifestReadsTheWall() throws {
        let json = #"""
        {"states": {"idle": {"folder": "idle", "fps": 4, "loop": true, "anchor": [0.5, 0.075]}},
         "edgeWall": {"folder": "edgeWall", "width": 44, "height": 272, "faceColumn": 16, "holdDepth": 4}}
        """#
        let m = try JSONDecoder().decode(AnimationManifest.self, from: Data(json.utf8))
        XCTAssertEqual(m.edgeWall, EdgeWallSpec(folder: "edgeWall", width: 44, height: 272, faceColumn: 16, holdDepth: 4))
        let old = try JSONDecoder().decode(AnimationManifest.self, from: Data(#"{"states": {}}"#.utf8))
        XCTAssertNil(old.edgeWall)
    }

    // MARK: packs

    func testBothPacksHaveTheEdgeArtWithTheIdleAnchor() throws {
        let packs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Assets/Packs")
        for pack in ["CorgiPack", "SheepPack"] {
            let dir = packs.appendingPathComponent(pack)
            let m = try AnimationManifest.load(from: dir.appendingPathComponent("manifest.json"))
            let idle = try XCTUnwrap(m.states["idle"])
            // The wall to hide behind: cap and tile, and a face column inside the wall.
            let wall = try XCTUnwrap(m.edgeWall, pack)
            XCTAssertGreaterThan(wall.width, wall.faceColumn)
            XCTAssertGreaterThan(wall.faceColumn, 0)
            for f in ["cap.png", "tile.png"] {
                XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(wall.folder)
                    .appendingPathComponent(f).path), "\(pack) \(f)")
            }
            for state in [AnimState.peekEdge, .holdEdge] {
                let spec = try XCTUnwrap(m.states[state.rawValue], "\(pack) \(state)")
                // Same anchor as idle: canvas column 0 is the edge and the exit ends on the idle frame in place.
                XCTAssertEqual(spec.anchor, idle.anchor, "\(pack) \(state)")
                XCTAssertTrue(spec.loop)
                XCTAssertNil(spec.scale)
                XCTAssertTrue(m.available.contains(state))
                for name in [Bridge.enter(state), Bridge.exit(state)] {
                    let b = try XCTUnwrap(m.bridges?[name], "\(pack) \(name)")
                    XCTAssertEqual(b.anchor, idle.anchor)
                    XCTAssertFalse(b.loop)
                    let files = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent(b.folder).path)
                    XCTAssertGreaterThan(files.filter { $0.hasSuffix(".png") }.count, 8, "\(pack) \(name)")
                }
                XCTAssertEqual(m.bridges?[Bridge.exit(state)]?.reversed, true)
                let frames = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent(spec.folder).path)
                XCTAssertGreaterThanOrEqual(frames.filter { $0.hasSuffix(".png") }.count, 12, "\(pack) \(state)")
            }
        }
    }
}
