#if canImport(AppKit)
import AppKit
import CorgiCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    /// The active pet's own save file (needs, level, together-since).
    private(set) var store: StateStore!
    var needs: NeedsEngine!
    let profileStore = ProfileStore(directory: StateStore.defaultDirectory)
    var profile = PetProfile()
    var controller: PetController!
    var awaySeconds: TimeInterval = 0
    private var saveTimer: Timer?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        StateStore.migrateAppFolder()          // settings from when the app was called DesktopCorgi
        profile = profileStore.load()
        StateStore.migrateLegacy(in: StateStore.defaultDirectory, to: profile.character)
        store = StateStore(directory: StateStore.defaultDirectory, character: profile.character)
        var loaded: NeedsState?
        do {
            loaded = try store.load()
        } catch {
            NSLog("DesktopPet: state file was corrupt, starting fresh: \(error)")
        }
        needs = NeedsEngine(state: loaded ?? .fresh(at: Date()), clock: SystemClock())
        if loaded != nil { awaySeconds = needs.catchUpOffline() }

        installEditMenu()
        controller = PetController(needs: needs, backend: makeBackend())
        controller.applyProfile(profile)
        controller.start()
        if profile.launchAtLogin {
            LoginItem.apply(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { LoginItem.askForApprovalIfNeeded() }
        }
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
        if let icon = Doodles.statusIcon(sheep: profile.character == .sheep) {
            statusItem.button?.image = icon
        } else {
            statusItem.button?.title = profile.character == .sheep ? "🐑" : "🐶"
        }
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

    /// A pack in ~/Library/Application Support/DesktopPet overrides the art bundled in the app.
    static func packURL(for profile: PetProfile) -> URL {
        let custom = StateStore.defaultDirectory.appendingPathComponent(profile.packFolderName)
        if FileManager.default.fileExists(atPath: custom.appendingPathComponent("manifest.json").path) { return custom }
        return Bundle.main.resourceURL?.appendingPathComponent("Packs/\(profile.packFolderName)") ?? custom
    }

    static func packExists(for profile: PetProfile) -> Bool {
        FileManager.default.fileExists(atPath: packURL(for: profile).appendingPathComponent("manifest.json").path)
    }

    static func canUse(_ profile: PetProfile) -> Bool { packExists(for: profile) }

    /// The chosen pet's art, falling back to the bundled corgi if a custom pack is broken.
    func makeBackend() -> AnimationBackend {
        for candidate in [profile, PetProfile(character: .corgi)] {
            do {
                return try FrameSequenceBackend(packURL: Self.packURL(for: candidate))
            } catch {
                NSLog("DesktopPet: could not load \(candidate.packFolderName): \(error)")
            }
        }
        fatalError("DesktopPet: no pet art found; build the app with scripts/bundle.sh so the packs are included")
    }

    func applicationWillTerminate(_ notification: Notification) {
        save()
    }

    @objc private func saveTimerFired() { save() }

    func save() {
        needs.markSaved()
        do { try store.save(needs.state) } catch { NSLog("DesktopPet: save failed: \(error)") }
    }

    func saveProfile() {
        do { try profileStore.save(profile) } catch { NSLog("DesktopPet: profile save failed: \(error)") }
    }

    /// The backend is fixed for the life of the controller, so a new character saves and relaunches the app.
    func switchCharacter(to character: Character) {
        var next = profile
        next.character = character
        guard character != profile.character, Self.canUse(next) else { return }
        updateProfile { $0.character = character }
        relaunch()
    }

    private func relaunch() {
        save()
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, error in
            DispatchQueue.main.async {
                if let error {
                    NSLog("DesktopPet: relaunch failed, new character applies on next launch: \(error)")
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func updateProfile(_ change: (inout PetProfile) -> Void) {
        change(&profile)
        controller.applyProfile(profile)
        saveProfile()
    }

    /// An accessory app has no visible menu bar, but without an Edit menu Cmd-C/V/X/A/Z do nothing in the rename field.
    private func installEditMenu() {
        let main = NSMenu()
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    /// NSAlert with a text field. OK renames; Later keeps the current name.
    func promptRename(firstTime: Bool) {
        let alert = NSAlert()
        let kind = profile.character.displayName.lowercased()
        alert.messageText = firstTime ? "Say hi to your new \(kind)!" : "Rename your \(kind)"
        alert.informativeText = firstTime ? "What should we call them? You can change it later from the menu."
            : "Pick a new name (up to \(PetProfile.maxNameLength) characters)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = profile.name
        field.placeholderString = profile.character.displayName
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
        let current = profile
        return PetMenuActions(
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
            toggleLogin: { [weak self] in
                guard let self else { return }
                self.updateProfile { $0.launchAtLogin.toggle() }
                LoginItem.apply(self.profile.launchAtLogin)
                if self.profile.launchAtLogin { DispatchQueue.main.async { LoginItem.askForApprovalIfNeeded() } }
            },
            loginOn: profile.launchAtLogin,
            rename: { [weak self] in DispatchQueue.main.async { self?.promptRename(firstTime: false) } },
            toggleSounds: { [weak self] in self?.updateProfile { $0.soundsOn.toggle() } },
            soundsOn: profile.soundsOn,
            character: profile.character,
            characterAvailable: { c in
                var p = current
                p.character = c
                return AppDelegate.canUse(p)
            },
            setCharacter: { [weak self] c in DispatchQueue.main.async { self?.switchCharacter(to: c) } }
        )
    }
}
#endif
