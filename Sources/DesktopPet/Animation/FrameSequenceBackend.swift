#if canImport(AppKit)
import AppKit
import CorgiCore
import SpriteKit

final class FrameSequenceBackend: AnimationBackend {
    let node = SKNode()
    let size: CGSize
    private(set) var movementBounds: CGRect = .zero
    var spriteBounds: CGRect { sprite.frame }
    private var poseBounds: [AnimState: CGRect] = [:]
    private let sprite = SKSpriteNode()
    private let scale: CGFloat
    private var animations: [AnimState: (spec: AnimationSpec, frames: [SKTexture])] = [:]
    /// Named one-shot transitions ("stand>sit", "enter:watch", ...), preloaded like the loops.
    private var bridgeAnims: [String: (spec: AnimationSpec, frames: [SKTexture])] = [:]
    var bridgeNames: Set<String> { Set(bridgeAnims.keys) }
    private var facingRight = true
    private var playbackID: UInt64 = 0
    /// Postures for this pet, with the pack's overrides.
    let postures: [AnimState: Posture]
    /// States the pack has art for, so transitions only use bridges that exist.
    let available: Set<AnimState>
    /// Pairs the pack draws in the same view, switched without going through the hub.
    let directPairs: Set<[AnimState]>
    /// When the current loop started and how long one cycle is, for finishing a step or bite.
    private var loopStart: CFTimeInterval = 0
    private var loopCycle: TimeInterval = 0
    private var loopState: AnimState?
    private var loopFrameCount: Int?

    init(packURL: URL) throws {
        let manifest = try AnimationManifest.load(from: packURL.appendingPathComponent("manifest.json"))
        var animations: [AnimState: (spec: AnimationSpec, frames: [SKTexture])] = [:]
        for (key, spec) in manifest.states {
            guard let state = AnimState(rawValue: key) else {
                NSLog("DesktopPet: manifest has unknown state '\(key)', skipping")
                continue
            }
            guard let frames = Self.loadFrames(packURL, spec) else {
                NSLog("DesktopPet: no PNG frames in \(spec.folder), '\(key)' will use idle")
                continue
            }
            animations[state] = (spec, frames)
        }
        var bridgeAnims: [String: (spec: AnimationSpec, frames: [SKTexture])] = [:]
        for (name, spec) in manifest.bridges ?? [:] {
            if let frames = Self.loadFrames(packURL, spec) { bridgeAnims[name] = (spec, frames) }
            else { NSLog("DesktopPet: no PNG frames for bridge '\(name)', skipping") }
        }
        self.bridgeAnims = bridgeAnims
        guard let idle = animations[.idle] else { throw AnimationManifestError.missingIdle }
        let missing = AnimState.allCases.filter { animations[$0] == nil }
        if !missing.isEmpty {
            NSLog("DesktopPet: pack has no \(missing.map(\.rawValue).joined(separator: ", ")); using idle for those")
        }
        self.animations = animations
        scale = CGFloat(manifest.scale ?? 1)
        postures = manifest.postures
        available = manifest.available
        directPairs = manifest.directPairs
        let frameSize = idle.frames[0].size()
        size = CGSize(width: frameSize.width * scale, height: frameSize.height * scale)
        let grips: Set<AnimState> = [.clingSit, .clingHang, .clingPeek, .clingLeft, .clingRight]
        for (state, entry) in animations {
            // Measure with SpriteKit's own canvas precision; no alpha trimming or per-frame offsets.
            let measurement = SKSpriteNode(texture: entry.frames[0])
            let frame = entry.frames[0].size()
            measurement.size = CGSize(width: frame.width * scale, height: frame.height * scale)
            measurement.anchorPoint = Self.anchor(entry.spec)
            let bounds = measurement.frame
            poseBounds[state] = bounds
            if !grips.contains(state) {
                let mirrored = CGRect(x: -bounds.maxX, y: bounds.minY, width: bounds.width, height: bounds.height)
                movementBounds = movementBounds.union(bounds).union(mirrored)
            }
        }
        node.addChild(sprite)
        play(.idle)
    }

    private static func anchor(_ spec: AnimationSpec) -> CGPoint {
        spec.anchor.count == 2 ? CGPoint(x: spec.anchor[0], y: spec.anchor[1]) : CGPoint(x: 0.5, y: 0.5)
    }

    func bounds(for state: AnimState) -> CGRect {
        poseBounds[state] ?? poseBounds[.idle] ?? .zero
    }

    func play(_ state: AnimState) {
        _ = start(state, once: false, completion: nil)
    }

    func playOnce(_ state: AnimState, completion: @escaping () -> Void) -> TimeInterval? {
        start(state, once: true, completion: completion)
    }

    func playBridge(_ name: String, completion: @escaping () -> Void) -> TimeInterval? {
        guard let entry = bridgeAnims[name] else { return nil }
        return start(entry, state: nil, once: true, completion: completion)
    }

    private static func loadFrames(_ packURL: URL, _ spec: AnimationSpec) -> [SKTexture]? {
        let dir = packURL.appendingPathComponent(spec.folder)
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var frames = files.compactMap { NSImage(contentsOf: $0) }.map { SKTexture(image: $0) }
        if spec.reversed == true { frames.reverse() }
        return frames.isEmpty ? nil : frames
    }

    private func start(_ state: AnimState, once: Bool, completion: (() -> Void)?) -> TimeInterval? {
        guard let entry = animations[state] ?? animations[state.base] ?? animations[.idle] else { return nil }
        // Swapping bowl versions of the same loop carries on from the same frame instead of restarting.
        var phase = 0
        if !once, let cur = loopState, cur != state, cur.base == state.base, loopCycle > 0,
           let curCount = loopFrameCount, curCount == entry.frames.count {
            let fps = entry.spec.fps.isFinite ? max(entry.spec.fps, 1) : 1
            phase = Int(((CACurrentMediaTime() - loopStart) * fps).rounded(.down)) % curCount
        }
        return start(entry, state: state, once: once, completion: completion, phase: phase)
    }

    private func start(_ entry: (spec: AnimationSpec, frames: [SKTexture]), state: AnimState?, once: Bool,
                       completion: (() -> Void)?, phase: Int = 0) -> TimeInterval? {
        let fps = entry.spec.fps.isFinite ? max(entry.spec.fps, 1) : 1
        let frameDuration = 1 / fps
        let duration = Double(entry.frames.count) * frameDuration
        guard duration.isFinite, duration > 0 else { return nil }
        playbackID &+= 1
        let id = playbackID
        sprite.removeAllActions()
        sprite.anchorPoint = Self.anchor(entry.spec)
        let frames = phase > 0 ? Array(entry.frames[phase...] + entry.frames[..<phase]) : entry.frames
        sprite.texture = frames[0]
        // SKSpriteNode.size is the on-screen size (it already includes xScale/yScale), so the pack scale is
        // applied here once and the node scale only carries the left/right flip. Frames in a state share one size.
        let t = entry.frames[0].size()
        sprite.yScale = 1
        sprite.xScale = facingRight ? 1 : -1
        sprite.size = CGSize(width: t.width * scale, height: t.height * scale)
        // Keep the last displayed pose on completion/cancellation; do not restore an older texture.
        let animation = SKAction.animate(with: frames, timePerFrame: frameDuration,
                                         resize: false, restore: false)
        if once {
            sprite.run(.sequence([animation, .run { [weak self] in
                guard self?.playbackID == id else { return }
                completion?()
            }]), withKey: "frames")
        } else {
            sprite.run(entry.spec.loop ? .repeatForever(animation) : animation, withKey: "frames")
            loopStart = CACurrentMediaTime() - Double(phase) * frameDuration
            loopCycle = entry.spec.loop ? duration : 0
            loopState = state
            loopFrameCount = entry.frames.count
        }
        if once { loopState = nil; loopFrameCount = nil }
        if state?.base == .drink && !once {
            // Lapping head-bob: the drinking frames only move the tongue and ripples.
            let lap = SKAction.sequence([.scaleY(to: 0.95, duration: 0.12), .scaleY(to: 1, duration: 0.14), .wait(forDuration: 0.12)])
            sprite.run(.repeatForever(lap))
        }
        return duration
    }

    func timeToCycleBoundary(parts: Int) -> TimeInterval? {
        guard loopCycle > 0, parts > 0 else { return nil }
        let part = loopCycle / Double(parts)
        let left = part - (CACurrentMediaTime() - loopStart).truncatingRemainder(dividingBy: part)
        return left < 0.02 ? 0 : left
    }

    func setFacing(right: Bool) {
        facingRight = right
        sprite.xScale = right ? 1 : -1
    }
}
#endif
