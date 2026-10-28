#if canImport(AppKit)
import Foundation

/// Appends routing decisions to ~/Library/Logs/DesktopPet/transitions.log so cuts and loops can be
/// spotted from normal use. Rolls over to transitions.old.log at 1 MB.
enum TransitionLog {
    private static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DesktopPet", isDirectory: true)
    private static let file = dir.appendingPathComponent("transitions.log")
    private static let queue = DispatchQueue(label: "DesktopPet.TransitionLog")
    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func append(_ line: String) {
        let text = "\(stamp.string(from: Date())) \(line)\n"
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: file.path))?[.size] as? Int, size > 1_000_000 {
                let old = dir.appendingPathComponent("transitions.old.log")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: file, to: old)
            }
            guard let data = text.data(using: .utf8) else { return }
            if let h = try? FileHandle(forWritingTo: file) {
                h.seekToEndOfFile()
                h.write(data)
                try? h.close()
            } else {
                try? data.write(to: file)
            }
        }
    }
}
#endif
