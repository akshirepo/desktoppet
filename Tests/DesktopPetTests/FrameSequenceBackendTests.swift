#if canImport(AppKit)
import AppKit
import Metal
import SpriteKit
import XCTest
import CorgiCore
@testable import DesktopPet

/// Runs SpriteKit actions without opening a window or launching the desktop app.
private final class ActionDriver {
    let renderer: SKRenderer
    let scene = SKScene(size: CGSize(width: 420, height: 320))
    private(set) var time: TimeInterval = 1

    init(node: SKNode) throws {
        renderer = SKRenderer(device: try XCTUnwrap(MTLCreateSystemDefaultDevice()))
        scene.addChild(node)
        renderer.scene = scene
        renderer.update(atTime: time)
    }

    func advance(_ seconds: TimeInterval) {
        let end = time + seconds
        while time < end {
            time = min(end, time + 1.0 / 120)
            renderer.update(atTime: time)
        }
    }
}

final class FrameSequenceBackendTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    func testCurrentPacksPlayOneFullReactionCycleRegardlessOfManifestLoopFlag() throws {
        for packName in ["CorgiPack", "SheepPack"] {
            let pack = root.appendingPathComponent("Assets/Packs/" + packName)
            let manifest = try AnimationManifest.load(from: pack.appendingPathComponent("manifest.json"))
            let backend = try FrameSequenceBackend(packURL: pack)
            let driver = try ActionDriver(node: backend.node)
            for state: AnimState in [.land, .happy, .wiggle, .letGo] {
                let spec = try XCTUnwrap(manifest.states[state.rawValue])
                let files = try FileManager.default.contentsOfDirectory(at: pack.appendingPathComponent(spec.folder),
                                                                          includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension.lowercased() == "png" }
                let expected = Double(files.count) / max(spec.fps, 1)
                var completions = 0
                let duration = try XCTUnwrap(backend.playOnce(state) { completions += 1 },
                                            "\(packName) \(state) needs explicit one-cycle playback")
                XCTAssertEqual(duration, expected, accuracy: 0.000001)
                driver.advance(duration - 1.0 / 30)
                XCTAssertEqual(completions, 0, "\(packName) \(state) must not finish early")
                driver.advance(1.0 / 15)
                XCTAssertEqual(completions, 1, "\(packName) \(state) must finish once")
                let sprite = try XCTUnwrap(backend.node.children.first as? SKSpriteNode)
                let lastFrame = sprite.texture
                driver.advance(duration)
                XCTAssertEqual(completions, 1)
                XCTAssertTrue(sprite.texture === lastFrame, "A finished one-shot keeps its last pose")
            }
        }
    }

    func testReplacingOneShotCancelsItsCompletionAndPreservesNewPlayback() throws {
        let backend = try FrameSequenceBackend(packURL: root.appendingPathComponent("Assets/Packs/CorgiPack"))
        let driver = try ActionDriver(node: backend.node)
        var completions = 0
        _ = try XCTUnwrap(backend.playOnce(.happy) { completions += 1 })
        driver.advance(0.2)
        backend.play(.scared)
        driver.advance(4)
        XCTAssertEqual(completions, 0)
        let sprite = try XCTUnwrap(backend.node.children.first as? SKSpriteNode)
        XCTAssertTrue(sprite.hasActions(), "The replacement's ordinary loop remains active")
    }

    func testMissingOrEmptyReactionUsesOneFiniteIdleCycle() throws {
        let pack = try temporaryPack(fps: 5, emptyReaction: true)
        defer { try? FileManager.default.removeItem(at: pack) }
        let backend = try FrameSequenceBackend(packURL: pack)
        let driver = try ActionDriver(node: backend.node)
        for state: AnimState in [.happy, .land] {
            var completions = 0
            let duration = try XCTUnwrap(backend.playOnce(state) { completions += 1 })
            XCTAssertEqual(duration, 0.2, accuracy: 0.000001)
            driver.advance(0.25)
            XCTAssertEqual(completions, 1)
            driver.advance(0.5)
            XCTAssertEqual(completions, 1)
        }
    }

    func testNonpositiveFPSHasFinitePlaybackAndCompletion() throws {
        for fps in [0.0, -10.0] {
            let pack = try temporaryPack(fps: fps)
            defer { try? FileManager.default.removeItem(at: pack) }
            let backend = try FrameSequenceBackend(packURL: pack)
            let driver = try ActionDriver(node: backend.node)
            var completions = 0
            let duration = try XCTUnwrap(backend.playOnce(.happy) { completions += 1 })
            XCTAssertEqual(duration, 1, accuracy: 0.000001)
            driver.advance(1.05)
            XCTAssertEqual(completions, 1)
        }
    }

    func testPackWithNoDecodableIdleFramesIsRejected() throws {
        let pack = try temporaryPack(fps: 5)
        defer { try? FileManager.default.removeItem(at: pack) }
        try Data("invalid PNG".utf8).write(to: pack.appendingPathComponent("idle/frame1.png"))
        XCTAssertThrowsError(try FrameSequenceBackend(packURL: pack)) { error in
            XCTAssertEqual(error as? AnimationManifestError, .missingIdle)
        }
    }

    /// Frames are kept in memory cut down to the manifest's crop box. Drawn, they must be pixel for pixel where the
    /// full canvas would put them, and the pose must measure the same.
    func testCroppedFramesDrawExactlyLikeTheFullCanvas() throws {
        for packName in ["CorgiPack", "SheepPack"] {
            let pack = root.appendingPathComponent("Assets/Packs/" + packName)
            let uncropped = try packWithoutCrops(pack)
            defer { try? FileManager.default.removeItem(at: uncropped) }
            let manifest = try AnimationManifest.load(from: pack.appendingPathComponent("manifest.json"))
            XCTAssertNotNil(manifest.states["idle"]?.crop, "\(packName) frames should come with a crop box")
            let a = try FrameSequenceBackend(packURL: pack), b = try FrameSequenceBackend(packURL: uncropped)
            for state: AnimState in [.idle, .sleep, .run, .clingHang, .peekEdge, .letGo, .drinkHalf] {
                a.play(state)
                b.play(state)
                a.setFacing(right: state != .run)
                b.setFacing(right: state != .run)
                XCTAssertEqual(a.bounds(for: state), b.bounds(for: state), "\(packName) \(state)")
                XCTAssertTrue(b.spriteBounds.insetBy(dx: -0.01, dy: -0.01).contains(a.spriteBounds), "\(packName) \(state)")
                XCTAssertLessThan(a.spriteBounds.width * a.spriteBounds.height,
                                  b.spriteBounds.width * b.spriteBounds.height * 0.8, "\(packName) \(state) crop saves nothing")
                let x = try render(a.node), y = try render(b.node)
                XCTAssertGreaterThan(x.filter { $0 != 0 }.count, 2000, "\(packName) \(state) drew nothing")
                let worst = zip(x, y).map { abs(Int($0) - Int($1)) }.max() ?? 0
                XCTAssertLessThanOrEqual(worst, 3, "\(packName) \(state) is drawn differently when cropped")
            }
            for name in a.bridgeNames.sorted().prefix(3) {
                XCTAssertNotNil(a.playBridge(name) {}, "\(packName) \(name)")
            }
        }
    }

    /// The node drawn at 2x into an off-screen texture, as RGBA bytes.
    private func render(_ node: SKNode) throws -> [UInt8] {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let parent = node.parent
        node.removeFromParent()
        defer {
            node.removeFromParent()
            parent?.addChild(node)
        }
        let scene = SKScene(size: CGSize(width: 320, height: 260))
        scene.backgroundColor = .clear
        node.position = CGPoint(x: 160, y: 130)
        scene.addChild(node)
        let renderer = SKRenderer(device: device)
        renderer.scene = scene
        renderer.update(atTime: 1)
        let (w, h) = (640, 520)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        let target = try XCTUnwrap(device.makeTexture(descriptor: desc))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        let buffer = try XCTUnwrap(device.makeCommandQueue()?.makeCommandBuffer())
        renderer.render(withViewport: CGRect(x: 0, y: 0, width: w, height: h), commandBuffer: buffer, renderPassDescriptor: pass)
        buffer.commit()
        buffer.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        target.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return bytes
    }

    /// The same pack (frames linked, not copied) with every crop box taken out of its manifest.
    private func packWithoutCrops(_ pack: URL) throws -> URL {
        let fm = FileManager.default
        let destination = fm.temporaryDirectory.appendingPathComponent("desktop-pet-nocrop-test-" + UUID().uuidString)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in try fm.contentsOfDirectory(at: pack, includingPropertiesForKeys: nil) where item.lastPathComponent != "manifest.json" {
            try fm.createSymbolicLink(at: destination.appendingPathComponent(item.lastPathComponent), withDestinationURL: item)
        }
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: pack.appendingPathComponent("manifest.json"))) as? [String: Any])
        for key in ["states", "bridges"] {
            guard var specs = manifest[key] as? [String: [String: Any]] else { continue }
            for name in specs.keys { specs[name]?["crop"] = nil }
            manifest[key] = specs
        }
        try JSONSerialization.data(withJSONObject: manifest).write(to: destination.appendingPathComponent("manifest.json"))
        return destination
    }

    private func temporaryPack(fps: Double, emptyReaction: Bool = false) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("desktop-pet-playback-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: destination.appendingPathComponent("idle"),
                                                withIntermediateDirectories: true)
        let sourcePack = root.appendingPathComponent("Assets/Packs/CorgiPack")
        let sourceManifest = try AnimationManifest.load(from: sourcePack.appendingPathComponent("manifest.json"))
        let sourceIdle = try XCTUnwrap(sourceManifest.states["idle"])
        let png = try XCTUnwrap(FileManager.default.contentsOfDirectory(
            at: sourcePack.appendingPathComponent(sourceIdle.folder), includingPropertiesForKeys: nil)
            .first { $0.pathExtension.lowercased() == "png" })
        try FileManager.default.copyItem(at: png, to: destination.appendingPathComponent("idle/frame1.png"))
        var states: [String: Any] = ["idle": ["folder": "idle", "fps": fps, "loop": true, "anchor": [0.5, 0.075]]]
        if emptyReaction {
            states["land"] = ["folder": "empty", "fps": 100, "loop": true, "anchor": [0.5, 0.075]]
        }
        let data = try JSONSerialization.data(withJSONObject: ["scale": 1, "states": states])
        try data.write(to: destination.appendingPathComponent("manifest.json"))
        return destination
    }
}
#endif
