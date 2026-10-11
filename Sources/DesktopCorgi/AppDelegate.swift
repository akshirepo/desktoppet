#if canImport(AppKit)
import AppKit
import CorgiCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let store = StateStore(directory: StateStore.defaultDirectory)
    var needs: NeedsEngine!
    var controller: PetController!
    var awaySeconds: TimeInterval = 0
    private var saveTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        var loaded: NeedsState?
        do {
            loaded = try store.load()
        } catch {
            NSLog("DesktopCorgi: state file was corrupt, starting fresh: \(error)")
        }
        needs = NeedsEngine(state: loaded ?? .fresh(at: Date()), clock: SystemClock())
        if loaded != nil { awaySeconds = needs.catchUpOffline() }

        controller = PetController(needs: needs, backend: PlaceholderBackend())
        controller.start()

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

        save()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.save() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        save()
    }

    func save() {
        needs.markSaved()
        do { try store.save(needs.state) } catch { NSLog("DesktopCorgi: save failed: \(error)") }
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        sender.state = LoginItem.isEnabled ? .on : .off
    }
}
#endif
