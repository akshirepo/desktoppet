#if canImport(AppKit)
import AppKit
import ServiceManagement

enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var isEnabled: Bool { status == .enabled }

    /// Registers (or unregisters) the app as a login item. Registering again is harmless and refreshes
    /// the item after the app has been rebuilt or replaced, which can otherwise leave it stale.
    @discardableResult
    static func apply(_ on: Bool) -> SMAppService.Status {
        do {
            if on { try SMAppService.mainApp.register() } else if status != .notRegistered { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("DesktopCorgi: login item change failed: \(error)")
        }
        return status
    }

    /// macOS sometimes holds a new login item until you allow it in System Settings > General > Login Items.
    static func askForApprovalIfNeeded() {
        guard status == .requiresApproval else { return }
        let alert = NSAlert()
        alert.messageText = "Allow DesktopPet to open at login"
        alert.informativeText = "macOS needs your OK. Turn on DesktopCorgi under Login Items in System Settings."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { SMAppService.openSystemSettingsLoginItems() }
    }
}
#endif
