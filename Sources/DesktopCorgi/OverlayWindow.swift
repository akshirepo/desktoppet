#if canImport(AppKit)
import AppKit
import SpriteKit

protocol SceneInputHandler: AnyObject {
    func mouseDown(at global: CGPoint)
    func mouseDragged(to global: CGPoint)
    func mouseUp(at global: CGPoint)
    func rightMouseDown(_ event: NSEvent, in view: NSView)
}

final class OverlayScene: SKScene {
    weak var input: SceneInputHandler?

    override func mouseDown(with event: NSEvent) { input?.mouseDown(at: NSEvent.mouseLocation) }
    override func mouseDragged(with event: NSEvent) { input?.mouseDragged(to: NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) { input?.mouseUp(at: NSEvent.mouseLocation) }
    override func rightMouseDown(with event: NSEvent) {
        if let view { input?.rightMouseDown(event, in: view) }
    }
}

/// Transparent, borderless, always-on-top panel covering one screen.
final class OverlayWindow: NSPanel {
    let skView: SKView
    let scene: OverlayScene

    init(screen: NSScreen) {
        let frame = screen.frame
        skView = SKView(frame: NSRect(origin: .zero, size: frame.size))
        scene = OverlayScene(size: frame.size)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        skView.allowsTransparency = true
        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)
        contentView = skView
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
#endif
