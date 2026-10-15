import Foundation

public enum Hat: String, Codable, CaseIterable {
    case none, bow, partyHat, beanie, flowerCrown, santaHat

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .bow: return "Bow"
        case .partyHat: return "Party Hat"
        case .beanie: return "Beanie"
        case .flowerCrown: return "Flower Crown"
        case .santaHat: return "Santa Hat"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Hat(rawValue: raw) ?? .none
    }
}

public enum Character: String, Codable, CaseIterable {
    case corgi, sheep

    public var displayName: String {
        switch self {
        case .corgi: return "Corgi"
        case .sheep: return "Sheep"
        }
    }

    public func packFolderName(sheepCap: Bool) -> String {
        switch self {
        case .corgi: return "CorgiPack"
        case .sheep: return sheepCap ? "SheepPack" : "SheepNoCapPack"
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
    public static let tagLength = 6

    public var name: String
    public var hat: Hat
    public var soundsOn: Bool
    public var askedForName: Bool
    public var showNameTag: Bool
    public var character: Character
    public var sheepCap: Bool

    public init(name: String = PetProfile.defaultName, hat: Hat = .none,
                soundsOn: Bool = false, askedForName: Bool = false, showNameTag: Bool = false,
                character: Character = .corgi, sheepCap: Bool = true) {
        self.name = name
        self.hat = hat
        self.soundsOn = soundsOn
        self.askedForName = askedForName
        self.showNameTag = showNameTag
        self.character = character
        self.sheepCap = sheepCap
    }

    public static let `default` = PetProfile()

    private enum CodingKeys: String, CodingKey { case name, hat, soundsOn, askedForName, showNameTag, character, sheepCap }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PetProfile()
        name = PetProfile.sanitizedName(try c.decodeIfPresent(String.self, forKey: .name) ?? d.name, keeping: d.name)
        hat = (try? c.decodeIfPresent(Hat.self, forKey: .hat)) ?? d.hat
        soundsOn = try c.decodeIfPresent(Bool.self, forKey: .soundsOn) ?? d.soundsOn
        askedForName = try c.decodeIfPresent(Bool.self, forKey: .askedForName) ?? d.askedForName
        showNameTag = try c.decodeIfPresent(Bool.self, forKey: .showNameTag) ?? d.showNameTag
        character = (try? c.decodeIfPresent(Character.self, forKey: .character)) ?? d.character
        sheepCap = ((try? c.decodeIfPresent(Bool.self, forKey: .sheepCap)) ?? nil) ?? d.sheepCap
    }

    public var packFolderName: String { character.packFolderName(sheepCap: sheepCap) }

    /// Trims whitespace and caps at 20 characters. Empty input keeps `old`.
    public static func sanitizedName(_ input: String, keeping old: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let capped = String(trimmed.prefix(maxNameLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return capped.isEmpty ? old : capped
    }

    public mutating func rename(to input: String) {
        name = PetProfile.sanitizedName(input, keeping: name)
    }

    /// First 6 characters, plus "…" when the name is longer.
    public static func tagText(for name: String) -> String {
        name.count > tagLength ? String(name.prefix(tagLength)) + "…" : name
    }

    public var tagText: String { PetProfile.tagText(for: name) }

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
