#if canImport(AppKit)
import AppKit
import CorgiCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
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

        controller = PetController(needs: needs, backend: makeBackend())
        controller.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐶"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        controller.onRightClick = { [weak self] event, view in
            guard let self else { return }
            let popup = NSMenu()
            PetMenu.populate(popup, self.makeMenuActions())
            NSMenu.popUpContextMenu(popup, with: event, for: view)
        }

        save()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.save() }
    }

    func makeBackend() -> AnimationBackend {
        let pack = StateStore.defaultDirectory.appendingPathComponent("CorgiPack")
        guard FileManager.default.fileExists(atPath: pack.appendingPathComponent("manifest.json").path) else {
            return PlaceholderBackend()
        }
        do {
            return try FrameSequenceBackend(packURL: pack)
        } catch {
            NSLog("DesktopCorgi: could not load asset pack, using placeholder: \(error)")
            return PlaceholderBackend()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        save()
    }

    func save() {
        needs.markSaved()
        do { try store.save(needs.state) } catch { NSLog("DesktopCorgi: save failed: \(error)") }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        PetMenu.populate(menu, makeMenuActions())
    }

    func makeMenuActions() -> PetMenuActions {
        PetMenuActions(
            feed: { [weak self] in self?.controller.feed() },
            play: { [weak self] in self?.controller.playBall() },
            bath: { [weak self] in self?.controller.bath() },
            nap: { [weak self] in self?.controller.nap() },
            toggleLogin: { LoginItem.setEnabled(!LoginItem.isEnabled) },
            loginOn: LoginItem.isEnabled
        )
    }
}
#endif
