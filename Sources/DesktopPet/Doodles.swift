#if canImport(AppKit)
import AppKit
import SpriteKit

/// Hand-drawn doodle icons bundled under Contents/Resources/Doodles (see Assets/Doodles).
/// Every lookup returns nil when the resources are missing (e.g. `swift run`), so callers keep a text fallback.
enum Doodles {
    private static let root = Bundle.main.resourceURL?.appendingPathComponent("Doodles")
    private static var images: [String: NSImage] = [:]
    private static var textures: [String: SKTexture] = [:]

    static func image(_ relativePath: String) -> NSImage? {
        if let cached = images[relativePath] { return cached }
        guard let url = root?.appendingPathComponent(relativePath),
              let img = NSImage(contentsOf: url) else { return nil }
        images[relativePath] = img
        return img
    }

    /// Scene texture. The soft sticker-style icons (soft/, drawn by scripts/soft_icons.py) come first, so what floats
    /// around the pet matches its speech bubble; anything not redrawn falls back to the pixel doodles
    /// ("heart", "zzz", ... in effects/2x; "menu:feed" in the color menu icons).
    static func texture(_ name: String) -> SKTexture? {
        if let cached = textures[name] { return cached }
        let plain = name.hasPrefix("menu:") ? String(name.dropFirst(5)) : name
        let path = name.hasPrefix("menu:") ? "menu/color/48/\(plain).png" : "effects/2x/\(name).png"
        guard let img = image("soft/\(plain).png") ?? image(path) else { return nil }
        let t = SKTexture(image: img)
        textures[name] = t
        return t
    }

    /// Black template icon for menus; macOS tints it for light/dark mode.
    static func menuIcon(_ name: String, size: CGFloat = 16) -> NSImage? {
        template(image("menu/black/48/\(name).png"), size: size)
    }

    /// Full-color icon, e.g. for the Stats popover.
    static func colorIcon(_ name: String, size: CGFloat) -> NSImage? {
        sized(image("menu/color/48/\(name).png"), size: size)
    }

    /// Menu bar icon for the current character.
    static func statusIcon(sheep: Bool) -> NSImage? {
        template(image(sheep ? "status/black/44/sheep.png" : "status/black/44/corgi.png"), size: 18)
    }

    private static func sized(_ img: NSImage?, size: CGFloat) -> NSImage? {
        guard let copy = img?.copy() as? NSImage else { return nil }
        copy.size = NSSize(width: size, height: size)
        return copy
    }

    private static func template(_ img: NSImage?, size: CGFloat) -> NSImage? {
        let copy = sized(img, size: size)
        copy?.isTemplate = true
        return copy
    }
}
#endif
