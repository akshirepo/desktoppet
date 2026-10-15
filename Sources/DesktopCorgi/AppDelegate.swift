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
    /// True when sprites come from an art pack; hats and the name tag only draw on the built-in corgi.
    private(set) var artPackInUse = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        var loaded: NeedsState?
        do {
            loaded = try store.load()
        } catch {
            NSLog("DesktopCorgi: state file was corrupt, starting fresh: \(error)")
        }
        needs = NeedsEngine(state: loaded ?? .fresh(at: Date()), clock: SystemClock())
        if loaded != nil { awaySeconds = needs.catchUpOffline() }

        installEditMenu()
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

    static func packURL(for profile: PetProfile) -> URL {
        StateStore.defaultDirectory.appendingPathComponent(profile.packFolderName)
    }

    static func packExists(for profile: PetProfile) -> Bool {
        FileManager.default.fileExists(atPath: packURL(for: profile).appendingPathComponent("manifest.json").path)
    }

    /// Corgi always works (built-in drawing); other choices need their pack installed.
    static func canUse(_ profile: PetProfile) -> Bool {
        profile.character == .corgi || packExists(for: profile)
    }

    func makeBackend() -> AnimationBackend {
        let pack = Self.packURL(for: profile)
        guard Self.packExists(for: profile) else {
            if profile.character != .corgi { NSLog("DesktopCorgi: no \(pack.lastPathComponent), using placeholder") }
            return PlaceholderBackend()
        }
        do {
            let backend = try FrameSequenceBackend(packURL: pack)
            artPackInUse = true
            return backend
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

    /// The backend is fixed for the life of the controller, so a new character saves and relaunches the app.
    func switchCharacter(to character: Character) {
        var next = profile
        next.character = character
        guard character != profile.character, Self.canUse(next) else { return }
        updateProfile { $0.character = character }
        relaunch()
    }

    /// Cap on or off swaps the sheep pack, which also needs a relaunch.
    func toggleSheepCap() {
        var next = profile
        next.sheepCap.toggle()
        guard profile.character == .sheep, Self.canUse(next) else { return }
        updateProfile { $0.sheepCap.toggle() }
        relaunch()
    }

    private func relaunch() {
        save()
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, error in
            DispatchQueue.main.async {
                if let error {
                    NSLog("DesktopCorgi: relaunch failed, new character applies on next launch: \(error)")
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
        let current = profile
        var capFlipped = current
        capFlipped.sheepCap.toggle()
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
            toggleLogin: { LoginItem.setEnabled(!LoginItem.isEnabled) },
            loginOn: LoginItem.isEnabled,
            rename: { [weak self] in DispatchQueue.main.async { self?.promptRename(firstTime: false) } },
            hat: profile.hat,
            setHat: { [weak self] hat in self?.updateProfile { $0.hat = hat } },
            toggleSounds: { [weak self] in self?.updateProfile { $0.soundsOn.toggle() } },
            soundsOn: profile.soundsOn,
            toggleNameTag: { [weak self] in self?.updateProfile { $0.showNameTag.toggle() } },
            nameTagOn: profile.showNameTag,
            character: profile.character,
            characterAvailable: { c in
                var p = current
                p.character = c
                return AppDelegate.canUse(p)
            },
            setCharacter: { [weak self] c in DispatchQueue.main.async { self?.switchCharacter(to: c) } },
            sheepCapOn: profile.sheepCap,
            sheepCapAvailable: current.character == .sheep && AppDelegate.canUse(capFlipped),
            toggleSheepCap: { [weak self] in DispatchQueue.main.async { self?.toggleSheepCap() } },
            artPackInUse: artPackInUse
        )
    }
}
#endif
