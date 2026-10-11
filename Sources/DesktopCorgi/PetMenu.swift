#if canImport(AppKit)
import AppKit

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}

struct PetMenuActions {
    var feed: () -> Void
    var play: () -> Void
    var bath: () -> Void
    var nap: () -> Void
    var stats: () -> Void
    var toggleDebug: () -> Void
    var debugOn: Bool
    var toggleLogin: () -> Void
    var loginOn: Bool
}

enum PetMenu {
    static func populate(_ menu: NSMenu, _ a: PetMenuActions) {
        menu.removeAllItems()
        menu.addItem(ClosureMenuItem("🍖 Feed", handler: a.feed))
        menu.addItem(ClosureMenuItem("🎾 Play Ball", handler: a.play))
        menu.addItem(ClosureMenuItem("🫧 Bath", handler: a.bath))
        menu.addItem(ClosureMenuItem("💤 Nap", handler: a.nap))
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("📊 Stats…", handler: a.stats))
        let debug = ClosureMenuItem("Debug Overlay", handler: a.toggleDebug)
        debug.state = a.debugOn ? .on : .off
        menu.addItem(debug)
        menu.addItem(.separator())
        let login = ClosureMenuItem("Launch at Login", handler: a.toggleLogin)
        login.state = a.loginOn ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }
}
#endif
