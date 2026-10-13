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

    /// Rounded speech bubble above the corgi for 2.5s, after `delay`. `thought` adds the little trailing dots.
    static func speech(_ text: String, on node: SKNode, height: CGFloat, delay: TimeInterval = 0,
                       thought: Bool = false) {
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
