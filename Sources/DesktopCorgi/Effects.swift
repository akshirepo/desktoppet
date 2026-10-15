#if canImport(AppKit)
import AppKit
import SpriteKit

enum Effects {
    /// Emoji that floats up from above the corgi and fades out.
    static func floatEmoji(_ text: String, on node: SKNode, height: CGFloat, count: Int = 1) {
        for i in 0..<count {
            let label = SKLabelNode(text: text)
            label.fontSize = 18
            label.position = CGPoint(x: CGFloat.random(in: -18...18), y: height)
            label.alpha = 0
            node.addChild(label)
            label.run(.sequence([
                .wait(forDuration: Double(i) * 0.15),
                .fadeIn(withDuration: 0.1),
                .group([.moveBy(x: 0, y: 40, duration: 1.0), .fadeOut(withDuration: 1.0)]),
                .removeFromParent(),
            ]))
        }
    }

    /// Doodle icon that floats up from above the pet and fades out. Falls back to `fallback` text.
    static func floatDoodle(_ name: String, fallback: String, on node: SKNode, height: CGFloat,
                            count: Int = 1, size: CGFloat = 24) {
        guard let texture = Doodles.texture(name) else {
            floatEmoji(fallback, on: node, height: height, count: count)
            return
        }
        for i in 0..<count {
            let sprite = SKSpriteNode(texture: texture, size: CGSize(width: size, height: size))
            sprite.position = CGPoint(x: CGFloat.random(in: -18...18), y: height + size / 2)
            sprite.alpha = 0
            sprite.zPosition = 40
            node.addChild(sprite)
            sprite.run(.sequence([
                .wait(forDuration: Double(i) * 0.15),
                .fadeIn(withDuration: 0.1),
                .group([.moveBy(x: 0, y: 40, duration: 1.0), .fadeOut(withDuration: 1.0)]),
                .removeFromParent(),
            ]))
        }
    }

    /// Doodle thought bubble with an icon inside (mood bubbles). Falls back to the text bubble.
    static func thought(icon: String, fallback: String, on node: SKNode, height: CGFloat) {
        guard let cloud = Doodles.texture("thought"), let inner = Doodles.texture(icon) else {
            speech(fallback, on: node, height: height, thought: true)
            return
        }
        let bubble = SKSpriteNode(texture: cloud, size: CGSize(width: 54, height: 54))
        let symbol = SKSpriteNode(texture: inner, size: CGSize(width: 22, height: 22))
        symbol.position = CGPoint(x: 0, y: 6)
        symbol.zPosition = 1
        bubble.addChild(symbol)
        show(bubble, on: node, at: CGPoint(x: 0, y: height + 30), delay: 0)
    }

    private static func show(_ bubble: SKNode, on node: SKNode, at position: CGPoint, delay: TimeInterval) {
        bubble.position = position
        bubble.zPosition = 50
        bubble.alpha = 0
        node.addChild(bubble)
        bubble.run(.sequence([
            .wait(forDuration: delay),
            .fadeIn(withDuration: 0.15),
            .wait(forDuration: 2.2),
            .fadeOut(withDuration: 0.15),
            .removeFromParent(),
        ]))
    }

    /// Speech bubble above the pet for 2.5s, after `delay`: the doodle bubble when bundled, else a rounded box.
    /// `thought` adds the little trailing dots (text fallback only).
    static func speech(_ text: String, on node: SKNode, height: CGFloat, delay: TimeInterval = 0,
                       thought: Bool = false) {
        if !thought, let tex = Doodles.texture("speech-oval") {
            let label = SKLabelNode(text: text)
            label.fontName = NSFont(name: "Chalkboard SE Bold", size: 14) != nil ? "Chalkboard SE Bold" : NSFont.boldSystemFont(ofSize: 14).fontName
            label.fontSize = 14
            label.fontColor = NSColor(white: 0.15, alpha: 1)
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            let w = max(64, label.frame.width + 34), h = w / 2
            let container = SKNode()
            let bubble = SKSpriteNode(texture: tex, size: CGSize(width: w, height: h))
            container.addChild(bubble)
            label.position = CGPoint(x: 0, y: h * 0.06)
            label.zPosition = 1
            container.addChild(label)
            show(container, on: node, at: CGPoint(x: 0, y: height + h / 2 + 6), delay: delay)
            return
        }
        let label = SKLabelNode(text: text)
        label.fontName = NSFont.boldSystemFont(ofSize: 13).fontName
        label.fontSize = 13
        label.fontColor = .black
        label.verticalAlignmentMode = .center
        let w = label.frame.width + 18, h: CGFloat = 24
        let bubble = SKShapeNode(rect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: 10)
        bubble.fillColor = .white
        bubble.strokeColor = NSColor(white: 0.2, alpha: 1)
        bubble.lineWidth = 1.5
        bubble.addChild(label)
        if thought {
            for (x, y, r) in [(-w / 2 + 10, -h / 2 - 6, 3.5), (-w / 2 + 5, -h / 2 - 13, 2.2)] as [(CGFloat, CGFloat, CGFloat)] {
                let dot = SKShapeNode(circleOfRadius: r)
                dot.fillColor = .white
                dot.strokeColor = NSColor(white: 0.2, alpha: 1)
                dot.lineWidth = 1.5
                dot.position = CGPoint(x: x, y: y)
                bubble.addChild(dot)
            }
        }
        bubble.position = CGPoint(x: 0, y: height + 22)
        bubble.zPosition = 50
        bubble.alpha = 0
        node.addChild(bubble)
        bubble.run(.sequence([
            .wait(forDuration: delay),
            .fadeIn(withDuration: 0.15),
            .wait(forDuration: 2.2),
            .fadeOut(withDuration: 0.15),
            .removeFromParent(),
        ]))
    }

    /// Placeholder prop drawn next to the corgi (📖 🎧 📺 ⚽️) until the art pack has one.
    static func makeProp(_ emoji: String) -> SKLabelNode {
        let label = SKLabelNode(text: emoji)
        label.fontSize = 22
        label.verticalAlignmentMode = .baseline
        label.zPosition = 5
        return label
    }

    static func makeBall() -> SKShapeNode {
        let ball = SKShapeNode(circleOfRadius: 7)
        ball.fillColor = .systemRed
        ball.strokeColor = .white
        ball.lineWidth = 1.5
        return ball
    }
}
#endif
