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
    /// Where a carried ball sits, facing right, relative to the feet.
    var mouthPoint: CGPoint { get }
    /// Height above the feet where speech and thought bubbles start.
    var bubbleHeight: CGFloat { get }
}

extension AnimationBackend {
    var mouthPoint: CGPoint { CGPoint(x: 26, y: 30) }
    var bubbleHeight: CGFloat { size.height }
}
#endif
