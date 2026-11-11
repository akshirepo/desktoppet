#if canImport(AppKit)
import AppKit

/// Which Space each display is showing, as its position in the display's left-to-right list of Spaces.
/// Read through the private CGS calls Mission Control uses, looked up at run time; without them it just can't
/// tell which way a switch went.
enum Spaces {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private static let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)   // RTLD_DEFAULT
    private static let mainConnection = dlsym(defaultHandle, "CGSMainConnectionID")
        .map { unsafeBitCast($0, to: MainConnection.self) }
    private static let copyDisplaySpaces = dlsym(defaultHandle, "CGSCopyManagedDisplaySpaces")
        .map { unsafeBitCast($0, to: CopyDisplaySpaces.self) }

    /// Display UUID (or "Main" when all displays share Spaces) to the index of its current Space.
    static func current() -> [String: Int] {
        guard let main = mainConnection, let copy = copyDisplaySpaces,
              let list = copy(main())?.takeRetainedValue() as? [[String: Any]] else { return [:] }
        var out: [String: Int] = [:]
        for display in list {
            guard let id = display["Display Identifier"] as? String,
                  let now = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int,
                  let spaces = display["Spaces"] as? [[String: Any]],
                  let i = spaces.firstIndex(where: { $0["ManagedSpaceID"] as? Int == now }) else { continue }
            out[id.uppercased()] = i
        }
        return out
    }

    /// The key `current()` uses for `screen`.
    static func key(of screen: NSScreen, in spaces: [String: Int]) -> String? {
        if spaces.count == 1 { return spaces.keys.first }
        guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(n.uint32Value)?.takeRetainedValue(),
              let s = CFUUIDCreateString(nil, uuid) as String? else { return nil }
        return s.uppercased()
    }
}
#endif
