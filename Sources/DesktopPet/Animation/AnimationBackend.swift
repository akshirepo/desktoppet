#if canImport(AppKit)
import CorgiCore
import SpriteKit

protocol AnimationBackend: AnimationPlaybackBackend {
    /// Root node. Its origin is the corgi's feet.
    var node: SKNode { get }
    /// Idle canvas size in points, used to position effects.
    var size: CGSize { get }
    /// Current sprite only, relative to the feet, including its anchor and facing.
    var spriteBounds: CGRect { get }
    /// Stable envelope for normal movement, excluding window grips and transient effects.
    var movementBounds: CGRect { get }
    /// Unmirrored canvas for a resolved pose, used to validate a window grip.
    func bounds(for state: AnimState) -> CGRect
    /// Posture of each pose for this pet, used to route transitions.
    var postures: [AnimState: Posture] { get }
    var available: Set<AnimState> { get }
    /// Named transition animations the pack has ("stand>sit", "enter:watch", ...).
    var bridgeNames: Set<String> { get }
    var directPairs: Set<[AnimState]> { get }
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
