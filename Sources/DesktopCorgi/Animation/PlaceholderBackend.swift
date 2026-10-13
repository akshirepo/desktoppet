#if canImport(AppKit)
import AppKit
import CorgiCore
import SpriteKit

private func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

private enum Palette {
    static let fur = rgb(0xF2A541)
    static let furFar = rgb(0xE0923A)
    static let furLine = rgb(0xC47A26)
    static let furLight = rgb(0xFFD27F, 0.6)
    static let cream = rgb(0xFFF6EA)
    static let earPink = rgb(0xFFC2C7)
    static let blush = rgb(0xFF8FA3, 0.7)
    static let ink = rgb(0x2B1B12)
    static let tongue = rgb(0xFF7F9A)
    static let tongueLine = rgb(0xE0566F)
    static let collar = rgb(0x4FB3D9)
    static let gold = rgb(0xFFD34D)
    static let goldLine = rgb(0xD9A520)
    static let sweat = rgb(0x8FD3FF)
}

private enum EyeStyle { case open, sparkle, closed, happy, squint, wobbly, wide, half }
private enum MouthStyle { case smile, tongue, open, bigOpen, wavy, tiny, none }

// MARK: - Shape helpers

private func fillShape(_ s: SKShapeNode, _ fill: NSColor, stroke: NSColor?, width: CGFloat) -> SKShapeNode {
    s.fillColor = fill
    s.strokeColor = stroke ?? .clear
    s.lineWidth = stroke == nil ? 0 : width
    s.isAntialiased = true
    return s
}

private func ell(_ w: CGFloat, _ h: CGFloat, _ fill: NSColor, at p: CGPoint = .zero,
                 stroke: NSColor? = nil, width: CGFloat = 1.3, rot: CGFloat = 0) -> SKShapeNode {
    let s = fillShape(SKShapeNode(ellipseOf: CGSize(width: w, height: h)), fill, stroke: stroke, width: width)
    s.position = p
    s.zRotation = rot
    return s
}

private func rrect(_ r: CGRect, _ corner: CGFloat, _ fill: NSColor, stroke: NSColor? = nil,
                   width: CGFloat = 1.3) -> SKShapeNode {
    fillShape(SKShapeNode(rect: r, cornerRadius: min(corner, min(r.width, r.height) / 2)), fill, stroke: stroke, width: width)
}

private func shape(_ fill: NSColor, stroke: NSColor? = nil, width: CGFloat = 1.3,
                   _ build: (CGMutablePath) -> Void) -> SKShapeNode {
    let p = CGMutablePath()
    build(p)
    p.closeSubpath()
    return fillShape(SKShapeNode(path: p), fill, stroke: stroke, width: width)
}

private func line(_ color: NSColor, _ width: CGFloat, _ build: (CGMutablePath) -> Void) -> SKShapeNode {
    let p = CGMutablePath()
    build(p)
    let s = SKShapeNode(path: p)
    s.fillColor = .clear
    s.strokeColor = color
    s.lineWidth = width
    s.lineCap = .round
    s.lineJoin = .round
    s.isAntialiased = true
    return s
}

private func star(_ r: CGFloat, _ color: NSColor, at p: CGPoint = .zero) -> SKShapeNode {
    let s = shape(color) { path in
        for i in 0..<8 {
            let a = CGFloat(i) * .pi / 4 + .pi / 2
            let rr = i % 2 == 0 ? r : r * 0.32
            let pt = CGPoint(x: cos(a) * rr, y: sin(a) * rr)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
    }
    s.position = p
    return s
}

private func ease(_ a: SKAction) -> SKAction {
    a.timingMode = .easeInEaseOut
    return a
}

private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

/// Code-drawn "chibi bean" corgi used until an asset pack is installed. Faces right by default.
/// Origin is the feet. Huge round head, tiny loaf body, stubby paws.
final class PlaceholderBackend: AnimationBackend {
    let node = SKNode()
    let size = CGSize(width: 96, height: 80)
    var drawsProps: Bool { true }
    var mouthPoint: CGPoint { CGPoint(x: 35, y: 35) }

    // Tree: node > squash > figure (facing) > pose > parts.
    private let squash = SKNode()
    private let figure = SKNode()
    private let shadow = ell(62, 7, NSColor(white: 0, alpha: 0.16), at: pt(-4, 0))
    private let pose = SKNode()
    private let props = SKNode()
    private let tailBase = SKNode()
    private let tailWag = SKNode()
    private let backNear = SKNode(), backFar = SKNode(), frontNear = SKNode(), frontFar = SKNode()
    private let body = SKNode()
    private let bodyInner = SKNode()
    private let chestBlaze = ell(14, 22, Palette.cream, at: pt(18, -3))
    private let collar = SKNode()
    private let tagPill = SKNode()
    private let tagLabel = SKLabelNode()
    private let headAnchor = SKNode()
    private let headBreath = SKNode()
    private let headTilt = SKNode()
    private let head = SKNode()
    private let earBack = SKNode(), earFront = SKNode()
    private let earBackTwitch = SKNode(), earFrontTwitch = SKNode()
    private var earInners: [SKNode] = []
    private var faceParts: [SKNode] = []
    private let face = SKNode()
    private let eyes = SKNode()
    private let eyeL = SKNode(), eyeR = SKNode()
    private let mouth = SKNode()
    private let blushL = ell(9, 5.5, Palette.blush, at: pt(-14, -6))
    private let blushR = ell(7, 4.5, Palette.blush, at: pt(23, -5))
    private let sweat = SKNode()
    private let headBubbles = SKNode()
    private let headphones = SKNode()
    private let hatNode = SKNode()

    private var facingRight = true
    private var eyeStyle: EyeStyle = .open
    private var happy = false
    private var hovering = false
    private var current: AnimState = .idle
    /// Rest transform of every node a pose may move: position, rotation, z.
    private var rest: [(SKNode, CGPoint, CGFloat, CGFloat)] = []

    init() {
        node.addChild(squash)
        squash.addChild(figure)
        shadow.zPosition = -10
        figure.addChild(shadow)
        figure.addChild(pose)
        figure.addChild(props)
        buildTail()
        buildLegs()
        buildBody()
        buildHead()
        for n: SKNode in [pose, tailBase, backNear, backFar, frontNear, frontFar, body, collar, tagPill,
                          headAnchor, earBack, earFront, mouth, eyes] {
            rest.append((n, n.position, n.zRotation, n.zPosition))
        }
        startLife()
        setName(PetProfile.defaultName)
        play(.idle)
    }

    // MARK: - Building

    private func buildTail() {
        tailBase.position = pt(-27, 24)
        tailBase.zRotation = 0.3
        tailBase.zPosition = 1
        pose.addChild(tailBase)
        tailBase.addChild(tailWag)
        tailWag.addChild(ell(18, 12, Palette.fur, at: pt(-6, 2), stroke: Palette.furLine, rot: 0.3))
        tailWag.addChild(ell(10, 9, Palette.cream, at: pt(-13, 5), rot: 0.3))
    }

    private func buildLegs() {
        let spots: [(SKNode, CGFloat, NSColor, CGFloat)] = [
            (backFar, -14, Palette.furFar, 2), (frontFar, 14, Palette.furFar, 2),
            (backNear, -22, Palette.fur, 2.5), (frontNear, 5, Palette.fur, 2.5),
        ]
        for (leg, x, color, z) in spots {
            leg.position = pt(x, 10)
            leg.zPosition = z
            leg.addChild(rrect(CGRect(x: -4.5, y: -10, width: 9, height: 13), 4.5, color, stroke: Palette.furLine))
            leg.addChild(ell(8, 4, Palette.cream, at: pt(0, -7.6)))
            pose.addChild(leg)
        }
    }

    private func buildBody() {
        body.position = pt(-6, 20)
        body.zPosition = 3
        pose.addChild(body)
        body.addChild(bodyInner)
        bodyInner.addChild(rrect(CGRect(x: -25, y: -15, width: 50, height: 30), 15, Palette.fur, stroke: Palette.furLine))
        bodyInner.addChild(ell(38, 11, Palette.cream, at: pt(1, -9.5)))
        bodyInner.addChild(ell(22, 9, Palette.furLight, at: pt(-8, 8), rot: 0.15))
        bodyInner.addChild(chestBlaze)

        // Collar sits under the head; the name tag hangs on the chest.
        collar.zPosition = 1.5
        body.addChild(collar)
        collar.addChild(line(Palette.collar, 3.5) { p in
            p.move(to: pt(13, 10))
            p.addQuadCurve(to: pt(32, 8), control: pt(23, 0))
        })
        collar.addChild(ell(5, 5, Palette.gold, at: pt(23, 3), stroke: Palette.goldLine, width: 1))
        tagPill.position = pt(23, -4.5)
        tagPill.zPosition = 1.6
        body.addChild(tagPill)
        tagLabel.fontName = "AvenirNext-Bold"
        tagLabel.fontSize = 7
        tagLabel.fontColor = Palette.ink
        tagLabel.verticalAlignmentMode = .center
        tagLabel.horizontalAlignmentMode = .center
        tagLabel.zPosition = 0.2
    }

    private func buildHead() {
        headAnchor.position = pt(20, 46)
        headAnchor.zPosition = 5
        pose.addChild(headAnchor)
        headAnchor.addChild(headBreath)
        headBreath.addChild(headTilt)
        headTilt.addChild(head)

        for (ear, twitch, p, r) in [(earBack, earBackTwitch, pt(-13, 14), CGFloat(0.35)),
                                    (earFront, earFrontTwitch, pt(7, 16), CGFloat(-0.2))] {
            ear.position = p
            ear.zRotation = r
            ear.zPosition = -1
            head.addChild(ear)
            ear.addChild(twitch)
            twitch.addChild(shape(Palette.fur, stroke: Palette.furLine) { path in
                path.move(to: pt(-7.5, 0))
                path.addQuadCurve(to: pt(0, 18), control: pt(-6.5, 12))
                path.addQuadCurve(to: pt(8, 0), control: pt(6.5, 11))
            })
            let inner = shape(Palette.earPink) { path in
                path.move(to: pt(-4, 1.5))
                path.addQuadCurve(to: pt(0, 13), control: pt(-3.5, 9))
                path.addQuadCurve(to: pt(4.5, 1.5), control: pt(3.5, 8))
            }
            inner.zPosition = 0.1
            twitch.addChild(inner)
            earInners.append(inner)
        }

        head.addChild(ell(52, 46, Palette.fur, stroke: Palette.furLine))
        let shine = ell(18, 9, Palette.furLight, at: pt(-10, 13), rot: 0.4)
        let blaze = ell(7, 17, Palette.cream, at: pt(5, 11))
        let muzzle = ell(27, 17, Palette.cream, at: pt(12, -8))
        for (i, n) in [shine, blaze, muzzle, blushL, blushR].enumerated() {
            n.zPosition = 0.1 + CGFloat(i) * 0.1
            head.addChild(n)
        }
        faceParts = [blaze, muzzle, blushL, blushR, face]

        face.zPosition = 1
        head.addChild(face)
        eyes.position = pt(0, 3)
        face.addChild(eyes)
        eyeL.position = pt(-5, 0)
        eyeR.position = pt(15, 0)
        eyes.addChild(eyeL)
        eyes.addChild(eyeR)
        let nose = ell(7.5, 5, Palette.ink, at: pt(13, -2.5))
        nose.addChild(ell(2.4, 1.4, NSColor(white: 1, alpha: 0.8), at: pt(-1, 1)))
        face.addChild(nose)
        mouth.position = pt(13, -6.5)
        face.addChild(mouth)

        sweat.position = pt(-21, 12)
        sweat.zPosition = 2
        sweat.addChild(shape(Palette.sweat, stroke: rgb(0x4FA3D9), width: 1) { p in
            p.move(to: pt(0, 6))
            p.addQuadCurve(to: pt(0, -3), control: pt(-5, -3))
            p.addQuadCurve(to: pt(0, 6), control: pt(5, -3))
        })
        head.addChild(sweat)

        headBubbles.zPosition = 3
        for (x, y, r) in [(-8.0, 22.0, 4.5), (2.0, 25.0, 3.5), (-16.0, 17.0, 3.0), (9.0, 21.0, 2.5)] {
            headBubbles.addChild(ell(r * 2, r * 2, NSColor(white: 1, alpha: 0.92), at: pt(x, y),
                                     stroke: rgb(0x9FD8F0), width: 1))
        }
        head.addChild(headBubbles)

        buildHeadphones()
        headphones.zPosition = 2.5
        head.addChild(headphones)
        hatNode.position = pt(1, 20)
        hatNode.zPosition = 10
        head.addChild(hatNode)
    }

    private func buildHeadphones() {
        headphones.addChild(line(rgb(0x555566), 3.2) { p in
            p.move(to: pt(-21, 3))
            p.addQuadCurve(to: pt(21, 6), control: pt(-2, 48))
        })
        let far = rrect(CGRect(x: 17, y: -2, width: 7, height: 11), 3.5, rgb(0xFF6F91), stroke: rgb(0xD94C73), width: 1)
        far.zPosition = -3
        headphones.addChild(far)
        headphones.addChild(rrect(CGRect(x: -26, y: -6, width: 9, height: 14), 4.5, rgb(0xFF6F91),
                                  stroke: rgb(0xD94C73), width: 1))
    }

    // MARK: - Expressions

    private func setEyes(_ style: EyeStyle) {
        eyeStyle = style
        eyes.removeAction(forKey: "blinkAnim")
        eyes.yScale = 1
        for (eye, far) in [(eyeL, false), (eyeR, true)] {
            eye.removeAllChildren()
            eye.removeAllActions()
            eye.setScale(1)
            drawEye(style, into: eye, r: far ? 5 : 5.8, mirrored: far)
        }
    }

    private func drawEye(_ style: EyeStyle, into eye: SKNode, r: CGFloat, mirrored: Bool) {
        let white = NSColor.white
        switch style {
        case .open, .half:
            eye.addChild(ell(2 * r, 2 * r, Palette.ink))
            eye.addChild(ell(r * 0.8, r * 0.8, white, at: pt(r * 0.3, r * 0.35)))
            eye.addChild(ell(r * 0.38, r * 0.38, white, at: pt(-r * 0.38, -r * 0.32)))
            if style == .half {
                let lid = shape(Palette.fur) { p in
                    p.move(to: pt(-r - 1, r * 0.05))
                    p.addLine(to: pt(-r - 1, r + 1))
                    p.addLine(to: pt(r + 1, r + 1))
                    p.addLine(to: pt(r + 1, r * 0.05))
                }
                lid.zPosition = 0.5
                eye.addChild(lid)
                let edge = line(Palette.ink, 1.6) { p in
                    p.move(to: pt(-r, r * 0.05))
                    p.addQuadCurve(to: pt(r, r * 0.05), control: pt(0, -r * 0.2))
                }
                edge.zPosition = 0.6
                eye.addChild(edge)
            }
        case .sparkle:
            eye.addChild(ell(2.15 * r, 2.15 * r, Palette.ink))
            eye.addChild(star(r * 0.75, white, at: pt(r * 0.25, r * 0.3)))
            eye.addChild(ell(r * 0.36, r * 0.36, white, at: pt(-r * 0.42, -r * 0.38)))
        case .closed:
            eye.addChild(line(Palette.ink, 2.2) { p in
                p.move(to: pt(-r, 0.5))
                p.addQuadCurve(to: pt(r, 0.5), control: pt(0, -r * 0.9))
            })
        case .happy:
            eye.addChild(line(Palette.ink, 2.2) { p in
                p.move(to: pt(-r, -1.5))
                p.addQuadCurve(to: pt(r, -1.5), control: pt(0, r * 1.2))
            })
        case .squint:
            let s: CGFloat = mirrored ? -1 : 1
            eye.addChild(line(Palette.ink, 2.2) { p in
                p.move(to: pt(-s * r * 0.7, r * 0.65))
                p.addLine(to: pt(s * r * 0.6, 0))
                p.addLine(to: pt(-s * r * 0.7, -r * 0.65))
            })
        case .wobbly:
            eye.addChild(ell(2.1 * r, 2.1 * r, white, stroke: Palette.ink, width: 1.4))
            let pupil = ell(r * 0.85, r * 0.85, Palette.ink)
            eye.addChild(pupil)
            let circle = CGPath(ellipseIn: CGRect(x: -r * 0.4, y: -r * 0.4, width: r * 0.8, height: r * 0.8), transform: nil)
            pupil.run(.repeatForever(.follow(circle, asOffset: false, orientToPath: false,
                                             duration: mirrored ? 0.45 : 0.38)))
            eye.run(.repeatForever(.sequence([.scaleX(to: 1.1, y: 0.92, duration: 0.12),
                                              .scaleX(to: 0.94, y: 1.06, duration: 0.12)])))
        case .wide:
            eye.addChild(ell(2.2 * r, 2.2 * r, white, stroke: Palette.ink, width: 1.4))
            eye.addChild(ell(r * 1.15, r * 1.15, Palette.ink, at: pt(r * 0.15, 0)))
            eye.addChild(ell(r * 0.4, r * 0.4, white, at: pt(r * 0.35, r * 0.25)))
        }
    }

    private func setMouth(_ style: MouthStyle) {
        mouth.removeAllChildren()
        mouth.removeAction(forKey: "pose")
        mouth.setScale(1)
        let ink = Palette.ink
        switch style {
        case .smile, .tongue:
            if style == .tongue {
                let t = ell(5.5, 7, Palette.tongue, at: pt(0.5, -3.8), stroke: Palette.tongueLine, width: 0.8)
                t.zPosition = -0.1
                t.addChild(line(Palette.tongueLine, 0.8) { p in
                    p.move(to: pt(0, 2))
                    p.addLine(to: pt(0, -1.5))
                })
                mouth.addChild(t)
            }
            mouth.addChild(line(ink, 1.6) { p in
                p.move(to: pt(-5, 0))
                p.addQuadCurve(to: pt(0, 0), control: pt(-2.5, -3))
                p.addQuadCurve(to: pt(5, 0), control: pt(2.5, -3))
            })
        case .open:
            mouth.addChild(ell(8, 7, ink, at: pt(0, -2.5)))
            mouth.addChild(ell(5, 3, Palette.tongue, at: pt(0, -4.4)))
        case .bigOpen:
            mouth.addChild(ell(10, 11, ink, at: pt(0, -4)))
            mouth.addChild(ell(7, 4, Palette.tongue, at: pt(0, -7.5)))
        case .wavy:
            mouth.addChild(line(ink, 1.5) { p in
                p.move(to: pt(-5, -1))
                p.addLine(to: pt(-2.5, 0.5))
                p.addLine(to: pt(0, -1))
                p.addLine(to: pt(2.5, 0.5))
                p.addLine(to: pt(5, -1))
            })
        case .tiny:
            mouth.addChild(line(ink, 1.4) { p in
                p.move(to: pt(-2, -0.5))
                p.addQuadCurve(to: pt(2, -0.5), control: pt(0, -2))
            })
        case .none:
            break
        }
    }

    // MARK: - Constant small life

    private func startLife() {
        node.run(.repeatForever(.sequence([.wait(forDuration: 4.5, withRange: 3),
                                           .run { [weak self] in self?.blink() }])), withKey: "blink")
        node.run(.repeatForever(.sequence([.wait(forDuration: 8, withRange: 6),
                                           .run { [weak self] in self?.twitchEar() }])), withKey: "twitch")
        bodyInner.run(.repeatForever(.sequence([ease(.scaleY(to: 1.04, duration: 1.4)),
                                                ease(.scaleY(to: 1, duration: 1.4))])), withKey: "breath")
        headBreath.run(.repeatForever(.sequence([ease(.move(to: pt(0, 1.2), duration: 1.4)),
                                                 ease(.move(to: .zero, duration: 1.4))])), withKey: "breath")
        startWag()
    }

    private func blink() {
        guard [.open, .sparkle, .wide, .half].contains(eyeStyle) else { return }
        eyes.run(.sequence([.scaleY(to: 0.1, duration: 0.07), .wait(forDuration: 0.06),
                            .scaleY(to: 1, duration: 0.08)]), withKey: "blinkAnim")
    }

    private func twitchEar() {
        let back = Bool.random()
        let ear = back ? earBackTwitch : earFrontTwitch
        let a: CGFloat = back ? 0.3 : -0.3
        ear.run(.sequence([.rotate(toAngle: a, duration: 0.08), .rotate(toAngle: 0, duration: 0.1),
                           .rotate(toAngle: a * 0.6, duration: 0.07), .rotate(toAngle: 0, duration: 0.1)]),
                withKey: "twitch")
    }

    private func startWag() {
        let d = happy ? 0.11 : 0.24
        tailWag.run(.repeatForever(.sequence([ease(.rotate(toAngle: 0.35, duration: d)),
                                              ease(.rotate(toAngle: -0.25, duration: d))])), withKey: "wag")
    }

    // MARK: - AnimationBackend

    func setFacing(right: Bool) {
        facingRight = right
        figure.xScale = right ? 1 : -1
        tagPill.xScale = right ? 1 : -1
    }

    func setHappy(_ happy: Bool) {
        guard happy != self.happy else { return }
        self.happy = happy
        startWag()
    }

    func setHovering(_ hovering: Bool) {
        guard hovering != self.hovering else { return }
        self.hovering = hovering
        headTilt.run(ease(.rotate(toAngle: hovering ? 0.2 : 0, duration: 0.25)), withKey: "tilt")
    }

    func setName(_ name: String) {
        tagPill.removeAllChildren()
        tagLabel.removeFromParent()
        tagLabel.text = PetProfile.tagText(for: name)
        let w = max(14, tagLabel.frame.width + 7)
        tagPill.addChild(rrect(CGRect(x: -w / 2, y: -5, width: w, height: 10), 5, Palette.cream,
                               stroke: Palette.goldLine, width: 1))
        tagPill.addChild(tagLabel)
    }

    func setHat(_ hat: Hat) {
        hatNode.removeAllChildren()
        hatNode.zRotation = 0
        switch hat {
        case .none: break
        case .bow: hatNode.addChild(makeBow())
        case .partyHat: hatNode.addChild(makePartyHat())
        case .beanie: hatNode.addChild(makeBeanie())
        case .flowerCrown: hatNode.addChild(makeFlowerCrown())
        case .santaHat: hatNode.addChild(makeSantaHat())
        }
    }

    // MARK: - Hats (hatNode sits on top of the skull)

    private func makeBow() -> SKNode {
        let n = SKNode()
        n.position = pt(-7, 1)
        n.zRotation = 0.3
        let pink = rgb(0xFF6F91), dark = rgb(0xD94C73)
        for s: CGFloat in [-1, 1] {
            n.addChild(shape(pink, stroke: dark, width: 1) { p in
                p.move(to: .zero)
                p.addQuadCurve(to: pt(s * 9, 5.5), control: pt(s * 4, 6))
                p.addQuadCurve(to: pt(s * 9, -5.5), control: pt(s * 11, 0))
                p.addQuadCurve(to: .zero, control: pt(s * 4, -6))
            })
        }
        n.addChild(ell(5, 5, dark))
        return n
    }

    private func makePartyHat() -> SKNode {
        let n = SKNode()
        n.position = pt(2, -1)
        n.zRotation = -0.18
        n.addChild(shape(rgb(0x7BDFF2), stroke: rgb(0x3BAFD0), width: 1) { p in
            p.move(to: pt(-8.5, 0))
            p.addLine(to: pt(0, 22))
            p.addLine(to: pt(8.5, 0))
            p.addQuadCurve(to: pt(-8.5, 0), control: pt(0, -3))
        })
        for (a, b) in [(pt(-6, 6), pt(6, 9)), (pt(-3.5, 13), pt(3.5, 15))] {
            n.addChild(line(rgb(0xFF6F91), 1.6) { p in
                p.move(to: a)
                p.addLine(to: b)
            })
        }
        n.addChild(ell(6.5, 6.5, Palette.gold, at: pt(0, 22), stroke: Palette.goldLine, width: 1))
        return n
    }

    private func makeBeanie() -> SKNode {
        let n = SKNode()
        n.position = pt(-1, -2)
        let main = rgb(0x9B8AE0), dark = rgb(0x6E5BC4)
        n.addChild(shape(main, stroke: dark, width: 1) { p in
            p.move(to: pt(-17, 0))
            p.addCurve(to: pt(17, 0), control1: pt(-16, 20), control2: pt(16, 20))
        })
        for x: CGFloat in [-8, 0, 8] {
            n.addChild(line(rgb(0xB9ADEE), 1) { p in
                p.move(to: pt(x, 1.5))
                p.addLine(to: pt(x * 0.7, 12.5))
            })
        }
        n.addChild(rrect(CGRect(x: -18.5, y: -3, width: 37, height: 6.5), 3.2, rgb(0x7E6BD2), stroke: dark, width: 1))
        n.addChild(ell(9, 9, Palette.cream, at: pt(0, 16), stroke: rgb(0xE6D9C6), width: 1))
        return n
    }

    private func makeFlowerCrown() -> SKNode {
        let n = SKNode()
        let a = pt(-19, -5), c = pt(0, 9), b = pt(19, -5)
        n.addChild(line(rgb(0x6CBF6C), 1.6) { p in
            p.move(to: a)
            p.addQuadCurve(to: b, control: c)
        })
        func bez(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            return pt(u * u * a.x + 2 * u * t * c.x + t * t * b.x, u * u * a.y + 2 * u * t * c.y + t * t * b.y)
        }
        for t: CGFloat in [0.2, 0.4, 0.6, 0.8] {
            n.addChild(ell(5, 2.6, rgb(0x6CBF6C), at: bez(t), rot: t < 0.5 ? 0.6 : -0.6))
        }
        let colors = [rgb(0xFF8FB1), rgb(0xFFFFFF), rgb(0xC9A7FF), rgb(0xFFD166), rgb(0xFF8FB1)]
        for (i, t) in [0.08, 0.3, 0.5, 0.7, 0.92].enumerated() {
            let f = SKNode()
            f.position = bez(CGFloat(t))
            for k in 0..<5 {
                let ang = CGFloat(k) * 2 * .pi / 5
                f.addChild(ell(4.4, 4.4, colors[i], at: pt(cos(ang) * 2.4, sin(ang) * 2.4),
                               stroke: NSColor(white: 0, alpha: 0.12), width: 0.6))
            }
            f.addChild(ell(2.8, 2.8, i == 3 ? rgb(0xFF9F43) : Palette.gold))
            n.addChild(f)
        }
        return n
    }

    private func makeSantaHat() -> SKNode {
        let n = SKNode()
        n.position = pt(0, -1)
        n.addChild(shape(rgb(0xE53945), stroke: rgb(0xB02232), width: 1) { p in
            p.move(to: pt(-14, 2))
            p.addQuadCurve(to: pt(-22, 11), control: pt(-4, 26))
            p.addQuadCurve(to: pt(14, 2), control: pt(8, 22))
        })
        n.addChild(rrect(CGRect(x: -16.5, y: -3, width: 33, height: 7), 3.5, .white, stroke: rgb(0xE6E6E6), width: 1))
        n.addChild(ell(8, 8, .white, at: pt(-22, 11), stroke: rgb(0xE6E6E6), width: 1))
        return n
    }

    // MARK: - Props

    private func makeBook(flat: Bool) -> SKNode {
        let n = SKNode()
        n.zPosition = 7
        let cover = rgb(0x5B8DEF), coverLine = rgb(0x3B6BC9)
        n.addChild(rrect(CGRect(x: -12.5, y: -1, width: 25, height: 16), 2, cover, stroke: coverLine, width: 1))
        for x: CGFloat in [-11, 0.5] {
            n.addChild(rrect(CGRect(x: x, y: 0.5, width: 10.5, height: 13), 1.5, .white))
            for y: CGFloat in [4, 7, 10] {
                n.addChild(line(NSColor(white: 0.75, alpha: 1), 0.8) { p in
                    p.move(to: pt(x + 2, y))
                    p.addLine(to: pt(x + 8.5, y))
                })
            }
        }
        n.addChild(line(coverLine, 1) { p in
            p.move(to: pt(0, 0))
            p.addLine(to: pt(0, 14))
        })
        if flat {
            n.yScale = 0.45
        } else {
            let page = rrect(CGRect(x: 0.5, y: 0.5, width: 10.5, height: 13), 1.5, rgb(0xF4F4F4))
            page.zPosition = 0.5
            page.isHidden = true
            n.addChild(page)
            page.run(.repeatForever(.sequence([
                .wait(forDuration: 4, withRange: 3),
                .run { page.isHidden = false; page.xScale = 1 },
                .scaleX(to: -1, duration: 0.35),
                .run { page.isHidden = true; page.xScale = 1 },
            ])))
        }
        return n
    }

    private func makeTV() -> SKNode {
        let n = SKNode()
        n.zPosition = 1
        let brown = rgb(0xA1887F), dark = rgb(0x6D4C41)
        for x: CGFloat in [-7, 7] {
            n.addChild(line(dark, 1.6) { p in
                p.move(to: pt(x, 4))
                p.addLine(to: pt(x * 1.2, 0))
            })
        }
        for (x, y) in [(-6.0, 28.0), (5.0, 29.0)] {
            n.addChild(line(dark, 1.2) { p in
                p.move(to: pt(0, 20))
                p.addLine(to: pt(x, y))
            })
            n.addChild(ell(2.4, 2.4, rgb(0xFF6F91), at: pt(x, y)))
        }
        n.addChild(rrect(CGRect(x: -12, y: 4, width: 24, height: 17), 3.5, brown, stroke: dark, width: 1.2))
        let screen = rrect(CGRect(x: -9, y: 7, width: 15, height: 11), 2.5, rgb(0x9AD0FF), stroke: dark, width: 1)
        n.addChild(screen)
        n.addChild(ell(2.2, 2.2, dark, at: pt(9, 15)))
        n.addChild(ell(2.2, 2.2, dark, at: pt(9, 10)))
        let colors = [rgb(0x9AD0FF), rgb(0xB8F2C8), rgb(0xFFD6E7), rgb(0xFFF1A8)]
        var i = 0
        n.run(.repeatForever(.sequence([.wait(forDuration: 0.6, withRange: 0.5), .run {
            i = (i + 1) % colors.count
            screen.fillColor = colors[i]
        }])))
        return n
    }

    private func makeBowl() -> SKNode {
        let n = SKNode()
        n.zPosition = 6
        for (x, y) in [(-6.0, 8.5), (-1.0, 9.8), (4.0, 9.2), (8.0, 8.2), (-3.0, 7.5), (2.0, 7.8)] {
            n.addChild(ell(4.6, 4.2, rgb(0x9C6B3E), at: pt(x, y)))
        }
        n.addChild(shape(rgb(0xE8505B), stroke: rgb(0xB8333E), width: 1.2) { p in
            p.move(to: pt(-12, 8))
            p.addQuadCurve(to: pt(12, 8), control: pt(0, -8))
        })
        n.addChild(line(NSColor(white: 1, alpha: 0.6), 1.2) { p in
            p.move(to: pt(-7, 5))
            p.addQuadCurve(to: pt(-1, 3), control: pt(-4, 3))
        })
        return n
    }

    private func makeTub() -> SKNode {
        let n = SKNode()
        n.zPosition = 8
        let blue = rgb(0x9FD8F0), line2 = rgb(0x5AA9CF)
        for x: CGFloat in [-26, 22] { n.addChild(ell(5, 4, line2, at: pt(x, 1.5))) }
        n.addChild(rrect(CGRect(x: -34, y: 2, width: 66, height: 15), 7, blue, stroke: line2))
        n.addChild(rrect(CGRect(x: -37, y: 14.5, width: 72, height: 5), 2.5, rgb(0xE6F6FD), stroke: line2, width: 1))
        for (x, r) in [(-30.0, 4.0), (-22.0, 5.0), (-13.0, 4.0), (-2.0, 4.5), (9.0, 5.0), (19.0, 4.0), (28.0, 4.5)] {
            n.addChild(ell(r * 2, r * 2, NSColor(white: 1, alpha: 0.95), at: pt(x, 20 + CGFloat(r) * 0.3),
                           stroke: blue, width: 1))
        }
        return n
    }

    private func makeBall() -> SKNode {
        let n = SKNode()
        n.zPosition = 6
        n.addChild(ell(12, 12, rgb(0xFF5A5F), stroke: rgb(0xD63B40), width: 1))
        n.addChild(line(.white, 1.4) { p in
            p.move(to: pt(-5, 2))
            p.addQuadCurve(to: pt(5, 2), control: pt(0, -3))
        })
        return n
    }

    /// Spawns a small node at `at` every `every` seconds that floats up and fades.
    private func spawnFloaters(every: TimeInterval, _ make: @escaping () -> SKNode, at: @escaping () -> CGPoint) {
        props.run(.repeatForever(.sequence([.run { [weak self] in
            guard let self else { return }
            let f = make()
            f.position = at()
            f.zPosition = 9
            f.alpha = 0
            self.props.addChild(f)
            f.run(.sequence([.fadeIn(withDuration: 0.15),
                             .group([.moveBy(x: CGFloat.random(in: -4...8), y: 24, duration: 1.3),
                                     .sequence([.wait(forDuration: 0.7), .fadeOut(withDuration: 0.6)])]),
                             .removeFromParent()]))
        }, .wait(forDuration: every)])), withKey: "pose")
    }

    // MARK: - Poses

    private func act(_ n: SKNode, _ a: SKAction) { n.run(a, withKey: "pose") }

    private func place(_ n: SKNode, _ x: CGFloat, _ y: CGFloat, rot: CGFloat? = nil, z: CGFloat? = nil) {
        n.position = pt(x, y)
        if let rot { n.zRotation = rot }
        if let z { n.zPosition = z }
    }

    private func resetPose() {
        for (n, p, r, z) in rest {
            n.removeAction(forKey: "pose")
            n.position = p
            n.zRotation = r
            n.zPosition = z
            n.setScale(1)
            n.isHidden = false
        }
        props.removeAllChildren()
        props.removeAction(forKey: "pose")
        shadow.isHidden = false
        faceParts.forEach { $0.isHidden = false }
        earInners.forEach { $0.isHidden = false }
        chestBlaze.isHidden = false
        sweat.isHidden = true
        headBubbles.isHidden = true
        headphones.isHidden = true
        tailWag.speed = 1
        bodyInner.speed = 1
        headBreath.speed = 1
    }

    private func swing(_ leg: SKNode, _ amp: CGFloat, _ t: TimeInterval, _ phase: Bool) {
        let a = ease(.rotate(toAngle: amp, duration: t)), b = ease(.rotate(toAngle: -amp, duration: t))
        act(leg, .repeatForever(.sequence(phase ? [a, b] : [b, a])))
    }

    private func gait(amp: CGFloat, t: TimeInterval, bob: CGFloat) {
        swing(backNear, amp, t, true)
        swing(frontFar, amp, t, true)
        swing(backFar, amp, t, false)
        swing(frontNear, amp, t, false)
        act(pose, .repeatForever(.sequence([.moveBy(x: 0, y: bob, duration: t), .moveBy(x: 0, y: -bob, duration: t)])))
    }

    private func sitBody() {
        place(body, -8, 25, rot: 0.42)
        body.xScale = 0.92
        place(backNear, -18, 7, rot: 1.45)
        place(backFar, -11, 7, rot: 1.45)
        place(frontNear, 6, 12)
        place(frontFar, 13, 12)
        frontNear.yScale = 1.2
        frontFar.yScale = 1.2
        place(headAnchor, 19, 52)
        place(tailBase, -30, 9, rot: -0.1)
    }

    /// Hanging from the scruff: head on top, body and legs below.
    private func hangBody() {
        shadow.isHidden = true
        place(body, 5, 26, rot: 1.35)
        body.xScale = 0.9
        place(headAnchor, 12, 54, rot: 0.1)
        place(frontNear, 13, 32, rot: 0.1)
        place(frontFar, 18, 33, rot: 0.1)
        place(backNear, 0, 9, rot: -0.1)
        place(backFar, 6, 10, rot: -0.1)
        place(tailBase, -3, 6, rot: -1.2)
    }

    private func flyBody() {
        shadow.isHidden = true
        frontNear.zRotation = 1.2
        frontFar.zRotation = 1.0
        backNear.zRotation = -1.2
        backFar.zRotation = -1.0
        tailBase.zRotation = -0.3
        act(pose, .repeatForever(.sequence([ease(.moveBy(x: 0, y: 3, duration: 0.35)),
                                            ease(.moveBy(x: 0, y: -3, duration: 0.35))])))
        act(earBack, .repeatForever(.sequence([.rotate(toAngle: 0.9, duration: 0.15), .rotate(toAngle: 0.4, duration: 0.15)])))
        act(earFront, .repeatForever(.sequence([.rotate(toAngle: 0.5, duration: 0.15), .rotate(toAngle: 0, duration: 0.15)])))
    }

    func play(_ state: AnimState) {
        current = state
        resetPose()
        setFacing(right: facingRight)
        var eyeChoice: EyeStyle = .open
        var mouthStyle: MouthStyle = .tongue
        switch state {
        case .idle:
            break
        case .walk:
            gait(amp: 0.35, t: 0.14, bob: 1.5)
        case .run:
            gait(amp: 0.7, t: 0.07, bob: 2)
            earBack.zRotation = 0.9
            earFront.zRotation = 0.6
            pose.zRotation = -0.05
            body.xScale = 1.06
            tailBase.zRotation = -0.2
            mouthStyle = .open
        case .roam:
            flyBody()
            eyeChoice = .happy
        case .holdBall:
            flyBody()
            eyeChoice = .sparkle
            mouthStyle = .none
        case .sit:
            sitBody()
        case .sleep:
            [backNear, backFar, frontFar].forEach { $0.isHidden = true }
            place(frontNear, 25, 6, rot: 1.5, z: 7)
            place(body, -6, 12)
            body.yScale = 0.72
            place(headAnchor, 17, 24, rot: -0.18)
            earBack.zRotation = 1.0
            earFront.zRotation = 0.7
            place(tailBase, -30, 7, rot: -0.5)
            tailWag.speed = 0
            bodyInner.speed = 0.5
            headBreath.speed = 0.5
            eyeChoice = .closed
            mouthStyle = .tiny
        case .eat:
            place(headAnchor, 27, 30, rot: -0.4)
            let bowl = makeBowl()
            bowl.position = pt(38, 0)
            props.addChild(bowl)
            act(headAnchor, .repeatForever(.sequence([.moveBy(x: 0, y: -2.5, duration: 0.12),
                                                      .moveBy(x: 0, y: 2.5, duration: 0.12)])))
            tailWag.speed = 1.8
            eyeChoice = .happy
            mouthStyle = .open
        case .beg:
            pose.setScale(0.92)
            place(body, -6, 24, rot: 0.9)
            body.xScale = 0.85
            place(backNear, -6, 7, rot: 1.45)
            place(backFar, 0, 7, rot: 1.45)
            place(frontNear, 12, 38, rot: 1.9, z: 6)
            place(frontFar, 16, 40, rot: 2.0)
            frontNear.yScale = 0.8
            frontFar.yScale = 0.8
            place(headAnchor, 12, 56)
            place(tailBase, -22, 6, rot: 0.2)
            act(frontNear, .repeatForever(.sequence([ease(.rotate(toAngle: 1.6, duration: 0.18)),
                                                     ease(.rotate(toAngle: 2.1, duration: 0.18))])))
            tailWag.speed = 1.8
            eyeChoice = .sparkle
        case .dangle:
            hangBody()
            act(pose, .repeatForever(.sequence([ease(.rotate(toAngle: 0.12, duration: 0.45)),
                                                ease(.rotate(toAngle: -0.12, duration: 0.45))])))
            tailWag.speed = 0.4
            eyeChoice = .half
            mouthStyle = .tiny
        case .scared:
            hangBody()
            for (i, leg) in [frontNear, frontFar, backNear, backFar].enumerated() {
                swing(leg, 0.5, 0.09, i % 2 == 0)
            }
            earBack.zRotation = 0.9
            earFront.zRotation = 0.6
            sweat.isHidden = false
            act(pose, .repeatForever(.sequence([.moveBy(x: 1.2, y: 0, duration: 0.04), .moveBy(x: -1.2, y: 0, duration: 0.04)])))
            tailWag.speed = 0
            eyeChoice = .wobbly
            mouthStyle = .wavy
        case .fall:
            shadow.isHidden = true
            frontNear.zRotation = 0.9
            frontFar.zRotation = 0.6
            backNear.zRotation = -0.9
            backFar.zRotation = -0.6
            pose.yScale = 1.04
            act(earBack, .repeatForever(.sequence([.rotate(toAngle: -0.2, duration: 0.1), .rotate(toAngle: 0.3, duration: 0.1)])))
            act(earFront, .repeatForever(.sequence([.rotate(toAngle: -0.5, duration: 0.1), .rotate(toAngle: 0, duration: 0.1)])))
            eyeChoice = .wide
            mouthStyle = .open
        case .land:
            squash.run(.sequence([.scaleX(to: 1.18, y: 0.8, duration: 0.06),
                                  ease(.scaleX(to: 1, y: 1, duration: 0.2))]), withKey: "squash")
            eyeChoice = .squint
        case .wiggle:
            act(pose, .repeatForever(.sequence([.rotate(toAngle: 0.07, duration: 0.08), .rotate(toAngle: -0.07, duration: 0.08)])))
            act(body, .repeatForever(.sequence([.rotate(toAngle: -0.06, duration: 0.08), .rotate(toAngle: 0.06, duration: 0.08)])))
            tailWag.speed = 2.2
            eyeChoice = .happy
        case .bath:
            [backNear, backFar, frontNear, frontFar].forEach { $0.isHidden = true }
            props.addChild(makeTub())
            headBubbles.isHidden = false
            act(pose, .repeatForever(.sequence([.moveBy(x: 1.5, y: 0, duration: 0.05), .moveBy(x: -1.5, y: 0, duration: 0.05)])))
            spawnFloaters(every: 0.35, {
                ell(5, 5, NSColor(white: 1, alpha: 0.85), stroke: rgb(0x9FD8F0), width: 1)
            }, at: { pt(CGFloat.random(in: -28...28), 22) })
            eyeChoice = .squint
        case .fetch:
            place(frontNear, 5, 5.5)
            place(frontFar, 14, 5.5)
            frontNear.yScale = 0.55
            frontFar.yScale = 0.55
            place(body, -6, 18, rot: -0.22)
            place(headAnchor, 23, 37)
            place(tailBase, -28, 28, rot: 0.9)
            act(pose, .repeatForever(.sequence([ease(.moveBy(x: 2, y: 0, duration: 0.2)),
                                                ease(.moveBy(x: -2, y: 0, duration: 0.2))])))
            tailWag.speed = 2
            eyeChoice = .sparkle
        case .wave:
            sitBody()
            place(frontNear, 12, 28, rot: 2.6, z: 6)
            frontNear.yScale = 1
            act(frontNear, .repeatForever(.sequence([ease(.rotate(toAngle: 2.2, duration: 0.18)),
                                                     ease(.rotate(toAngle: 2.9, duration: 0.18))])))
            tailWag.speed = 1.8
            eyeChoice = .happy
        case .back:
            faceParts.forEach { $0.isHidden = true }
            earInners.forEach { $0.isHidden = true }
            chestBlaze.isHidden = true
            tagPill.isHidden = true
            place(headAnchor, 2, 46)
            place(earBack, -12, 14, rot: 0.25, z: 1)
            place(earFront, 12, 14, rot: -0.25, z: 1)
            place(tailBase, -4, 20, rot: 1.4, z: 9)
        case .read:
            sitBody()
            place(frontNear, 12, 22, rot: 1.25, z: 8)
            place(frontFar, 15, 23, rot: 1.25)
            frontNear.yScale = 1
            frontFar.yScale = 1
            let book = makeBook(flat: false)
            book.position = pt(31, 24)
            book.zRotation = 0.15
            props.addChild(book)
            place(headAnchor, 20, 51, rot: -0.12)
            tailWag.speed = 0.5
            eyeChoice = .half
            mouthStyle = .smile
        case .readSleep:
            sitBody()
            let book = makeBook(flat: true)
            book.position = pt(36, 1)
            props.addChild(book)
            place(headAnchor, 21, 44, rot: -0.35)
            act(headAnchor, .repeatForever(.sequence([ease(.rotate(toAngle: -0.27, duration: 1.6)),
                                                      ease(.rotate(toAngle: -0.35, duration: 1.6))])))
            tailWag.speed = 0
            bodyInner.speed = 0.6
            headBreath.speed = 0.6
            eyeChoice = .closed
            mouthStyle = .tiny
        case .music:
            sitBody()
            headphones.isHidden = false
            act(headAnchor, .repeatForever(.sequence([ease(.rotate(toAngle: 0.1, duration: 0.3)),
                                                      ease(.rotate(toAngle: -0.1, duration: 0.3))])))
            spawnFloaters(every: 0.9, {
                let l = SKLabelNode(text: ["♪", "♫"].randomElement()!)
                l.fontName = "AvenirNext-Bold"
                l.fontSize = 13
                l.fontColor = rgb(0x7E6BD2)
                return l
            }, at: { pt(CGFloat.random(in: 26...36), 62) })
            tailWag.speed = 1.5
            eyeChoice = .happy
        case .watch:
            pose.position = pt(-12, 0)
            place(frontNear, 8, 5, rot: 1.5)
            place(frontFar, 14, 5, rot: 1.5)
            place(backNear, -24, 5, rot: -1.5)
            place(backFar, -17, 5, rot: -1.5)
            place(body, -6, 13)
            body.yScale = 0.8
            place(headAnchor, 18, 31)
            place(tailBase, -30, 10, rot: 0)
            let tv = makeTV()
            tv.position = pt(42, 0)
            props.addChild(tv)
            tailWag.speed = 0.5
            mouthStyle = .smile
        case .yawn:
            sitBody()
            earBack.zRotation = 0.6
            act(pose, .sequence([
                .run { [weak self] in
                    self?.setEyes(.closed)
                    self?.setMouth(.bigOpen)
                    self?.headAnchor.run(ease(.rotate(toAngle: 0.25, duration: 0.4)), withKey: "pose")
                },
                .wait(forDuration: 1.4),
                .run { [weak self] in
                    self?.setEyes(.half)
                    self?.setMouth(.tiny)
                    self?.headAnchor.run(ease(.rotate(toAngle: 0, duration: 0.4)), withKey: "pose")
                },
            ]))
            tailWag.speed = 0.4
        case .happy:
            act(pose, .repeatForever(.sequence([
                { let a = SKAction.moveBy(x: 0, y: 7, duration: 0.13); a.timingMode = .easeOut; return a }(),
                { let a = SKAction.moveBy(x: 0, y: -7, duration: 0.13); a.timingMode = .easeIn; return a }(),
            ])))
            earBack.zRotation = 0.1
            earFront.zRotation = -0.35
            tailWag.speed = 2
            eyeChoice = .sparkle
            mouthStyle = .open
        case .kick:
            let ball = makeBall()
            ball.position = pt(38, 6)
            props.addChild(ball)
            act(frontNear, .repeatForever(.sequence([.rotate(toAngle: 0.9, duration: 0.12),
                                                     .rotate(toAngle: 0, duration: 0.2), .wait(forDuration: 0.4)])))
            ball.run(.repeatForever(.sequence([.wait(forDuration: 0.1), .moveBy(x: 5, y: 4, duration: 0.15),
                                               .moveBy(x: -5, y: -4, duration: 0.3), .wait(forDuration: 0.17)])))
            tailWag.speed = 1.8
            eyeChoice = .sparkle
        }
        setEyes(eyeChoice)
        setMouth(mouthStyle)
    }
}
#endif
