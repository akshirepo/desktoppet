#if canImport(AppKit)
import AppKit
import CorgiCore
import SpriteKit

/// One folder of frames. The textures are decoded when the folder is first played and dropped again when
/// `FrameBudget` needs the room, so only what's been playing lately is in memory.
private final class FrameFolder {
    let name: String
    let urls: [URL]
    /// Pixel size of the frames as drawn (the full canvas).
    let canvas: CGSize
    /// The part of the canvas that's kept (see `FrameLayout`).
    let crop: CGRect
    var textures: [SKTexture]?

    init?(pack: URL, spec: AnimationSpec) {
        let dir = pack.appendingPathComponent(spec.folder).resolvingSymlinksInPath()
        urls = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard let first = urls.first, let source = CGImageSourceCreateWithURL(first as CFURL, nil),
              let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = info[kCGImagePropertyPixelWidth] as? Int, let h = info[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0 else { return nil }
        name = spec.folder
        canvas = CGSize(width: w, height: h)
        crop = FrameLayout(canvas: canvas, crop: spec.crop, anchor: .zero).crop
    }

    /// Reads and cuts down every frame. Safe off the main thread. Frames with identical files share one image
    /// (a held pose is stored as repeats), given as an index into `images` per frame.
    func decode() -> (images: [CGImage], index: [Int]) {
        var unique: [Data] = [], seen: [Data: Int] = [:], index: [Int] = []
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let i = seen[data] {
                index.append(i)
            } else {
                seen[data] = unique.count
                index.append(unique.count)
                unique.append(data)
            }
        }
        var decoded = [CGImage?](repeating: nil, count: unique.count)
        let crop = self.crop, canvas = self.canvas
        decoded.withUnsafeMutableBufferPointer { out in
            let out = UncheckedSendableBox(out)
            DispatchQueue.concurrentPerform(iterations: unique.count) { i in
                out.value[i] = Self.cut(unique[i], crop: crop, canvas: canvas)
            }
        }
        // A frame that won't decode is skipped, like a missing file was.
        var slot: [Int: Int] = [:], images: [CGImage] = []
        for (i, image) in decoded.enumerated() {
            guard let image else { continue }
            slot[i] = images.count
            images.append(image)
        }
        return (images, index.compactMap { slot[$0] })
    }

    /// The frame's crop box as its own bitmap, so the rest of the canvas isn't kept.
    private static func cut(_ data: Data, crop: CGRect, canvas: CGSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let ctx = CGContext(data: nil, width: Int(crop.width), height: Int(crop.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        // The crop is measured from the top-left; Core Graphics draws from the bottom-left.
        ctx.draw(image, in: CGRect(x: -crop.minX, y: -(canvas.height - crop.maxY), width: canvas.width, height: canvas.height))
        return ctx.makeImage()
    }

    func install(_ decoded: (images: [CGImage], index: [Int])) -> [SKTexture] {
        let made = decoded.images.map { SKTexture(cgImage: $0) }
        let frames = decoded.index.map { made[$0] }
        textures = frames
        bytes = decoded.images.count * Int(crop.width) * Int(crop.height) * 4
        return frames
    }

    private(set) var bytes = 0
}

private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

final class FrameSequenceBackend: AnimationBackend {
    let node = SKNode()
    let size: CGSize
    private(set) var movementBounds: CGRect = .zero
    var spriteBounds: CGRect { sprite.frame }
    /// Bubbles start just above the top of the current pose, so they sit close over a pet that's lying down too.
    var bubbleHeight: CGFloat { sprite.frame.maxY + 3 }
    private var poseBounds: [AnimState: CGRect] = [:]
    private let sprite = SKSpriteNode()
    /// The pet sprite itself, so a neighbouring display can mirror it while the pet straddles a seam.
    var spriteNode: SKSpriteNode { sprite }
    /// The size the last animation start set, for size-glitch logging.
    private(set) var lastSetSize = ""
    private let scale: CGFloat
    private typealias Entry = (spec: AnimationSpec, frames: FrameFolder)
    private var animations: [AnimState: Entry] = [:]
    /// Named one-shot transitions ("stand>sit", "enter:watch", ...).
    private var bridgeAnims: [String: Entry] = [:]
    /// Decoded frames are held to about this much; the loops needed at once (standing, moving, falling, being
    /// picked up) are kept whatever happens.
    private var budget = FrameBudget<String>(limit: 128 << 20)
    private static let keptReady: [AnimState] = [.idle, .walk, .run, .fall, .scared]
    /// The size `start` last gave the sprite, so a size glitch can be told from a small pose.
    private(set) var expectedSpriteSize: CGSize = .zero
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
    /// The wall to hide behind at a screen edge, from the pack's `edgeWall`.
    private(set) var edgeWall: EdgeWallArt?

    init(packURL: URL) throws {
        let manifest = try AnimationManifest.load(from: packURL.appendingPathComponent("manifest.json"))
        var folders: [String: FrameFolder] = [:]
        func folder(_ spec: AnimationSpec) -> FrameFolder? {
            if let f = folders[spec.folder] { return f }
            let f = FrameFolder(pack: packURL, spec: spec)
            folders[spec.folder] = f
            return f
        }
        var animations: [AnimState: Entry] = [:]
        for (key, spec) in manifest.states {
            guard let state = AnimState(rawValue: key) else {
                NSLog("DesktopPet: manifest has unknown state '\(key)', skipping")
                continue
            }
            guard let frames = folder(spec) else {
                NSLog("DesktopPet: no PNG frames in \(spec.folder), '\(key)' will use idle")
                continue
            }
            animations[state] = (spec, frames)
        }
        var bridgeAnims: [String: Entry] = [:]
        for (name, spec) in manifest.bridges ?? [:] {
            if let frames = folder(spec) { bridgeAnims[name] = (spec, frames) }
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
        if let w = manifest.edgeWall {
            let art = EdgeWallArt(pack: packURL, spec: w, packScale: CGFloat(manifest.scale ?? 1))
            if art == nil { NSLog("DesktopPet: edge wall art missing in \(w.folder), peeking without a wall") }
            edgeWall = art
        }
        postures = manifest.postures
        available = manifest.available
        directPairs = manifest.directPairs
        size = CGSize(width: idle.frames.canvas.width * scale, height: idle.frames.canvas.height * scale)
        let grips: Set<AnimState> = [.clingSit, .clingHang, .clingPeek, .clingLeft, .clingRight]
        for (state, entry) in animations {
            // A pose is measured by its whole canvas, whatever part of it is kept in memory.
            let bounds = FrameLayout.canvasBounds(canvas: entry.frames.canvas, anchor: Self.anchor(entry.spec),
                                                  scale: scale * CGFloat(entry.spec.scale ?? 1))
            poseBounds[state] = bounds
            if !grips.contains(state) {
                let mirrored = CGRect(x: -bounds.maxX, y: bounds.minY, width: bounds.width, height: bounds.height)
                movementBounds = movementBounds.union(bounds).union(mirrored)
            }
        }
        budget.pinned = Set(Self.keptReady.compactMap { animations[$0]?.frames.name })
        node.addChild(shadow)
        node.addChild(sprite)
        play(.idle)
        warm(Self.keptReady.compactMap { animations[$0]?.frames })
    }

    /// The folder's textures in playing order, decoding them now if they aren't in memory.
    private func textures(_ entry: Entry) -> [SKTexture] {
        let folder = entry.frames
        let frames = folder.textures ?? folder.install(folder.decode())
        noteUse(folder)
        return entry.spec.reversed == true ? frames.reversed() : frames
    }

    private func noteUse(_ folder: FrameFolder) {
        for name in budget.use(folder.name, bytes: folder.bytes) {
            (animations.values.first { $0.frames.name == name } ?? bridgeAnims.values.first { $0.frames.name == name })?
                .frames.textures = nil
        }
    }

    /// Decodes folders in the background so their first play doesn't wait on it.
    private func warm(_ folders: [FrameFolder]) {
        DispatchQueue.global(qos: .utility).async {
            for folder in folders {
                let decoded = folder.decode()
                DispatchQueue.main.async { [weak self] in
                    guard let self, folder.textures == nil else { return }
                    _ = folder.install(decoded)
                    self.noteUse(folder)
                }
            }
        }
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
        return start(entry, state: nil, once: true, completion: completion, eased: true)
    }

    /// Per-frame times for a one-shot move that eases in and out: the first and last frames linger a little,
    /// the middle moves faster, and the total stays the same.
    static func easedTimes(count: Int, frameDuration: TimeInterval) -> [TimeInterval] {
        guard count > 2 else { return Array(repeating: frameDuration, count: count) }
        let weights = (0..<count).map { i -> Double in
            let x = (Double(i) + 0.5) / Double(count)          // 0...1 across the move
            return 1 + 0.6 * cos(2 * .pi * x)                   // ~1.6x at the ends, ~0.4x mid-move
        }
        let total = weights.reduce(0, +)
        return weights.map { $0 / total * frameDuration * Double(count) }
    }

    private func start(_ state: AnimState, once: Bool, completion: (() -> Void)?) -> TimeInterval? {
        guard let entry = animations[state] ?? animations[state.base] ?? animations[.idle] else { return nil }
        // Swapping bowl versions of the same loop carries on from the same frame instead of restarting.
        var phase = 0
        if !once, let cur = loopState, cur != state, cur.base == state.base, loopCycle > 0,
           let curCount = loopFrameCount, curCount == entry.frames.urls.count {
            let fps = entry.spec.fps.isFinite ? max(entry.spec.fps, 1) : 1
            phase = Int(((CACurrentMediaTime() - loopStart) * fps).rounded(.down)) % curCount
        }
        return start(entry, state: state, once: once, completion: completion, phase: phase)
    }

    private func start(_ entry: Entry, state: AnimState?, once: Bool,
                       completion: (() -> Void)?, phase: Int = 0, eased: Bool = false) -> TimeInterval? {
        let fps = entry.spec.fps.isFinite ? max(entry.spec.fps, 1) : 1
        let frameDuration = 1 / fps
        let all = textures(entry)
        let duration = Double(all.count) * frameDuration
        guard duration.isFinite, duration > 0 else { return nil }
        playbackID &+= 1
        let id = playbackID
        sprite.removeAllActions()
        let layout = FrameLayout(canvas: entry.frames.canvas, crop: entry.spec.crop, anchor: Self.anchor(entry.spec))
        sprite.anchorPoint = layout.anchor
        let frames = phase > 0 && phase < all.count ? Array(all[phase...] + all[..<phase]) : all
        sprite.texture = frames[0]
        // SKSpriteNode.size is the on-screen size (it already includes xScale/yScale), so the pack scale is
        // applied here once and the node scale only carries the left/right flip. Frames in a folder share one size,
        // the folder's crop box, and the anchor above puts that box where it sits in the full canvas.
        let t = layout.crop.size
        sprite.yScale = 1
        sprite.xScale = facingRight ? 1 : -1
        let k = scale * CGFloat(entry.spec.scale ?? 1)
        sprite.size = CGSize(width: t.width * k, height: t.height * k)
        expectedSpriteSize = sprite.size
        applyTurn()                          // a turn in progress carries on from where it was
        lastSetSize = "\(Int(sprite.size.width))x\(Int(sprite.size.height)) k=\(k) eased=\(eased) once=\(once) state=\(state?.rawValue ?? "bridge")"
        // Keep the last displayed pose on completion/cancellation; do not restore an older texture.
        let animation = SKAction.animate(with: frames, timePerFrame: frameDuration,
                                         resize: false, restore: false)
        if once {
            let move: SKAction
            if eased {
                let times = Self.easedTimes(count: frames.count, frameDuration: frameDuration)
                // One single-frame animate per frame: SKAction.setTexture(_:resize: false) still resized the sprite
                // to the full texture size (420x320 pt), which made the pet huge mid-transition.
                move = .sequence(zip(frames, times).map { SKAction.animate(with: [$0.0], timePerFrame: $0.1, resize: false, restore: false) })
            } else {
                move = animation
            }
            sprite.run(.sequence([move, .run { [weak self] in
                guard self?.playbackID == id else { return }
                completion?()
            }]), withKey: "frames")
        } else {
            sprite.run(entry.spec.loop ? .repeatForever(animation) : animation, withKey: "frames")
            loopStart = CACurrentMediaTime() - Double(phase) * frameDuration
            loopCycle = entry.spec.loop ? duration : 0
            loopState = state
            loopFrameCount = all.count
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

    /// Turns to face the other way. Animated, it squashes flat and opens out again over `turnSeconds`, like a card
    /// turning round, and a turn reversed halfway just turns back.
    func setFacing(right: Bool, animated: Bool) {
        facingRight = right
        let target: CGFloat = right ? 0 : .pi
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(max(now - lastTurnTime, 0), 0.05))
        lastTurnTime = now
        if animated {
            let step = .pi / Self.turnSeconds * dt
            turnAngle += max(-step, min(step, target - turnAngle))
        } else {
            turnAngle = target
        }
        applyTurn()
    }

    private static let turnSeconds: CGFloat = 0.18
    /// 0 facing right, pi facing left; in between it's mid-turn.
    private var turnAngle: CGFloat = 0
    private var lastTurnTime: CFTimeInterval = 0

    /// The sprite's width follows its x scale, so this is all a turn needs. Never quite zero, so it has a size.
    private func applyTurn() {
        let x = cos(turnAngle)
        sprite.xScale = abs(x) < 0.06 ? (facingRight ? 0.06 : -0.06) : x
    }

    /// A soft patch of shade on the floor under the pet: `drop` is how far below its feet the floor is (0 when
    /// standing), nil for no floor to cast on. It shrinks and fades the higher the pet is.
    func setShadow(drop: CGFloat?) {
        guard let drop, expectedSpriteSize.width > 0 else {
            shadow.isHidden = true
            return
        }
        let near = max(0.3, 1 - drop / 420)
        shadow.isHidden = false
        shadow.size = CGSize(width: expectedSpriteSize.width * 0.66 * near, height: 9 * near)
        shadow.alpha = 0.55 * near
        // The pose's middle, whichever way it faces (the art isn't always centred on the feet).
        let mid = sprite.anchorPoint.x * expectedSpriteSize.width
        let offset = expectedSpriteSize.width / 2 - mid
        shadow.position = CGPoint(x: offset * (facingRight ? 1 : -1), y: -drop - 1)
    }

    private let shadow: SKSpriteNode = {
        // A blurred dark oval, drawn once.
        let w = 96, h = 24
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
        ctx.scaleBy(x: CGFloat(w) / CGFloat(h), y: 1)
        let colors = [NSColor(white: 0, alpha: 0.5).cgColor, NSColor(white: 0, alpha: 0.28).cgColor, NSColor(white: 0, alpha: 0).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: [0, 0.55, 1])!
        ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: CGFloat(h) / 2, options: [])
        let node = SKSpriteNode(texture: SKTexture(cgImage: ctx.makeImage()!))
        node.zPosition = -1
        node.isHidden = true
        return node
    }()
}
#endif
