#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// How a frame cut down to its art box is drawn so it lands exactly where the full canvas would.
public struct FrameLayout: Equatable {
    /// The part of the canvas that's kept, in canvas pixels from the top-left.
    public var crop: CGRect
    /// Anchor of the cropped image (unit coordinates from its bottom-left) that sits on the canvas anchor.
    public var anchor: CGPoint

    /// `crop` is the spec's [x, y, w, h]; anything missing, empty or outside the canvas means the whole canvas.
    public init(canvas: CGSize, crop: [Double]?, anchor: CGPoint) {
        let full = CGRect(origin: .zero, size: canvas)
        var box = full
        if let c = crop, c.count == 4 {
            let r = CGRect(x: c[0], y: c[1], width: c[2], height: c[3]).integral.intersection(full)
            if !r.isNull, r.width >= 1, r.height >= 1 { box = r }
        }
        self.crop = box
        // The canvas anchor measured from the crop's bottom-left corner.
        let below = canvas.height - box.maxY
        self.anchor = CGPoint(x: (anchor.x * canvas.width - box.minX) / box.width,
                              y: (anchor.y * canvas.height - below) / box.height)
    }

    /// Where the full canvas sits relative to the anchor at `scale`: what a sprite showing the whole canvas would cover.
    public static func canvasBounds(canvas: CGSize, anchor: CGPoint, scale: CGFloat) -> CGRect {
        CGRect(x: -anchor.x * canvas.width * scale, y: -anchor.y * canvas.height * scale,
               width: canvas.width * scale, height: canvas.height * scale)
    }
}

/// Keeps decoded frames under a memory limit: the least recently played folders go first.
public struct FrameBudget<Key: Hashable> {
    public let limit: Int
    /// Never dropped (the poses needed at once: standing, walking, falling).
    public var pinned: Set<Key> = []
    private var sizes: [Key: Int] = [:]
    /// Least recently used first.
    private var order: [Key] = []

    public init(limit: Int) { self.limit = limit }

    public var total: Int { sizes.values.reduce(0, +) }
    public var keys: Set<Key> { Set(sizes.keys) }

    /// Notes that `key` (holding `bytes`) was just used, and returns the folders to drop to get back under the limit.
    /// The one just used is never dropped, even when it alone is over the limit.
    public mutating func use(_ key: Key, bytes: Int) -> [Key] {
        sizes[key] = bytes
        order.removeAll { $0 == key }
        order.append(key)
        var dropped: [Key] = []
        var total = self.total
        for candidate in order where total > limit && candidate != key && !pinned.contains(candidate) {
            total -= sizes[candidate] ?? 0
            dropped.append(candidate)
        }
        for k in dropped {
            sizes[k] = nil
            order.removeAll { $0 == k }
        }
        return dropped
    }
}
