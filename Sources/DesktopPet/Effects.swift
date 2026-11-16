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

    // MARK: - Bubble artwork with live text (Assets/Bubbles)

    private struct BubbleGeometry: Decodable {
        struct Rect: Decodable { let x, y, width, height: CGFloat }
        struct Point: Decodable { let x, y: CGFloat }
        let width, height: CGFloat
        let textBox: Rect
        let tailTip: Point
    }

    private static let bubbleRoot = Bundle.main.resourceURL?.appendingPathComponent("Bubbles")
    private static let bubbleGeometry: [String: BubbleGeometry] = {
        guard let url = bubbleRoot?.appendingPathComponent("bubbles.json"), let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: BubbleGeometry].self, from: data)) ?? [:]
    }()
    private static var bubbleTextures: [String: SKTexture] = [:]
    /// #52372e, the bubble artwork's ink color.
    private static let bubbleInk = NSColor(srgbRed: 82.0 / 255.0, green: 55.0 / 255.0, blue: 46.0 / 255.0, alpha: 1.0)

    private static func bubbleTexture(_ path: String) -> SKTexture? {
        if let t = bubbleTextures[path] { return t }
        guard let url = bubbleRoot?.appendingPathComponent(path), let img = NSImage(contentsOf: url) else { return nil }
        let t = SKTexture(image: img)
        t.filteringMode = .nearest   // pixel art
        bubbleTextures[path] = t
        return t
    }

    private static let bubbleName = "bubble"
    /// Speech bubbles are drawn at this size relative to their artwork layout.
    private static let bubbleScale: CGFloat = 0.8

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

    /// How bubbles are drawn and lettered; the user picks both in the menu.
    static var bubbleStyle = BubbleStyle.sticker
    static var bubbleFont = BubbleFont.bubbly
    static var bubbleColor = BubbleColor.lavender
    private static var tint: NSColor {
        let (r, g, b) = bubbleColor.rgb
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
    /// #4b3f55, the lettering on the pastel bubbles.
    private static let plum = NSColor(srgbRed: 0.29, green: 0.25, blue: 0.33, alpha: 1)

    /// The pixel fonts that ship with the app (Assets/Fonts, SIL Open Font License), made available to this process.
    private static let bundledFonts: Void = {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension.lowercased() == "ttf" {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }()

    /// The chosen typeface at the size it reads best in a small bubble; `bump` makes it a little larger.
    private static func font(_ choice: BubbleFont, bump: CGFloat = 0) -> NSFont {
        _ = bundledFonts
        let (names, size): ([String], CGFloat)
        switch choice {
        case .bubbly: (names, size) = (["Fredoka"], 11)
        case .chubby: (names, size) = (["Sniglet-Regular", "Sniglet"], 11)
        case .soft: (names, size) = (["VarelaRound-Regular", "Varela Round"], 10.5)
        case .neat: (names, size) = (["PatrickHand-Regular", "Patrick Hand"], 12)
        case .pixel: (names, size) = (["PixelifySans-Regular", "Pixelify Sans"], 11)
        case .pixelCaps: (names, size) = (["Silkscreen-Regular", "Silkscreen"], 8)
        case .terminal: (names, size) = (["VT323-Regular", "VT323"], 13)
        case .rounded: (names, size) = ([], 10.5)
        case .clean: (names, size) = (["AvenirNext-DemiBold"], 10)
        case .handwritten: (names, size) = (["ChalkboardSE-Regular"], 10.5)
        case .note: (names, size) = (["Noteworthy-Bold"], 10.5)
        case .marker: (names, size) = (["MarkerFelt-Thin"], 11.5)
        case .comic: (names, size) = (["ComicSansMS"], 10)
        case .typewriter: (names, size) = (["AmericanTypewriter"], 10)
        case .serif: (names, size) = (["Georgia"], 10)
        }
        for name in names {
            let found = NSFont(name: name, size: size + bump)
                ?? NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: name]), size: size + bump)
            guard let f = found, f.familyName == name || f.fontName == name else { continue }
            // Fredoka is one file with a weight dial ('wght'); semibold is the bubbly one.
            if name == "Fredoka" {
                return NSFont(descriptor: f.fontDescriptor.addingAttributes([.variation: [0x77676874: 600]]), size: size + bump) ?? f
            }
            return f
        }
        let system = NSFont.systemFont(ofSize: size + bump, weight: .semibold)
        return system.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size + bump) } ?? system
    }

    private struct BubbleLook {
        var fill: NSColor, stroke: NSColor, ink: NSColor
        static var light: BubbleLook {
            BubbleLook(fill: tint.withAlphaComponent(0.97), stroke: plum.withAlphaComponent(0.75), ink: plum)
        }
        static let dark = BubbleLook(fill: NSColor(white: 0.12, alpha: 0.82), stroke: NSColor(white: 1, alpha: 0.18),
                                     ink: NSColor(white: 0.97, alpha: 1))
    }

    /// A rounded box of `size` whose bottom edge sits `tail` above the origin, with a little tail down to the
    /// origin. The box starts 12pt to the side of the tail and opens right (or left with `tailRight`).
    private static func capsule(size: CGSize, tailRight: Bool, look: BubbleLook, pixel: Bool = false) -> SKShapeNode {
        let tail: CGFloat = 5, r = min(9, size.height / 2)
        let minX = tailRight ? 12 - size.width : -12
        let box = CGRect(x: minX, y: tail, width: size.width, height: size.height)
        if pixel {
            // Corners cut in one 2pt step and a thick edge, like the pets' outlines.
            let c: CGFloat = 2
            let path = CGMutablePath()
            path.addLines(between: [
                CGPoint(x: box.minX + c, y: box.minY), CGPoint(x: -3, y: box.minY), CGPoint(x: -3, y: box.minY - 2),
                CGPoint(x: -1, y: box.minY - 2), CGPoint(x: -1, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: box.minY - 2),
                CGPoint(x: 3, y: box.minY - 2), CGPoint(x: 3, y: box.minY),
                CGPoint(x: box.maxX - c, y: box.minY), CGPoint(x: box.maxX - c, y: box.minY + c), CGPoint(x: box.maxX, y: box.minY + c),
                CGPoint(x: box.maxX, y: box.maxY - c), CGPoint(x: box.maxX - c, y: box.maxY - c), CGPoint(x: box.maxX - c, y: box.maxY),
                CGPoint(x: box.minX + c, y: box.maxY), CGPoint(x: box.minX + c, y: box.maxY - c), CGPoint(x: box.minX, y: box.maxY - c),
                CGPoint(x: box.minX, y: box.minY + c), CGPoint(x: box.minX + c, y: box.minY + c),
            ])
            path.closeSubpath()
            let shape = SKShapeNode(path: path)
            shape.fillColor = tint
            shape.strokeColor = plum
            shape.lineWidth = 2
            shape.lineJoin = .miter
            shape.isAntialiased = false
            return shape
        }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: box.minX + r, y: box.minY))
        path.addLine(to: CGPoint(x: -4, y: box.minY))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 4, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX - r, y: box.minY))
        path.addArc(tangent1End: CGPoint(x: box.maxX, y: box.minY), tangent2End: CGPoint(x: box.maxX, y: box.midY), radius: r)
        path.addArc(tangent1End: CGPoint(x: box.maxX, y: box.maxY), tangent2End: CGPoint(x: box.midX, y: box.maxY), radius: r)
        path.addArc(tangent1End: CGPoint(x: box.minX, y: box.maxY), tangent2End: CGPoint(x: box.minX, y: box.midY), radius: r)
        path.addArc(tangent1End: CGPoint(x: box.minX, y: box.minY), tangent2End: CGPoint(x: box.minX + r, y: box.minY), radius: r)
        path.closeSubpath()
        let shape = SKShapeNode(path: path)
        shape.fillColor = look.fill
        shape.strokeColor = look.stroke
        shape.lineWidth = 1
        shape.isAntialiased = true
        return shape
    }

    /// A puffy pastel sticker: thick white border, a faint edge and shadow so it holds up on any background, a
    /// little shine, and two soft dots leading down to the pet instead of a pointed tail.
    private static func sticker(size: CGSize, tailRight: Bool) -> SKNode {
        let node = SKNode()
        let lift: CGFloat = 9
        let minX = tailRight ? 14 - size.width : -14
        let box = CGRect(x: minX, y: lift, width: size.width, height: size.height)
        let r = min(13, size.height / 2)
        let dir: CGFloat = tailRight ? -1 : 1
        let parts: [CGPath] = [
            CGPath(roundedRect: box, cornerWidth: r, cornerHeight: r, transform: nil),
            CGPath(ellipseIn: CGRect(x: dir * 1.5 - 3.2, y: lift - 6.4, width: 6.4, height: 6.4), transform: nil),
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
        layer(tint, .white, 2.6, z: -0.1)                                              // the sticker
        let shine = SKShapeNode(ellipseOf: CGSize(width: min(12, size.width * 0.3), height: 3))
        shine.fillColor = NSColor(white: 1, alpha: 0.65)
        shine.strokeColor = .clear
        shine.position = CGPoint(x: box.minX + r + 3, y: box.maxY - 4.5)
        shine.zPosition = 0
        node.addChild(shine)
        return node
    }

    /// The bubble body for a drawn style, with its tail tip on the origin.
    private static func body(size: CGSize, tailRight: Bool, style: BubbleStyle) -> SKNode {
        if style == .sticker { return sticker(size: size, tailRight: tailRight) }
        return capsule(size: size, tailRight: tailRight, look: style == .dark ? .dark : .light, pixel: style == .pixel)
    }

    /// Where the body's box starts and how far it's lifted off the origin, to place things inside it.
    private static func inset(_ style: BubbleStyle, width: CGFloat, tailRight: Bool) -> (minX: CGFloat, lift: CGFloat) {
        style == .sticker ? (tailRight ? 14 - width : -14, 9) : (tailRight ? 12 - width : -12, 5)
    }

    private static func bubbleLabel(_ text: String, color: NSColor, outlined: Bool) -> SKLabelNode {
        let font = Self.font(bubbleFont, bump: outlined ? 1 : 0)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let label = SKLabelNode(attributedText: NSAttributedString(string: text, attributes: attributes))
        label.numberOfLines = 2
        label.preferredMaxLayoutWidth = 104
        label.lineBreakMode = .byWordWrapping
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.zPosition = 1
        if outlined {
            // Dark copies just behind it, so the words read on any wallpaper or window.
            attributes[.foregroundColor] = NSColor(white: 0.08, alpha: 0.9)
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1), (-0.7, -0.7), (0.7, 0.7), (-0.7, 0.7), (0.7, -0.7)] as [(CGFloat, CGFloat)] {
                let edge = SKLabelNode(attributedText: NSAttributedString(string: text, attributes: attributes))
                edge.numberOfLines = 2
                edge.preferredMaxLayoutWidth = 104
                edge.lineBreakMode = .byWordWrapping
                edge.horizontalAlignmentMode = .center
                edge.verticalAlignmentMode = .center
                edge.position = CGPoint(x: dx, y: dy)
                edge.zPosition = -1
                label.addChild(edge)
            }
        }
        return label
    }

    /// The drawn styles: a shape fitted to the text, the words alone, or just the icon.
    private static func drawnBubble(_ text: String, icon: String?, tailRight: Bool, style: BubbleStyle) -> SKNode {
        let container = SKNode()
        let accent = icon.flatMap { bubbleTexture("accents/\($0).png") }
        if style == .icon, let accent {
            let d: CGFloat = 24
            let at = inset(.pill, width: d, tailRight: tailRight)
            let a = SKSpriteNode(texture: accent, size: CGSize(width: 15, height: 15))
            a.position = CGPoint(x: at.minX + d / 2, y: at.lift + d / 2)
            a.zPosition = 1
            container.addChild(body(size: CGSize(width: d, height: d), tailRight: tailRight, style: .pill))
            container.addChild(a)
            return container
        }
        let ink: NSColor = style == .text ? .white : style == .dark ? BubbleLook.dark.ink : plum
        let label = bubbleLabel(text, color: ink, outlined: style == .text)
        let textSize = label.frame.size
        if style == .text {
            label.position = CGPoint(x: 0, y: 4 + textSize.height / 2)
            container.addChild(label)
            return container
        }
        let roomy = style == .sticker
        let iconWidth: CGFloat = accent == nil ? 0 : 15
        let pad: CGFloat = roomy ? 10 : 8
        let size = CGSize(width: ceil(textSize.width) + iconWidth + pad * 2, height: ceil(textSize.height) + (roomy ? 12 : 9))
        let at = inset(style, width: size.width, tailRight: tailRight)
        container.addChild(body(size: size, tailRight: tailRight, style: style))
        label.position = CGPoint(x: at.minX + pad + iconWidth + textSize.width / 2, y: at.lift + size.height / 2)
        container.addChild(label)
        if let accent {
            let a = SKSpriteNode(texture: accent, size: CGSize(width: 13, height: 13))
            a.position = CGPoint(x: at.minX + pad + 5, y: at.lift + size.height / 2)
            a.zPosition = 1
            container.addChild(a)
        }
        return container
    }

    /// A speech or thought bubble with live text above the pet, its tail pointing at the pet.
    /// `tailRight` puts the tail on the right so the bubble opens to the left (for a pet near the right edge).
    /// Returns false when the artwork isn't bundled, so callers can fall back.
    @discardableResult
    static func say(_ text: String, bubble: SpeechLibrary.Bubble, icon: String?, tailRight: Bool,
                    on node: SKNode, height: CGFloat, delay: TimeInterval = 0) -> Bool {
        if bubbleStyle != .classic {
            let container = drawnBubble(text, icon: icon, tailRight: tailRight, style: bubbleStyle)
            container.position = CGPoint(x: 0, y: height + 2)
            container.zPosition = 50
            container.alpha = 0
            container.setScale(0.85)
            container.name = bubbleName
            node.addChild(container)
            // The sticker pops in with a little bounce.
            let appear: SKAction = bubbleStyle == .sticker
                ? .group([.fadeIn(withDuration: 0.12), .sequence([.scale(to: 1.1, duration: 0.14), .scale(to: 1, duration: 0.1)])])
                : .group([.fadeIn(withDuration: 0.2), .scale(to: 1, duration: 0.2)])
            if bubbleStyle == .sticker { container.setScale(0.6) }
            container.run(.sequence([
                .wait(forDuration: delay),
                replaceOtherBubbles(container, on: node),
                appear,
                .wait(forDuration: 2.4),
                .fadeOut(withDuration: 0.32),
                .removeFromParent(),
            ]))
            return true
        }
        let name = "\(bubble.rawValue)-\(tailRight ? "right" : "left")"
        guard let geo = bubbleGeometry[name], let tex = bubbleTexture("bubbles/\(name).png") else { return false }
        let s: CGFloat = 0.6
        let w = geo.width * s, h = geo.height * s
        let container = SKNode()
        container.addChild(SKSpriteNode(texture: tex, size: CGSize(width: w, height: h)))

        let label = SKLabelNode(text: text)
        let face = font(bubbleFont, bump: 1)
        label.fontName = face.fontName
        label.fontSize = face.pointSize
        label.fontColor = bubbleInk
        label.numberOfLines = 2
        label.preferredMaxLayoutWidth = geo.textBox.width * s
        label.lineBreakMode = .byWordWrapping
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: (geo.textBox.x + geo.textBox.width / 2) * s - w / 2,
                                 y: h / 2 - (geo.textBox.y + geo.textBox.height / 2) * s)
        label.zPosition = 1
        container.addChild(label)

        if let icon, let accent = bubbleTexture("accents/\(icon).png") {
            let a = SKSpriteNode(texture: accent, size: CGSize(width: 18, height: 18))
            a.position = CGPoint(x: tailRight ? -w / 2 + 6 : w / 2 - 6, y: h / 2 - 4)
            a.zPosition = 2
            container.addChild(a)
        }

        // Put the tail tip just above the pet's head (the container is drawn at `bubbleScale`).
        let tip = CGPoint(x: geo.tailTip.x * s - w / 2, y: h / 2 - geo.tailTip.y * s)
        container.position = CGPoint(x: -tip.x * bubbleScale, y: height + 2 - tip.y * bubbleScale)
        container.zPosition = 50
        container.alpha = 0
        container.setScale(bubbleScale * 0.85)
        node.addChild(container)
        container.name = bubbleName
        container.run(.sequence([
            .wait(forDuration: delay),
            replaceOtherBubbles(container, on: node),
            .group([.fadeIn(withDuration: 0.2), .scale(to: bubbleScale, duration: 0.2)]),
            .wait(forDuration: 2.4),
            .fadeOut(withDuration: 0.32),
            .removeFromParent(),
        ]))
        return true
    }

    /// Doodle thought bubble with an icon inside (mood bubbles). Falls back to the text bubble.
    static func thought(icon: String, fallback: String, on node: SKNode, height: CGFloat) {
        if bubbleStyle != .classic, let inner = Doodles.texture(icon) {
            // The same need icon in a small round bubble (or alone, for the words-only style).
            let container = SKNode()
            let d: CGFloat = bubbleStyle == .sticker ? 28 : 26
            let at = inset(bubbleStyle, width: d, tailRight: false)
            if bubbleStyle != .text {
                container.addChild(body(size: CGSize(width: d, height: d), tailRight: false,
                                        style: bubbleStyle == .icon ? .pill : bubbleStyle))
            }
            let symbol = SKSpriteNode(texture: inner, size: CGSize(width: 16, height: 16))
            symbol.position = CGPoint(x: at.minX + d / 2, y: at.lift + d / 2)
            symbol.zPosition = 1
            container.addChild(symbol)
            show(container, on: node, at: CGPoint(x: 0, y: height + 2), delay: 0)
            return
        }
        guard let cloud = Doodles.texture("thought"), let inner = Doodles.texture(icon) else {
            speech(fallback, on: node, height: height, thought: true)
            return
        }
        let bubble = SKSpriteNode(texture: cloud, size: CGSize(width: 44, height: 44))
        let symbol = SKSpriteNode(texture: inner, size: CGSize(width: 18, height: 18))
        symbol.position = CGPoint(x: 0, y: 5)
        symbol.zPosition = 1
        bubble.addChild(symbol)
        show(bubble, on: node, at: CGPoint(x: 0, y: height + 25), delay: 0)
    }

    private static func show(_ bubble: SKNode, on node: SKNode, at position: CGPoint, delay: TimeInterval) {
        bubble.position = position
        bubble.zPosition = 50
        bubble.alpha = 0
        bubble.name = bubbleName
        node.addChild(bubble)
        bubble.run(.sequence([
            .wait(forDuration: delay),
            replaceOtherBubbles(bubble, on: node),
            .fadeIn(withDuration: 0.15),
            .wait(forDuration: 1.6),
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
        bubble.name = bubbleName
        node.addChild(bubble)
        bubble.run(.sequence([
            .wait(forDuration: delay),
            replaceOtherBubbles(bubble, on: node),
            .fadeIn(withDuration: 0.15),
            .wait(forDuration: 1.6),
            .fadeOut(withDuration: 0.15),
            .removeFromParent(),
        ]))
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
