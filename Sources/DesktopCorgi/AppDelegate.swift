#if canImport(AppKit)
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!

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
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        sender.state = LoginItem.isEnabled ? .on : .off
    }
}
#endif
