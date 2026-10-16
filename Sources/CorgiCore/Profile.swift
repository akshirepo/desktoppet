import Foundation

public enum Character: String, Codable, CaseIterable {
    case corgi, sheep

    public var displayName: String {
        switch self {
        case .corgi: return "Corgi"
        case .sheep: return "Sheep"
        }
    }

    public var packFolderName: String {
        switch self {
        case .corgi: return "CorgiPack"
        case .sheep: return "SheepPack"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Character(rawValue: raw) ?? .corgi
    }
}

public struct PetProfile: Codable, Equatable {
    public static let defaultName = "Corgi"
    public static let maxNameLength = 20

    public var name: String
    public var soundsOn: Bool
    public var askedForName: Bool
    public var character: Character

    public init(name: String = PetProfile.defaultName, soundsOn: Bool = false, askedForName: Bool = false,
                character: Character = .corgi) {
        self.name = name
        self.soundsOn = soundsOn
        self.askedForName = askedForName
        self.character = character
    }

    public static let `default` = PetProfile()

    private enum CodingKeys: String, CodingKey { case name, soundsOn, askedForName, character }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PetProfile()
        name = PetProfile.sanitizedName(try c.decodeIfPresent(String.self, forKey: .name) ?? d.name, keeping: d.name)
        soundsOn = try c.decodeIfPresent(Bool.self, forKey: .soundsOn) ?? d.soundsOn
        askedForName = try c.decodeIfPresent(Bool.self, forKey: .askedForName) ?? d.askedForName
        character = (try? c.decodeIfPresent(Character.self, forKey: .character)) ?? d.character
    }

    public var packFolderName: String { character.packFolderName }

    /// Trims whitespace and caps at 20 characters. Empty input keeps `old`.
    public static func sanitizedName(_ input: String, keeping old: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let capped = String(trimmed.prefix(maxNameLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return capped.isEmpty ? old : capped
    }

    public mutating func rename(to input: String) {
        name = PetProfile.sanitizedName(input, keeping: name)
    }

    public func statsTitle(level: Int) -> String { "\(name) · Level \(level)" }
}

public final class ProfileStore {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("profile.json") }
    public var backupURL: URL { directory.appendingPathComponent("profile.corrupt.json") }

    public init(directory: URL = StateStore.defaultDirectory) {
        self.directory = directory
    }

    /// Missing file gives defaults. A corrupt file is moved to profile.corrupt.json and defaults are returned.
    public func load() -> PetProfile {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return PetProfile() }
        do {
            return try JSONDecoder().decode(PetProfile.self, from: Data(contentsOf: fileURL))
        } catch {
            try? fm.removeItem(at: backupURL)
            try? fm.moveItem(at: fileURL, to: backupURL)
            return PetProfile()
        }
    }

    public func save(_ profile: PetProfile) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profile).write(to: fileURL, options: .atomic)
    }
}
