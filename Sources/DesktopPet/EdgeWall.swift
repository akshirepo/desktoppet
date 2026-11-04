#if canImport(AppKit)
import AppKit
import CorgiCore
import ImageIO
import SpriteKit

/// A pack's wall art for hiding behind at a screen edge (`EdgeWallSpec`): the cap and the brick tile, drawn for a
/// left edge, in canvas pixels at the pack scale.
struct EdgeWallArt {
    let spec: EdgeWallSpec
    let cap: CGImage
    let tile: CGImage
    /// Optional footing drawn at the bottom, so a short wall section ends finished instead of cut off.
    let base: CGImage?
    let packScale: CGFloat

    /// Points before the display scale.
    var width: CGFloat { CGFloat(spec.width) * packScale }
    var height: CGFloat { CGFloat(spec.height) * packScale }
    var inset: CGFloat { spec.inset(packScale: Double(packScale)) }
    /// How far below the feet a hold's wall section reaches (points before the display scale), nil for floor-to-grip.
    var holdDepth: CGFloat? { spec.holdDepth.map { CGFloat($0) * packScale } }

    init?(pack: URL, spec: EdgeWallSpec, packScale: CGFloat) {
        let dir = pack.appendingPathComponent(spec.folder)
        guard let cap = Self.image(dir.appendingPathComponent("cap.png")),
              let tile = Self.image(dir.appendingPathComponent("tile.png")),
              cap.width == tile.width, tile.height > 0 else { return nil }
        self.spec = spec
        self.cap = cap
        self.tile = tile
        let base = Self.image(dir.appendingPathComponent("base.png"))
        self.base = base?.width == cap.width ? base : nil
        self.packScale = packScale
    }

    private static func image(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// The cap on top, the footing (if any) at the bottom and the tile repeated between, `heightPx` canvas pixels tall.
    func texture(heightPx: Int) -> SKTexture? {
        let w = cap.width
        guard heightPx > 0,
              let ctx = CGContext(data: nil, width: w, height: heightPx, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        // Core Graphics counts up from the bottom: the cap goes at the top, tiles below it down past y = 0.
        var top = heightPx
        let footing = base.map { min($0.height, max(0, heightPx - cap.height)) } ?? 0
        ctx.draw(cap, in: CGRect(x: 0, y: top - cap.height, width: w, height: cap.height))
        top -= cap.height
        while top > footing {
            ctx.draw(tile, in: CGRect(x: 0, y: top - tile.height, width: w, height: tile.height))
            top -= tile.height
        }
        if let base, footing > 0 {
            // Drawn last, over the cut end of the last tile; its bottom row sits on the wall's bottom edge.
            ctx.draw(base, in: CGRect(x: 0, y: footing - base.height, width: w, height: base.height))
        }
        guard let image = ctx.makeImage() else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        return texture
    }
}

/// The wall on screen: slides out from behind the screen edge when the pet goes to hide, back in when it's done.
/// It's drawn just behind the pet, so paws drawn over its face sit on the bricks.
final class EdgeWall {
    private var node: SKSpriteNode?
    private var direction: CGFloat = 1
    private var width: CGFloat = 0
    static let slideIn: TimeInterval = 0.2
    static let slideOut: TimeInterval = 0.25

    var isShown: Bool { node != nil }

    /// `frame` from `EdgePeek.wallFrame` (global points); `scale` is the display's draw scale.
    func show(_ art: EdgeWallArt, frame: CGRect, side: EdgeSide, scale: CGFloat, overlays: OverlayManager) {
        remove()
        let px = Int((frame.height / (art.packScale * scale)).rounded())
        guard frame.width > 0, frame.height > 0, let texture = art.texture(heightPx: max(2, px)) else { return }
        let n = SKSpriteNode(texture: texture)
        n.anchorPoint = .zero
        n.yScale = 1
        n.xScale = side == .left ? 1 : -1          // mirrored at a right edge, still anchored on the edge
        n.size = frame.size
        n.zPosition = overlays.corgiNode.zPosition - 1
        let edgeX = side == .left ? frame.minX : frame.maxX
        let inside = CGPoint(x: side == .left ? frame.minX + 1 : frame.maxX - 1, y: frame.minY + 1)
        overlays.place(n, global: CGPoint(x: edgeX, y: frame.minY), inside: inside)
        direction = side == .left ? 1 : -1
        width = frame.width
        let home = n.position.x
        n.position.x = home - direction * frame.width
        let slide = SKAction.moveTo(x: home, duration: Self.slideIn)
        slide.timingMode = .easeOut
        n.run(slide)
        node = n
    }

    /// Slides back behind the edge (or vanishes at once).
    func hide(animated: Bool = true) {
        guard let n = node else { return }
        node = nil
        guard animated else { n.removeFromParent(); return }
        let slide = SKAction.moveBy(x: -direction * width, y: 0, duration: Self.slideOut)
        slide.timingMode = .easeIn
        n.run(.sequence([slide, .removeFromParent()]))
    }

    func remove() { hide(animated: false) }
}
#endif
