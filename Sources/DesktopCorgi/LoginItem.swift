#if canImport(AppKit)
import Foundation
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("DesktopCorgi: login item change failed: \(error)")
        }
    }
}
#endif
