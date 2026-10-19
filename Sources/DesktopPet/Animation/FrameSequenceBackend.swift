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
                NSLog("DesktopPet: manifest has unknown state '\(key)', skipping")
                continue
            }
            let dir = packURL.appendingPathComponent(spec.folder)
            let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "png" }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            let frames = files.compactMap { NSImage(contentsOf: $0) }.map { SKTexture(image: $0) }
            guard !frames.isEmpty else {
                NSLog("DesktopPet: no PNG frames in \(dir.path), '\(key)' will use idle")
                continue
            }
            animations[state] = (spec, frames)
        }
        guard let idle = animations[.idle] else { throw AnimationManifestError.missingIdle }
        let missing = AnimState.allCases.filter { animations[$0] == nil }
        if !missing.isEmpty {
            NSLog("DesktopPet: pack has no \(missing.map(\.rawValue).joined(separator: ", ")); using idle for those")
        }
        self.animations = animations
        scale = CGFloat(manifest.scale ?? 1)
        let frameSize = idle.frames[0].size()
        size = CGSize(width: frameSize.width * scale, height: frameSize.height * scale)
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
        // SKSpriteNode.size is the on-screen size (it already includes xScale/yScale), so the pack scale is
        // applied here once and the node scale only carries the left/right flip. Frames in a state share one size.
        let t = entry.frames[0].size()
        sprite.yScale = 1
        sprite.xScale = facingRight ? 1 : -1
        sprite.size = CGSize(width: t.width * scale, height: t.height * scale)
        let animation = SKAction.animate(with: entry.frames, timePerFrame: 1 / max(entry.spec.fps, 1),
                                         resize: false, restore: false)
        sprite.run(entry.spec.loop ? .repeatForever(animation) : animation)
    }

    func setFacing(right: Bool) {
        facingRight = right
        sprite.xScale = right ? 1 : -1
    }
}
#endif
