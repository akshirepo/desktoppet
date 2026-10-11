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
