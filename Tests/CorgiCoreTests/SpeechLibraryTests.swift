import XCTest
@testable import CorgiCore

final class SpeechLibraryTests: XCTestCase {
    static let json = """
    {"version":1,"categories":[
      {"id":"hungry","icon":"star","bubble":{"corgi":"speech","sheep":"thought"},
       "corgi":["Snack?","Treat?","Crumbs?"],"sheep":["Nibble?"]},
      {"id":"happy","icon":"hearts","bubble":{"corgi":"speech","sheep":"speech"},"corgi":["Yay!"],"sheep":["Comfy."]}
    ]}
    """

    func library(seed: UInt64 = 1) throws -> SpeechLibrary {
        try SpeechLibrary(data: Data(Self.json.utf8), rng: SeededRandom(seed: seed))
    }

    func testPicksALineWithItsBubbleAndIcon() throws {
        var lib = try library()
        let line = try XCTUnwrap(lib.line(for: "hungry", pet: .sheep))
        XCTAssertEqual(line.text, "Nibble?")
        XCTAssertEqual(line.bubble, .thought)
        XCTAssertEqual(line.icon, "star")
        XCTAssertEqual(lib.line(for: "hungry", pet: .corgi)?.bubble, .speech)
    }

    func testNeverRepeatsTheSameLineTwiceInARow() throws {
        var lib = try library(seed: 9)
        var last = lib.line(for: "hungry", pet: .corgi)?.text
        for _ in 0..<50 {
            let next = lib.line(for: "hungry", pet: .corgi)?.text
            XCTAssertNotEqual(next, last)
            last = next
        }
    }

    func testSingleLineCategoriesStillWorkAndUnknownOnesReturnNil() throws {
        var lib = try library()
        XCTAssertEqual(lib.line(for: "happy", pet: .corgi)?.text, "Yay!")
        XCTAssertEqual(lib.line(for: "happy", pet: .corgi)?.text, "Yay!")
        XCTAssertNil(lib.line(for: "dragons", pet: .corgi))
    }

    func testNeedsMapToMoods() {
        XCTAssertEqual(SpeechLibrary.category(for: .hunger, variant: 0), "hungry")
        XCTAssertEqual(SpeechLibrary.category(for: .cleanliness, variant: 0), "dirty")
        XCTAssertEqual(SpeechLibrary.category(for: .energy, variant: 0), "sleepy")
        XCTAssertEqual(SpeechLibrary.category(for: .happiness, variant: 0), "affection")
        XCTAssertEqual(SpeechLibrary.category(for: .happiness, variant: 1), "bored")
    }

    func testBundledMessagesCoverEveryMoodForBothPets() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Assets/Bubbles/messages.json")
        var lib = try SpeechLibrary(data: Data(contentsOf: url), rng: SeededRandom(seed: 1))
        for mood in ["hungry", "affection", "bored", "sleepy", "company", "happy", "dirty"] {
            for pet in Character.allCases {
                let line = try XCTUnwrap(lib.line(for: mood, pet: pet), "\(mood) \(pet)")
                XCTAssertFalse(line.text.isEmpty)
                XCTAssertLessThanOrEqual(line.text.count, 28, line.text)   // fits two short lines
            }
        }
    }
}
