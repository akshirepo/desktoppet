#if canImport(AppKit)
import AppKit
import CorgiCore
import SpriteKit

/// Draws floor segments (green ground, blue windows), the hit box, and the behavior name.
final class DebugOverlay {
    var enabled = false {
        didSet { if !enabled { clear() } }
    }
    private var nodes: [SKNode] = []

    func update(world: World, hitRect: CGRect, behavior: Behavior, overlays: OverlayManager) {
        clear()
        guard enabled else { return }
        for overlay in overlays.overlays {
            let origin = overlay.frame.origin
            let root = SKNode()
            root.zPosition = 100
            for s in world.segments {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: s.minX - origin.x, y: s.y - origin.y))
                path.addLine(to: CGPoint(x: s.maxX - origin.x, y: s.y - origin.y))
                let line = SKShapeNode(path: path)
                line.strokeColor = s.windowID == nil ? .systemGreen : .systemBlue
                line.lineWidth = 2
                root.addChild(line)
            }
            let box = SKShapeNode(rect: hitRect.offsetBy(dx: -origin.x, dy: -origin.y))
            box.strokeColor = .systemRed
            root.addChild(box)
            let label = SKLabelNode(text: behavior.rawValue)
            label.fontSize = 12
            label.fontColor = .systemRed
            label.position = CGPoint(x: hitRect.midX - origin.x, y: hitRect.maxY - origin.y + 4)
            root.addChild(label)
            overlay.scene.addChild(root)
            nodes.append(root)
        }
    }

    private func clear() {
        nodes.forEach { $0.removeFromParent() }
        nodes = []
    }
}
#endif
