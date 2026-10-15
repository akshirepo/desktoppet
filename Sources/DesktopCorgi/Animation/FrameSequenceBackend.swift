#if canImport(AppKit)
import AppKit
import CorgiCore
import SpriteKit

final class FrameSequenceBackend: AnimationBackend {
    let node = SKNode()
    let size: CGSize
    private let sprite = SKSpriteNode()
    private let scale: CGFloat
    private var animations: [AnimState: (spec: AnimationSpec, frames: [SKTexture])] = [:]
    private var facingRight = true

    init(packURL: URL) throws {
        let manifest = try AnimationManifest.load(from: packURL.appendingPathComponent("manifest.json"))
        var animations: [AnimState: (spec: AnimationSpec, frames: [SKTexture])] = [:]
        for (key, spec) in manifest.states {
            guard let state = AnimState(rawValue: key) else {
                NSLog("DesktopCorgi: manifest has unknown state '\(key)', skipping")
                continue
            }
            let dir = packURL.appendingPathComponent(spec.folder)
            let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "png" }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            let frames = files.compactMap { NSImage(contentsOf: $0) }.map { SKTexture(image: $0) }
            guard !frames.isEmpty else {
                NSLog("DesktopCorgi: no PNG frames in \(dir.path), '\(key)' will use idle")
                continue
            }
            animations[state] = (spec, frames)
        }
        guard let idle = animations[.idle] else { throw AnimationManifestError.missingIdle }
        let missing = AnimState.allCases.filter { animations[$0] == nil }
        if !missing.isEmpty {
            NSLog("DesktopCorgi: pack has no \(missing.map(\.rawValue).joined(separator: ", ")); using idle for those")
        }
        self.animations = animations
        scale = CGFloat(manifest.scale ?? 1)
        let frameSize = idle.frames[0].size()
        size = CGSize(width: frameSize.width * scale, height: frameSize.height * scale)
        sprite.setScale(scale)
        node.addChild(sprite)
        play(.idle)
    }

    func play(_ state: AnimState) {
        guard let entry = animations[state] ?? animations[.idle] else { return }
        sprite.removeAllActions()
        if entry.spec.anchor.count == 2 {
            sprite.anchorPoint = CGPoint(x: entry.spec.anchor[0], y: entry.spec.anchor[1])
        }
        sprite.texture = entry.frames[0]
        sprite.size = entry.frames[0].size()
        sprite.setScale(scale)
        setFacing(right: facingRight)
        let animation = SKAction.animate(with: entry.frames, timePerFrame: 1 / max(entry.spec.fps, 1),
                                         resize: true, restore: false)
        sprite.run(entry.spec.loop ? .repeatForever(animation) : animation)
    }

    /// Pack sprites already include their props (book, headphones, TV, ball).
    var drawsProps: Bool { true }

    func setFacing(right: Bool) {
        facingRight = right
        sprite.xScale = (right ? 1 : -1) * scale
    }
}
#endif
