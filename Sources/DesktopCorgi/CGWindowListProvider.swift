#if canImport(AppKit)
import AppKit
import CorgiCore

/// Reads on-screen normal windows. Window bounds need no special permission.
final class CGWindowListProvider: WindowListProvider {
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    func visibleWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.height
        else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let id = info[kCGWindowNumber as String] as? Int,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  bounds.height >= 50
            else { return nil }
            return WindowInfo(id: id, frame: appKitRect(fromCGBounds: bounds, primaryScreenHeight: primaryHeight))
        }
    }
}
#endif
