#if canImport(AppKit)
import AppKit
import CorgiCore
import SpriteKit

/// Code-drawn corgi used until an asset pack is installed. Faces right by default.
final class PlaceholderBackend: AnimationBackend {
    let node = SKNode()
    let size = CGSize(width: 96, height: 72)
    private let figure = SKNode()
    private var facingRight = true

    private static let fur = NSColor(red: 0.91, green: 0.64, blue: 0.24, alpha: 1)

    init() {
        node.addChild(figure)
        for x in [-22.0, -12.0, 14.0, 24.0] {
            figure.addChild(shape(SKShapeNode(rect: CGRect(x: x - 3, y: 0, width: 6, height: 14), cornerRadius: 3), Self.fur))
        }
        figure.addChild(shape(SKShapeNode(ellipseOf: CGSize(width: 74, height: 38)), Self.fur, at: CGPoint(x: 0, y: 24)))
        figure.addChild(shape(SKShapeNode(ellipseOf: CGSize(width: 40, height: 16)), .white, at: CGPoint(x: 4, y: 16)))
        figure.addChild(shape(SKShapeNode(circleOfRadius: 6), .white, at: CGPoint(x: -38, y: 32)))
        figure.addChild(shape(SKShapeNode(circleOfRadius: 17), Self.fur, at: CGPoint(x: 36, y: 46)))
        figure.addChild(shape(SKShapeNode(ellipseOf: CGSize(width: 18, height: 11)), .white, at: CGPoint(x: 48, y: 41)))
        figure.addChild(shape(SKShapeNode(circleOfRadius: 2.5), .black, at: CGPoint(x: 56, y: 43)))
        figure.addChild(shape(SKShapeNode(circleOfRadius: 2.5), .black, at: CGPoint(x: 41, y: 51)))
        for (a, b, c) in [(CGPoint(x: 24, y: 56), CGPoint(x: 27, y: 74), CGPoint(x: 35, y: 60)),
                          (CGPoint(x: 37, y: 61), CGPoint(x: 44, y: 76), CGPoint(x: 48, y: 57))] {
            let path = CGMutablePath()
            path.addLines(between: [a, b, c])
            path.closeSubpath()
            figure.addChild(shape(SKShapeNode(path: path), Self.fur))
        }
    }

    private func shape(_ s: SKShapeNode, _ color: NSColor, at p: CGPoint = .zero) -> SKShapeNode {
        s.fillColor = color
        s.strokeColor = color.blended(withFraction: 0.3, of: .black) ?? color
        s.lineWidth = 1
        s.position = p
        return s
    }

    func setFacing(right: Bool) {
        facingRight = right
        figure.xScale = right ? abs(figure.xScale) : -abs(figure.xScale)
    }

    func play(_ state: AnimState) {
        figure.removeAllActions()
        figure.position = .zero
        figure.zRotation = 0
        figure.setScale(1)
        setFacing(right: facingRight)
        switch state {
        case .walk, .run, .roam, .holdBall:
            let t = state == .walk ? 0.16 : 0.08
            figure.run(.repeatForever(.sequence([.moveBy(x: 0, y: 3, duration: t), .moveBy(x: 0, y: -3, duration: t)])))
        case .sleep, .readSleep:
            figure.yScale = 0.7
        case .sit, .read, .music, .watch:
            figure.yScale = 0.9
        case .beg:
            figure.zRotation = 0.25
        case .eat:
            figure.run(.repeatForever(.sequence([.rotate(toAngle: -0.15, duration: 0.2), .rotate(toAngle: 0, duration: 0.2)])))
        case .dangle:
            figure.run(.repeatForever(.sequence([.rotate(toAngle: 0.2, duration: 0.4), .rotate(toAngle: -0.2, duration: 0.4)])))
        case .scared:
            figure.run(.repeatForever(.sequence([.moveBy(x: 2, y: 0, duration: 0.04), .moveBy(x: -2, y: 0, duration: 0.04)])))
        case .wiggle:
            figure.run(.repeat(.sequence([.rotate(toAngle: 0.15, duration: 0.08), .rotate(toAngle: -0.15, duration: 0.08)]), count: 4))
        case .wave:
            figure.run(.repeatForever(.sequence([.rotate(toAngle: 0.12, duration: 0.15), .rotate(toAngle: -0.04, duration: 0.15)])))
        case .happy:
            figure.run(.repeat(.sequence([.moveBy(x: 0, y: 6, duration: 0.12), .moveBy(x: 0, y: -6, duration: 0.12)]), count: 3))
        case .back:
            figure.run(.sequence([.scaleX(by: 0.3, y: 1, duration: 0.25), .wait(forDuration: 1.5),
                                  .scaleX(by: 1 / 0.3, y: 1, duration: 0.25)]))
        case .yawn:
            figure.run(.sequence([.scaleY(to: 1.1, duration: 0.6), .scaleY(to: 0.8, duration: 1.4)]))
        case .kick:
            figure.run(.repeatForever(.sequence([.rotate(toAngle: -0.2, duration: 0.15), .rotate(toAngle: 0, duration: 0.25),
                                                 .wait(forDuration: 0.1)])))
        case .bath:
            figure.run(.repeatForever(.sequence([.moveBy(x: 3, y: 0, duration: 0.05), .moveBy(x: -3, y: 0, duration: 0.05)])))
        case .fall:
            figure.yScale = 1.05
        case .land:
            figure.yScale = 0.85
        case .idle, .fetch:
            break
        }
    }
}
#endif
