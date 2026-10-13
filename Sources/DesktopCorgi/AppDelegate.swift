#if canImport(AppKit)
import AppKit
import CorgiCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    let store = StateStore(directory: StateStore.defaultDirectory)
    var needs: NeedsEngine!
    let profileStore = ProfileStore(directory: StateStore.defaultDirectory)
    var profile = PetProfile()
    var controller: PetController!
    var awaySeconds: TimeInterval = 0
    private var saveTimer: Timer?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        var loaded: NeedsState?
        do {
            loaded = try store.load()
        } catch {
            NSLog("DesktopCorgi: state file was corrupt, starting fresh: \(error)")
        }
        needs = NeedsEngine(state: loaded ?? .fresh(at: Date()), clock: SystemClock())
        if loaded != nil { awaySeconds = needs.catchUpOffline() }

        profile = profileStore.load()
        controller = PetController(needs: needs, backend: makeBackend())
        controller.applyProfile(profile)
        controller.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.controller.greet(awaySeconds: self.awaySeconds)
        }
        if !profile.askedForName {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self else { return }
                self.profile.askedForName = true
                self.saveProfile()
                self.promptRename(firstTime: true)
            }
        }

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
        saveTimer = Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(saveTimerFired),
                                         userInfo: nil, repeats: true)
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

    @objc private func saveTimerFired() { save() }

    func save() {
        needs.markSaved()
        do { try store.save(needs.state) } catch { NSLog("DesktopCorgi: save failed: \(error)") }
    }

    func saveProfile() {
        do { try profileStore.save(profile) } catch { NSLog("DesktopCorgi: profile save failed: \(error)") }
    }

    func updateProfile(_ change: (inout PetProfile) -> Void) {
        change(&profile)
        controller.applyProfile(profile)
        saveProfile()
    }

    /// NSAlert with a text field. OK renames; Later keeps the current name.
    func promptRename(firstTime: Bool) {
        let alert = NSAlert()
        alert.messageText = firstTime ? "Say hi to your new corgi!" : "Rename your corgi"
        alert.informativeText = firstTime ? "What should we call them? You can change it later from the menu."
            : "Pick a new name (up to \(PetProfile.maxNameLength) characters)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = profile.name
        field.placeholderString = PetProfile.defaultName
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Later")
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        updateProfile { $0.rename(to: field.stringValue) }
    }

    func showStats() {
        guard let button = statusItem.button else { return }
        let p = NSPopover()
        p.behavior = .transient
        p.contentViewController = NSHostingController(rootView: StatsView(state: needs.state, title: profile.statsTitle(level: needs.level)))
        NSApp.activate()
        p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover = p
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        PetMenu.populate(menu, makeMenuActions())
    }

    func makeMenuActions() -> PetMenuActions {
        PetMenuActions(
            feed: { [weak self] in self?.controller.feed() },
            play: { [weak self] in self?.controller.playBall() },
            toggleChaseMe: { [weak self] in
                guard let c = self?.controller else { return }
                c.setChaseMe(!c.chaseMe)
            },
            chaseMeOn: controller.chaseMe,
            bath: { [weak self] in self?.controller.bath() },
            nap: { [weak self] in self?.controller.nap() },
            stats: { [weak self] in DispatchQueue.main.async { self?.showStats() } },
            toggleDebug: { [weak self] in self?.controller.debug.enabled.toggle() },
            debugOn: controller.debug.enabled,
            toggleLogin: { LoginItem.setEnabled(!LoginItem.isEnabled) },
            loginOn: LoginItem.isEnabled,
            rename: { [weak self] in DispatchQueue.main.async { self?.promptRename(firstTime: false) } },
            hat: profile.hat,
            setHat: { [weak self] hat in self?.updateProfile { $0.hat = hat } },
            toggleSounds: { [weak self] in self?.updateProfile { $0.soundsOn.toggle() } },
            soundsOn: profile.soundsOn
        )
    }
}
#endif
