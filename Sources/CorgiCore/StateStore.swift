import Foundation

public enum StateStoreError: Error, Equatable {
    case corrupt(backupURL: URL)
}

public final class StateStore {
    public let directory: URL
    public let fileName: String
    public var fileURL: URL { directory.appendingPathComponent(fileName) }
    public var backupURL: URL {
        directory.appendingPathComponent(fileName.replacingOccurrences(of: ".json", with: ".corrupt.json"))
    }

    public static let appFolderName = "DesktopPet"

    /// The app used to be called DesktopCorgi. Moves its settings folder (in `base`, normally
    /// ~/Library/Application Support) to the new name, unless a new folder already exists.
    @discardableResult
    public static func migrateAppFolder(in base: URL = FileManager.default.urls(for: .applicationSupportDirectory,
                                                                                in: .userDomainMask)[0]) -> URL {
        let fm = FileManager.default
        let old = base.appendingPathComponent("DesktopCorgi"), new = base.appendingPathComponent(appFolderName)
        if fm.fileExists(atPath: old.path) && !fm.fileExists(atPath: new.path) { try? fm.moveItem(at: old, to: new) }
        return new
    }

    /// Each pet keeps its own needs, level and together-since date.
    public static func fileName(for character: Character) -> String { "state-\(character.rawValue).json" }

    /// Older versions kept one shared state.json. It belongs to the pet that was active then.
    /// Never overwrites a pet's own file.
    public static func migrateLegacy(in directory: URL, to character: Character) {
        let fm = FileManager.default
        let legacy = directory.appendingPathComponent("state.json")
        let target = directory.appendingPathComponent(fileName(for: character))
        guard fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: target.path) else { return }
        try? fm.moveItem(at: legacy, to: target)
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appFolderName)
    }

    public init(directory: URL, fileName: String = "state.json") {
        self.directory = directory
        self.fileName = fileName
    }

    public convenience init(directory: URL, character: Character) {
        self.init(directory: directory, fileName: StateStore.fileName(for: character))
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
