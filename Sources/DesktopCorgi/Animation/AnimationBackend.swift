#if canImport(AppKit)
import CorgiCore
import SpriteKit

protocol AnimationBackend: AnyObject {
    /// Root node. Its origin is the corgi's feet.
    var node: SKNode { get }
    /// Size in points, used for the hit box.
    var size: CGSize { get }
    func play(_ state: AnimState)
    func setFacing(right: Bool)
    func setHat(_ hat: Hat)
    func setName(_ name: String)
    func setHovering(_ hovering: Bool)
    func setHappy(_ happy: Bool)
    /// True when the backend draws its own book, headphones, TV and ball, so no emoji prop is needed.
    var drawsProps: Bool { get }
    /// Where a carried ball sits, facing right, relative to the feet.
    var mouthPoint: CGPoint { get }
    /// Height above the feet where speech and thought bubbles start (above any hat).
    var bubbleHeight: CGFloat { get }
}

extension AnimationBackend {
    func setHat(_ hat: Hat) {}
    func setName(_ name: String) {}
    func setHovering(_ hovering: Bool) {}
    func setHappy(_ happy: Bool) {}
    var drawsProps: Bool { false }
    var mouthPoint: CGPoint { CGPoint(x: 26, y: 30) }
    var bubbleHeight: CGFloat { size.height }
}
#endif
