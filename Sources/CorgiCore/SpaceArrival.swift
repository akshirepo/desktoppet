#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// Coming back into view after a switch to another Space: the side it runs in from and where it stops.
public struct SpaceArrival: Equatable {
    /// Feet x to start from, far enough past the display edge that none of the sprite shows.
    public var startX: CGFloat
    /// Feet x it runs on to.
    public var stopX: CGFloat
    public var fromLeft: Bool

    /// `step` is how many Spaces the display moved (positive: to one on the right), nil when it can't tell.
    /// Moving right, the old Space slides off to the left, so the pet follows in from the left edge; when it
    /// can't tell, it comes in on the side it was nearer. `reach` is how far the drawn sprite extends from its
    /// feet, and `depth` how far across the floor it runs (0...1). Nil for a step of 0: its Space didn't change.
    public static func plan(step: Int?, screen: CGRect, floor: FloorSegment, feetX: CGFloat, reach: CGFloat,
                            depth: CGFloat) -> SpaceArrival? {
        if step == 0 { return nil }
        let fromLeft = step.map { $0 > 0 } ?? (feetX < screen.midX)
        let start = fromLeft ? min(screen.minX, floor.minX) - reach : max(screen.maxX, floor.maxX) + reach
        let run = floor.width * min(max(depth, 0), 1)
        return SpaceArrival(startX: start, stopX: fromLeft ? floor.minX + run : floor.maxX - run, fromLeft: fromLeft)
    }
}
