import Foundation

public enum StateStoreError: Error, Equatable {
    case corrupt(backupURL: URL)
}

public final class StateStore {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("state.json") }
    public var backupURL: URL { directory.appendingPathComponent("state.corrupt.json") }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DesktopCorgi")
    }

    public init(directory: URL) {
        self.directory = directory
    }

    public func load() throws -> NeedsState? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return nil }
        do {
            return try JSONDecoder().decode(NeedsState.self, from: Data(contentsOf: fileURL))
        } catch {
            try? fm.removeItem(at: backupURL)
            try fm.moveItem(at: fileURL, to: backupURL)
            throw StateStoreError.corrupt(backupURL: backupURL)
        }
    }

    public func save(_ state: NeedsState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: fileURL, options: .atomic)
    }
}
