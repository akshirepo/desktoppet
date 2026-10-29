#if canImport(AppKit)
import AppKit
import SpriteKit

final class OverlayManager {
    private(set) var overlays: [OverlayWindow] = []
    let corgiNode: SKNode
    weak var input: SceneInputHandler? {
        didSet { overlays.forEach { $0.scene.input = input } }
    }

    init(corgiNode: SKNode) {
        self.corgiNode = corgiNode
        rebuild()
    }

    var currentScene: OverlayScene? { corgiNode.scene as? OverlayScene }

    private var currentOverlay: OverlayWindow? {
        overlays.first { $0.scene === corgiNode.scene }
    }

    func rebuild() {
        mirrors.values.forEach { $0.removeFromParent() }
        mirrors = [:]
        corgiNode.removeFromParent()
        overlays.forEach { $0.close() }
        overlays = NSScreen.screens.map { OverlayWindow(screen: $0) }
        overlays.forEach {
            $0.scene.input = input
            $0.orderFrontRegardless()
        }
    }

    func toScene(_ global: CGPoint) -> CGPoint {
        guard let o = currentOverlay else { return global }
        return CGPoint(x: global.x - o.frame.minX, y: global.y - o.frame.minY)
    }

    func place(globalFeet p: CGPoint) {
        guard let target = overlays.first(where: { $0.frame.contains(p) })
            ?? overlays.first(where: { $0.frame.minX <= p.x && p.x < $0.frame.maxX }) ?? overlays.first
        else { return }
        if corgiNode.scene !== target.scene {
            corgiNode.removeFromParent()
            target.scene.addChild(corgiNode)
        }
        corgiNode.position = CGPoint(x: p.x - target.frame.minX, y: p.y - target.frame.minY)
    }

    /// Copies of the pet sprite shown on the other displays it overlaps, keyed by overlay.
    private var mirrors: [ObjectIdentifier: SKSpriteNode] = [:]

    /// While the pet straddles a seam, draws a copy of `sprite` on each other display it overlaps,
    /// so it isn't cut off at the edge of the display it belongs to.
    func mirror(_ sprite: SKSpriteNode, globalFeet p: CGPoint, scale: CGFloat = 1) {
        let f = sprite.frame                           // relative to the feet, before the pet's display scale
        let local = CGRect(x: f.minX * scale, y: f.minY * scale, width: f.width * scale, height: f.height * scale)
        let global = local.offsetBy(dx: p.x, dy: p.y)
        for o in overlays {
            let id = ObjectIdentifier(o)
            let needed = o.scene !== corgiNode.scene && o.frame.intersects(global)
            guard needed else {
                mirrors[id]?.isHidden = true
                continue
            }
            let m = mirrors[id] ?? {
                let n = SKSpriteNode()
                o.scene.addChild(n)
                mirrors[id] = n
                return n
            }()
            if m.scene !== o.scene { m.removeFromParent(); o.scene.addChild(m) }
            m.isHidden = false
            m.texture = sprite.texture
            m.anchorPoint = sprite.anchorPoint
            m.xScale = 1
            m.yScale = 1
            m.size = CGSize(width: sprite.size.width * scale, height: sprite.size.height * scale)
            m.xScale = sprite.xScale
            m.yScale = sprite.yScale
            m.zPosition = corgiNode.zPosition + sprite.zPosition
            m.position = CGPoint(x: p.x - o.frame.minX + sprite.position.x * scale, y: p.y - o.frame.minY + sprite.position.y * scale)
        }
    }

    /// Puts any node (the ball) on the overlay of the screen containing the global point `p`.
    func place(_ node: SKNode, global p: CGPoint) {
        guard let target = overlays.first(where: { $0.frame.contains(p) })
            ?? overlays.first(where: { $0.frame.minX <= p.x && p.x < $0.frame.maxX }) ?? overlays.first
        else { return }
        if node.scene !== target.scene {
            node.removeFromParent()
            target.scene.addChild(node)
        }
        node.position = CGPoint(x: p.x - target.frame.minX, y: p.y - target.frame.minY)
    }

    func setClickThrough(_ through: Bool) {
        for o in overlays where o.ignoresMouseEvents != through { o.ignoresMouseEvents = through }
    }

    func setFPS(_ fps: Int) {
        for o in overlays where o.skView.preferredFramesPerSecond != fps { o.skView.preferredFramesPerSecond = fps }
    }

    func setPaused(_ paused: Bool) {
        overlays.forEach { $0.skView.isPaused = paused }
    }
}
#endif
