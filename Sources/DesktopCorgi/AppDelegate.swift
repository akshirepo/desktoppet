#if canImport(AppKit)
import AppKit
import CorgiCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var backend: AnimationBackend!
    var overlays: OverlayManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐶"
        let menu = NSMenu()
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        backend = PlaceholderBackend()
        overlays = OverlayManager(corgiNode: backend.node)
        if let vf = NSScreen.main?.visibleFrame {
            overlays.place(globalFeet: CGPoint(x: vf.midX, y: vf.minY))
        }
        backend.play(.walk)
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        sender.state = LoginItem.isEnabled ? .on : .off
    }
}
#endif
