#if !canImport(CoreGraphics)
import Foundation

public struct CGVector: Equatable, Hashable {
    public var dx: CGFloat
    public var dy: CGFloat

    public init(dx: CGFloat, dy: CGFloat) {
        self.dx = dx
        self.dy = dy
    }

    public static let zero = CGVector(dx: 0, dy: 0)
}
#endif
