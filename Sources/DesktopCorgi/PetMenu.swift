#if canImport(AppKit)
import AppKit
import CorgiCore

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
    var toggleChaseMe: () -> Void
    var chaseMeOn: Bool
    var bath: () -> Void
    var nap: () -> Void
    var stats: () -> Void
    var toggleDebug: () -> Void
    var debugOn: Bool
    var toggleLogin: () -> Void
    var loginOn: Bool
    var rename: () -> Void
    var hat: Hat
    var setHat: (Hat) -> Void
    var toggleSounds: () -> Void
    var soundsOn: Bool
    var toggleNameTag: () -> Void
    var nameTagOn: Bool
}

enum PetMenu {
    static func populate(_ menu: NSMenu, _ a: PetMenuActions) {
        menu.removeAllItems()
        menu.addItem(ClosureMenuItem("🍖 Feed", handler: a.feed))
        menu.addItem(ClosureMenuItem("🎾 Play Ball", handler: a.play))
        let chase = ClosureMenuItem("🏃 Chase Me", handler: a.toggleChaseMe)
        chase.state = a.chaseMeOn ? .on : .off
        menu.addItem(chase)
        menu.addItem(ClosureMenuItem("🫧 Bath", handler: a.bath))
        menu.addItem(ClosureMenuItem("💤 Nap", handler: a.nap))
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("📊 Stats…", handler: a.stats))
        menu.addItem(ClosureMenuItem("Rename…", handler: a.rename))
        let tag = ClosureMenuItem("Name Tag", handler: a.toggleNameTag)
        tag.state = a.nameTagOn ? .on : .off
        menu.addItem(tag)
        let hats = NSMenuItem(title: "Hats", action: nil, keyEquivalent: "")
        let hatMenu = NSMenu()
        for hat in Hat.allCases {
            let item = ClosureMenuItem(hat.displayName) { a.setHat(hat) }
            item.state = hat == a.hat ? .on : .off
            hatMenu.addItem(item)
        }
        hats.submenu = hatMenu
        menu.addItem(hats)
        let sounds = ClosureMenuItem("Sounds", handler: a.toggleSounds)
        sounds.state = a.soundsOn ? .on : .off
        menu.addItem(sounds)
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
