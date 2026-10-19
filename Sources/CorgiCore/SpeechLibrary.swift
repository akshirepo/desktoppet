import Foundation

/// The pets' little lines (Assets/Bubbles/messages.json): a few per mood for each pet,
/// each mood with its bubble shape and accent doodle. Never says the same line twice in a row.
public struct SpeechLibrary {
    public enum Bubble: String, Decodable { case speech, thought }

    public struct Line: Equatable {
        public let text: String
        public let bubble: Bubble
        public let icon: String?

        public init(text: String, bubble: Bubble, icon: String?) {
            self.text = text
            self.bubble = bubble
            self.icon = icon
        }
    }

    private struct Category: Decodable {
        let id: String
        let icon: String?
        let bubble: [String: Bubble]
        let corgi: [String]
        let sheep: [String]
    }

    private struct File: Decodable { let categories: [Category] }

    private let categories: [String: Category]
    private var lastIndex: [String: Int] = [:]
    private var rng: any RandomNumberGenerator

    public init(data: Data, rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        categories = Dictionary(file.categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.rng = rng
    }

    public mutating func line(for category: String, pet: Character) -> Line? {
        guard let c = categories[category] else { return nil }
        let lines = pet == .sheep ? c.sheep : c.corgi
        guard !lines.isEmpty else { return nil }
        let key = "\(category)/\(pet.rawValue)"
        var i = Int(rng.next() % UInt64(lines.count))
        if lines.count > 1, i == lastIndex[key] { i = (i + 1) % lines.count }
        lastIndex[key] = i
        return Line(text: lines[i], bubble: c.bubble[pet.rawValue] ?? .speech, icon: c.icon)
    }

    /// Which mood speaks for a low need. `variant` alternates the two moods a sad pet can be in.
    public static func category(for need: Need, variant: Int) -> String {
        switch need {
        case .hunger: return "hungry"
        case .cleanliness: return "dirty"
        case .energy: return "sleepy"
        case .happiness: return variant % 2 == 0 ? "affection" : "bored"
        }
    }
}
