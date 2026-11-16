#if canImport(AppKit)
import AppKit
import CorgiCore
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

    // MARK: - Speech and thought bubbles

    private static let bubbleRoot = Bundle.main.resourceURL?.appendingPathComponent("Bubbles")
    private static var accentTextures: [String: SKTexture] = [:]

    /// The little icon that goes with a line: the soft set, else the pixel accents (Assets/Bubbles/accents).
    private static func accent(_ name: String) -> SKTexture? {
        if let t = Doodles.texture(name) { return t }
        if let t = accentTextures[name] { return t }
        guard let url = bubbleRoot?.appendingPathComponent("accents/\(name).png"), let img = NSImage(contentsOf: url) else { return nil }
        let t = SKTexture(image: img)
        t.filteringMode = .nearest   // pixel art
        accentTextures[name] = t
        return t
    }

    private static let bubbleName = "bubble"
    /// The bubble's lavender, and #4b3f55 for the lettering.
    private static let lavender = NSColor(srgbRed: 0.91, green: 0.87, blue: 1.0, alpha: 1)
    private static let plum = NSColor(srgbRed: 0.29, green: 0.25, blue: 0.33, alpha: 1)

    /// Fredoka semibold (Assets/Fonts, SIL Open Font License), registered for this process; the rounded system
    /// font if it isn't bundled.
    private static let bubbleFont: NSFont = {
        let size: CGFloat = 11
        if let file = Bundle.main.resourceURL?.appendingPathComponent("Fonts/Fredoka.ttf") {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
        if let f = NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: "Fredoka"]), size: size), f.familyName == "Fredoka" {
            // One file with a weight dial ('wght'); semibold is the bubbly one.
            return NSFont(descriptor: f.fontDescriptor.addingAttributes([.variation: [0x77676874: 600]]), size: size) ?? f
        }
        let system = NSFont.systemFont(ofSize: size, weight: .semibold)
        return system.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? system
    }()

    /// One bubble at a time: when a new one appears, whatever is showing fades out quickly.
    /// Bubbles still waiting on their delay are left alone.
    private static func replaceOtherBubbles(_ bubble: SKNode, on node: SKNode) -> SKAction {
        .run { [weak bubble, weak node] in
            guard let bubble, let node else { return }
            for other in node.children where other.name == bubbleName && other !== bubble && other.alpha > 0 {
                other.name = nil
                other.removeAllActions()
                other.run(.sequence([.fadeOut(withDuration: 0.12), .removeFromParent()]))
            }
        }
    }

    /// How far the sticker's box starts to the side of the origin, and how far above it.
    private static let stickerSide: CGFloat = 14, stickerLift: CGFloat = 9

    /// A puffy lavender sticker of `size`: thick white border, a faint edge and shadow so it holds up on any
    /// background, a little shine, and two soft dots leading down to the origin (the pet) instead of a pointed tail.
    /// The box opens to the right of the dots, or to the left with `tailRight`.
    private static func sticker(size: CGSize, tailRight: Bool) -> SKNode {
        let node = SKNode()
        let box = CGRect(x: tailRight ? stickerSide - size.width : -stickerSide, y: stickerLift, width: size.width, height: size.height)
        let r = min(13, size.height / 2)
        let dir: CGFloat = tailRight ? -1 : 1
        let parts: [CGPath] = [
            CGPath(roundedRect: box, cornerWidth: r, cornerHeight: r, transform: nil),
            CGPath(ellipseIn: CGRect(x: dir * 1.5 - 3.2, y: stickerLift - 6.4, width: 6.4, height: 6.4), transform: nil),
            CGPath(ellipseIn: CGRect(x: -1.8, y: -0.5, width: 3.6, height: 3.6), transform: nil),
        ]
        func layer(_ fill: NSColor, _ stroke: NSColor, _ width: CGFloat, dy: CGFloat = 0, z: CGFloat) {
            for path in parts {
                let shape = SKShapeNode(path: path)
                shape.fillColor = fill
                shape.strokeColor = stroke
                shape.lineWidth = width
                shape.isAntialiased = true
                shape.position = CGPoint(x: 0, y: dy)
                shape.zPosition = z
                node.addChild(shape)
            }
        }
        let shade = NSColor(srgbRed: 0.2, green: 0.16, blue: 0.3, alpha: 1)
        layer(shade.withAlphaComponent(0.16), .clear, 0, dy: -2, z: -0.3)             // soft shadow
        layer(.clear, shade.withAlphaComponent(0.28), 4.6, z: -0.2)                    // faint edge outside the border
        layer(lavender, .white, 2.6, z: -0.1)                                          // the sticker
        let shine = SKShapeNode(ellipseOf: CGSize(width: min(12, size.width * 0.3), height: 3))
        shine.fillColor = NSColor(white: 1, alpha: 0.65)
        shine.strokeColor = .clear
        shine.position = CGPoint(x: box.minX + r + 3, y: box.maxY - 4.5)
        node.addChild(shine)
        return node
    }

    /// Pops a bubble in above the pet with a little bounce, holds it, and fades it out.
    private static func show(_ bubble: SKNode, on node: SKNode, height: CGFloat, hold: TimeInterval, delay: TimeInterval) {
        bubble.position = CGPoint(x: 0, y: height + 2)
        bubble.zPosition = 50
        bubble.alpha = 0
        bubble.setScale(0.6)
        bubble.name = bubbleName
        node.addChild(bubble)
        bubble.run(.sequence([
            .wait(forDuration: delay),
            replaceOtherBubbles(bubble, on: node),
            .group([.fadeIn(withDuration: 0.12), .sequence([.scale(to: 1.1, duration: 0.14), .scale(to: 1, duration: 0.1)])]),
            .wait(forDuration: hold),
            .fadeOut(withDuration: 0.3),
            .removeFromParent(),
        ]))
    }

    /// A speech bubble fitted to `text` (up to two lines) above the pet, with the line's icon in front of the words.
    /// `tailRight` opens the bubble to the left (for a pet near the right edge).
    static func say(_ text: String, icon: String?, tailRight: Bool, on node: SKNode, height: CGFloat, delay: TimeInterval = 0) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let label = SKLabelNode(attributedText: NSAttributedString(string: text, attributes: [
            .font: bubbleFont, .foregroundColor: plum, .paragraphStyle: style]))
        label.numberOfLines = 2
        label.preferredMaxLayoutWidth = 104
        label.lineBreakMode = .byWordWrapping
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.zPosition = 1
        let textSize = label.frame.size
        let mark = icon.flatMap(accent)
        let pad: CGFloat = 10, iconWidth: CGFloat = mark == nil ? 0 : 15
        let size = CGSize(width: ceil(textSize.width) + iconWidth + pad * 2, height: ceil(textSize.height) + 12)
        let minX = tailRight ? stickerSide - size.width : -stickerSide
        let container = sticker(size: size, tailRight: tailRight)
        label.position = CGPoint(x: minX + pad + iconWidth + textSize.width / 2, y: stickerLift + size.height / 2)
        container.addChild(label)
        if let mark {
            let a = SKSpriteNode(texture: mark, size: CGSize(width: 13, height: 13))
            a.position = CGPoint(x: minX + pad + 5, y: stickerLift + size.height / 2)
            a.zPosition = 1
            container.addChild(a)
        }
        show(container, on: node, height: height, hold: 2.4, delay: delay)
    }

    /// A small round bubble with just a need's icon in it (mood bubbles). Says `fallback` if the icon is missing.
    static func thought(icon: String, fallback: String, on node: SKNode, height: CGFloat) {
        guard let inner = Doodles.texture(icon) else {
            say(fallback, icon: nil, tailRight: false, on: node, height: height)
            return
        }
        let d: CGFloat = 28
        let container = sticker(size: CGSize(width: d, height: d), tailRight: false)
        let symbol = SKSpriteNode(texture: inner, size: CGSize(width: 16, height: 16))
        symbol.position = CGPoint(x: -stickerSide + d / 2, y: stickerLift + d / 2)
        symbol.zPosition = 1
        container.addChild(symbol)
        show(container, on: node, height: height, hold: 1.6, delay: 0)
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
