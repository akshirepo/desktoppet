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
}
#endif
