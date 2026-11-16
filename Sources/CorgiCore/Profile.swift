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

/// How speech and thought bubbles are drawn.
public enum BubbleStyle: String, Codable, CaseIterable {
    /// A small light capsule fitted to the text.
    case pill
    /// The same capsule, dark with light text.
    case dark
    /// Just the words, outlined, with nothing behind them.
    case text
    /// Only the little icon in a round bubble; a line without an icon falls back to the capsule.
    case icon
    /// A square-cornered box with a chunky edge, like the pets' pixel art.
    case pixel
    /// The original hand-drawn bubble artwork, one size for every line.
    case classic

    public var displayName: String {
        switch self {
        case .pill: return "Small Light"
        case .dark: return "Small Dark"
        case .text: return "Words Only"
        case .icon: return "Icon Only"
        case .pixel: return "Pixel Box"
        case .classic: return "Classic (large)"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BubbleStyle(rawValue: raw) ?? .pill
    }
}

/// The typeface for the words in a bubble.
public enum BubbleFont: String, Codable, CaseIterable {
    case pixel, pixelCaps, terminal, rounded, clean, handwritten, note, marker, comic, typewriter, serif

    public var displayName: String {
        switch self {
        case .pixel: return "Pixel"
        case .pixelCaps: return "Pixel Caps"
        case .terminal: return "Retro Terminal"
        case .rounded: return "Rounded"
        case .clean: return "Clean"
        case .handwritten: return "Chalkboard"
        case .note: return "Handwritten Note"
        case .marker: return "Marker"
        case .comic: return "Comic"
        case .typewriter: return "Typewriter"
        case .serif: return "Storybook"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BubbleFont(rawValue: raw) ?? .pixel
    }
}

public struct PetProfile: Codable, Equatable {
    public static let defaultName = "Corgi"
    public static let maxNameLength = 20

    /// Each pet's own name, keyed by character. Missing means its default (the character's display name).
    public private(set) var names: [String: String] = [:]
    /// Pets that have already been asked for a name.
    public private(set) var askedNames: Set<String> = []
    public var soundsOn: Bool
    public var character: Character
    /// Start the app when you log in. Re-applied on every launch so rebuilt or moved apps stay registered.
    public var launchAtLogin = false
    /// Now and then, come to the cursor and ask for food, a bath, play or a nap when a need is low.
    public var askForCare = true
    public var bubbleStyle = BubbleStyle.pill
    public var bubbleFont = BubbleFont.pixel

    public init(name: String? = nil, soundsOn: Bool = false, askedForName: Bool = false,
                character: Character = .corgi) {
        self.soundsOn = soundsOn
        self.character = character
        if let name { names[character.rawValue] = name }
        if askedForName { askedNames.insert(character.rawValue) }
    }

    public static let `default` = PetProfile()

    /// The current pet's name.
    public var name: String {
        get { names[character.rawValue] ?? character.displayName }
        set { names[character.rawValue] = newValue }
    }

    /// Whether the current pet has been asked for a name yet.
    public var askedForName: Bool {
        get { askedNames.contains(character.rawValue) }
        set { if newValue { askedNames.insert(character.rawValue) } else { askedNames.remove(character.rawValue) } }
    }

    private enum CodingKeys: String, CodingKey { case names, askedNames, soundsOn, character, launchAtLogin, askForCare, bubbleStyle, bubbleFont, name, askedForName }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        soundsOn = try c.decodeIfPresent(Bool.self, forKey: .soundsOn) ?? false
        character = (try? c.decodeIfPresent(Character.self, forKey: .character)) ?? .corgi
        launchAtLogin = (try? c.decodeIfPresent(Bool.self, forKey: .launchAtLogin)) ?? false
        askForCare = (try? c.decodeIfPresent(Bool.self, forKey: .askForCare)) ?? true
        bubbleStyle = (try? c.decodeIfPresent(BubbleStyle.self, forKey: .bubbleStyle)) ?? .pill
        bubbleFont = (try? c.decodeIfPresent(BubbleFont.self, forKey: .bubbleFont)) ?? .pixel
        let stored = (try? c.decodeIfPresent([String: String].self, forKey: .names)) ?? [:]
        for (key, value) in stored {
            guard let pet = Character(rawValue: key) else { continue }
            names[key] = PetProfile.sanitizedName(value, keeping: pet.displayName)
        }
        askedNames = Set((try? c.decodeIfPresent([String].self, forKey: .askedNames)) ?? [])
        // Older versions had one name and one prompt flag; they belong to the pet that was active then.
        if let legacy = try c.decodeIfPresent(String.self, forKey: .name), names[character.rawValue] == nil {
            names[character.rawValue] = PetProfile.sanitizedName(legacy, keeping: character.displayName)
        }
        if (try c.decodeIfPresent(Bool.self, forKey: .askedForName)) == true { askedNames.insert(character.rawValue) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(names, forKey: .names)
        try c.encode(askedNames.sorted(), forKey: .askedNames)
        try c.encode(soundsOn, forKey: .soundsOn)
        try c.encode(character, forKey: .character)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(askForCare, forKey: .askForCare)
        try c.encode(bubbleStyle, forKey: .bubbleStyle)
        try c.encode(bubbleFont, forKey: .bubbleFont)
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
