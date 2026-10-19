#if canImport(AppKit)
import AppKit
import CorgiCore

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", icon: String? = nil, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        if let icon { image = Doodles.menuIcon(icon) }
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
    var toggleSounds: () -> Void
    var soundsOn: Bool
    var toggleAskForCare: () -> Void
    var askForCareOn: Bool
    var character: Character
    var characterAvailable: (Character) -> Bool
    var setCharacter: (Character) -> Void
}

enum PetMenu {
    static func populate(_ menu: NSMenu, _ a: PetMenuActions) {
        menu.removeAllItems()
        menu.addItem(ClosureMenuItem("Feed", icon: "feed", handler: a.feed))
        menu.addItem(ClosureMenuItem("Play Ball", icon: "play", handler: a.play))
        let chase = ClosureMenuItem("Chase Me", icon: "resume", handler: a.toggleChaseMe)
        chase.state = a.chaseMeOn ? .on : .off
        menu.addItem(chase)
        menu.addItem(ClosureMenuItem("Bath", icon: "affection", handler: a.bath))
        menu.addItem(ClosureMenuItem("Nap", icon: "sleep", handler: a.nap))
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Stats…", icon: "settings", handler: a.stats))
        menu.addItem(ClosureMenuItem("Rename…", handler: a.rename))
        let chars = NSMenuItem(title: "Character", action: nil, keyEquivalent: "")
        let charMenu = NSMenu()
        charMenu.autoenablesItems = false
        for c in Character.allCases {
            let item = ClosureMenuItem(c.displayName, icon: c == .sheep ? "sheep" : "corgi") { a.setCharacter(c) }
            item.state = c == a.character ? .on : .off
            item.isEnabled = a.characterAvailable(c)
            charMenu.addItem(item)
        }
        chars.submenu = charMenu
        menu.addItem(chars)
        let sounds = ClosureMenuItem("Sounds", icon: a.soundsOn ? "sound-on" : "sound-off", handler: a.toggleSounds)
        sounds.state = a.soundsOn ? .on : .off
        menu.addItem(sounds)
        let care = ClosureMenuItem("Ask for Care", icon: "help", handler: a.toggleAskForCare)
        care.state = a.askForCareOn ? .on : .off
        menu.addItem(care)
        let debug = ClosureMenuItem("Debug Overlay", handler: a.toggleDebug)
        debug.state = a.debugOn ? .on : .off
        menu.addItem(debug)
        menu.addItem(.separator())
        let login = ClosureMenuItem("Launch at Login", handler: a.toggleLogin)
        login.state = a.loginOn ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = Doodles.menuIcon("quit")
        menu.addItem(quit)
    }
}
#endif
