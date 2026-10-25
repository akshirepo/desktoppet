#if canImport(AppKit)
import XCTest
import AppKit
import SpriteKit
@testable import CorgiCore
@testable import DesktopPet

final class ScreenBoundaryTests: XCTestCase {
    private let bottomDock = CGRect(x: 0, y: 90, width: 1728, height: 994)
    private let packs = ["CorgiPack", "SheepPack"]

    private func backend(_ pack: String) throws -> FrameSequenceBackend {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try FrameSequenceBackend(packURL: root.appendingPathComponent("Assets/Packs/" + pack))
    }

    private final class NoWindows: WindowListProvider {
        func visibleWindows() -> [WindowInfo] { [] }
    }

    // This setup follows the controller's production geometry contract.
    private func world(_ backend: FrameSequenceBackend, screens: [CGRect]) -> World {
        World(provider: NoWindows(), screens: screens, bodyBounds: backend.movementBounds)
    }

    private func clamp(_ body: Body, world: World, backend: FrameSequenceBackend) {
        let areas = body.cling.map { placementRects(world.screens, bounds: backend.bounds(for: $0.animState)) }
            ?? world.movementScreens
        if body.clamp(to: areas) == .startedFalling { body.clamp(to: world.movementScreens) }
    }

    private func hitBounds(_ backend: FrameSequenceBackend) -> CGRect {
        backend.spriteBounds
    }

    private func home(_ backend: FrameSequenceBackend, world: World) -> HomeTracker {
        let home = HomeTracker(clock: SystemClock())
        home.setScreens(world.screens, mainIndex: 0, bodyBounds: world.bodyBounds)
        return home
    }

    private func ball(_ backend: FrameSequenceBackend, world: World) -> Ball {
        let ball = Ball(start: CGPoint(x: 800, y: 300), screens: world.screens)
        ball.setArea(Ball.area(for: world.screens, reachableFrom: world.roamingScreens(headroom: BodyConfig().roamHeadroom)))
        return ball
    }

    private func sprite(_ backend: FrameSequenceBackend) throws -> SKSpriteNode {
        try XCTUnwrap(backend.node.children.compactMap { $0 as? SKSpriteNode }.first)
    }

    private func assertVisible(_ backend: FrameSequenceBackend, body: Body, in screen: CGRect,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let rect = try sprite(backend).frame.offsetBy(dx: body.position.x, dy: body.position.y)
        let epsilon: CGFloat = 0.0001
        XCTAssertGreaterThanOrEqual(rect.minX + epsilon, screen.minX, "left edge", file: file, line: line)
        XCTAssertGreaterThanOrEqual(rect.minY + epsilon, screen.minY, "bottom edge", file: file, line: line)
        XCTAssertLessThanOrEqual(rect.maxX - epsilon, screen.maxX, "right edge", file: file, line: line)
        XCTAssertLessThanOrEqual(rect.maxY - epsilon, screen.maxY, "top edge", file: file, line: line)
    }

    @discardableResult
    private func run(_ body: Body, world: World, backend: FrameSequenceBackend, steps: Int = 120) -> [BodyEvent] {
        var events: [BodyEvent] = []
        for _ in 0..<steps {
            if let event = body.step(dt: 1.0 / 60, world: world) { events.append(event) }
            clamp(body, world: world, backend: backend)
        }
        return events
    }

    func testBothPacksLandEntirelyAboveBottomDock() throws {
        for pack in packs {
            let backend = try backend(pack)
            let world = world(backend, screens: [bottomDock])
            let body = Body(position: CGPoint(x: 864, y: 500))
            XCTAssertTrue(run(body, world: world, backend: backend).contains(.landed))
            XCTAssertEqual(body.mode, .grounded)
            try assertVisible(backend, body: body, in: bottomDock)
        }
    }

    func testWalkingReachesAnActualEdgeBeforeOverlappingEitherSideDock() throws {
        for pack in packs {
            for right in [false, true] {
                let backend = try backend(pack)
                let screen = right ? CGRect(x: 0, y: 0, width: 1638, height: 1084)
                    : CGRect(x: 90, y: 0, width: 1638, height: 1084)
                let world = world(backend, screens: [screen])
                let body = Body(position: CGPoint(x: right ? 1500 : 220, y: 200))
                run(body, world: world, backend: backend)
                body.walk(direction: right ? 1 : -1, speed: 240)
                backend.play(.run)
                backend.setFacing(right: right)
                let events = run(body, world: world, backend: backend)
                XCTAssertEqual(events, [.hitEdge])
                XCTAssertEqual(body.mode, .grounded)
                XCTAssertFalse(body.isMoving)
                try assertVisible(backend, body: body, in: screen)
            }
        }
    }

    func testRoamingDoesNotCutOffTheHeadAtTheMenuBar() throws {
        for pack in packs {
            let backend = try backend(pack)
            let world = world(backend, screens: [bottomDock])
            let body = Body(position: CGPoint(x: 864, y: 800))
            body.startRoaming()
            body.roam(toward: CGPoint(x: 864, y: 2000), speed: 400)
            XCTAssertTrue(run(body, world: world, backend: backend).contains(.hitEdge))
            XCTAssertEqual(body.mode, .roaming)
            try assertVisible(backend, body: body, in: bottomDock)
        }
    }

    func testNormalPoseChangesKeepOneStableFootPositionAboveDock() throws {
        for pack in packs {
            let backend = try backend(pack)
            let world = world(backend, screens: [bottomDock])
            let body = Body(position: CGPoint(x: 864, y: 500))
            run(body, world: world, backend: backend)
            let planted = body.position
            for state: AnimState in [.idle, .land, .run, .happy, .wiggle, .letGo, .drink] {
                for right in [false, true] {
                    backend.play(state)
                    backend.setFacing(right: right)
                    clamp(body, world: world, backend: backend)
                    XCTAssertEqual(body.position, planted, "Changing an animation must not move the feet")
                    try assertVisible(backend, body: body, in: bottomDock)
                }
            }
        }
    }

    func testHeldBodyUsesTheNearestStackedScreenWithoutDropping() throws {
        for pack in packs {
            let backend = try backend(pack)
            let lower = CGRect(x: -800, y: -600, width: 1200, height: 700)
            let upper = CGRect(x: -800, y: 200, width: 1200, height: 900)
            let world = world(backend, screens: [lower, upper])
            let body = Body(position: CGPoint(x: -500, y: 2100))
            body.pickUp()
            clamp(body, world: world, backend: backend)
            XCTAssertEqual(body.mode, .held)
            XCTAssertGreaterThan(body.position.y, upper.minY)
            try assertVisible(backend, body: body, in: upper)
            world.setScreens([lower])
            clamp(body, world: world, backend: backend)
            XCTAssertEqual(body.mode, .held)
            try assertVisible(backend, body: body, in: lower)
        }
    }

    func testDockGrowthAndMovingSidesRecoverThePet() throws {
        for pack in packs {
            let backend = try backend(pack)
            let hiddenDock = CGRect(x: 0, y: 2, width: 1728, height: 1082)
            let world = world(backend, screens: [hiddenDock])
            let body = Body(position: CGPoint(x: 65, y: 200))
            run(body, world: world, backend: backend)
            world.setScreens([bottomDock])
            clamp(body, world: world, backend: backend)
            run(body, world: world, backend: backend)
            try assertVisible(backend, body: body, in: bottomDock)
            let leftDock = CGRect(x: 120, y: 0, width: 1608, height: 1084)
            world.setScreens([leftDock])
            clamp(body, world: world, backend: backend)
            run(body, world: world, backend: backend)
            XCTAssertEqual(body.mode, .grounded)
            try assertVisible(backend, body: body, in: leftDock)
        }
    }

    func testUnsafeClingReleasesInsteadOfMovingAnAttachedGrip() throws {
        for pack in packs {
            let backend = try backend(pack)
            backend.play(.clingHang)
            let world = world(backend, screens: [bottomDock])
            let body = Body(position: CGPoint(x: 500, y: 80))
            body.startClinging(ClingSpot(windowID: 1, edge: .bottom, along: 0.5, above: false), at: body.position)
            clamp(body, world: world, backend: backend)
            XCTAssertEqual(body.mode, .airborne)
            XCTAssertNil(body.cling)
            backend.play(.fall)
            try assertVisible(backend, body: body, in: bottomDock)
        }
    }

    func testSafeClingPreservesItsExactWindowContact() throws {
        for pack in packs {
            let backend = try backend(pack)
            let world = world(backend, screens: [bottomDock])
            for edge: ClingEdge in [.left, .right, .top, .bottom] {
                let contact = CGPoint(x: 500, y: 500)
                let body = Body(position: contact)
                let spot = ClingSpot(windowID: 1, edge: edge, along: 0.5, above: false)
                backend.play(spot.animState)
                body.startClinging(spot, at: contact)
                clamp(body, world: world, backend: backend)
                XCTAssertEqual(body.mode, .clinging)
                XCTAssertEqual(body.position, contact)
                XCTAssertEqual(body.cling, spot)
                try assertVisible(backend, body: body, in: bottomDock)
            }
        }
    }

    func testHomeKeepsItsExistingCornerPaddingAndRemainsReachable() throws {
        for pack in packs {
            let backend = try backend(pack)
            let world = world(backend, screens: [bottomDock])
            let home = home(backend, world: world)
            let target = try XCTUnwrap(home.spot)
            XCTAssertEqual(target.x, bottomDock.maxX - home.config.insetFromRight)
            let body = Body(position: target)
            run(body, world: world, backend: backend)
            XCTAssertTrue(home.isHome(body.position))
            XCTAssertEqual(body.mode, .grounded)
            try assertVisible(backend, body: body, in: bottomDock)
        }
    }

    func testEveryBallAreaCornerCanBeReachedByThePetsMouth() throws {
        for pack in packs {
            let backend = try backend(pack)
            let world = world(backend, screens: [bottomDock])
            let ball = ball(backend, world: world)
            XCTAssertFalse(ball.area.isEmpty)
            for area in ball.area {
                for x in [area.minX, area.maxX] {
                    for y in [area.minY, area.maxY] {
                        let body = Body(position: CGPoint(x: x, y: y - 30))
                        body.startRoaming()
                        let requested = body.position
                        clamp(body, world: world, backend: backend)
                        XCTAssertEqual(body.position, requested, "Ball mouth target must already be reachable")
                        try assertVisible(backend, body: body, in: bottomDock)
                    }
                }
            }
        }
    }

    func testHitBoundsFollowTheSpriteAnchorAndFacingWithoutIncludingEffects() throws {
        for pack in packs {
            let backend = try backend(pack)
            let effect = SKSpriteNode(color: .red, size: CGSize(width: 500, height: 500))
            effect.position = CGPoint(x: 200, y: 800)
            backend.node.addChild(effect)
            for state: AnimState in [.idle, .clingHang, .clingPeek, .clingLeft, .clingRight, .letGo] {
                for right in [false, true] {
                    backend.play(state)
                    backend.setFacing(right: right)
                    let expected = try sprite(backend).frame
                    XCTAssertEqual(hitBounds(backend), expected, "Exact sprite-only hit area")
                }
            }
        }
    }
}
#endif
