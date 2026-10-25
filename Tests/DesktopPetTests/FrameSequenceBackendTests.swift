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
