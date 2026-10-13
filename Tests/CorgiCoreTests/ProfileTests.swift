import XCTest
@testable import CorgiCore

final class ProfileTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("corgi-profile-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testDefaults() {
        let p = PetProfile()
        XCTAssertEqual(p.name, "Corgi")
        XCTAssertEqual(p.hat, .none)
        XCTAssertFalse(p.soundsOn)
        XCTAssertFalse(p.askedForName)
        XCTAssertEqual(PetProfile.default, p)
    }

    func testHatCasesAndDisplayNames() {
        XCTAssertEqual(Hat.allCases, [.none, .bow, .partyHat, .beanie, .flowerCrown, .santaHat])
        XCTAssertEqual(Hat.allCases.map(\.displayName),
                       ["None", "Bow", "Party Hat", "Beanie", "Flower Crown", "Santa Hat"])
    }

    func testMissingFileLoadsDefaults() {
        let store = ProfileStore(directory: dir)
        XCTAssertEqual(store.load(), PetProfile())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.backupURL.path))
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = ProfileStore(directory: dir)
        let p = PetProfile(name: "Biscuit", hat: .flowerCrown, soundsOn: true, askedForName: true)
        try store.save(p)
        XCTAssertEqual(store.fileURL.lastPathComponent, "profile.json")
        XCTAssertEqual(store.load(), p)
    }

    func testCorruptFileIsBackedUpAndDefaultsUsed() throws {
        let store = ProfileStore(directory: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{nope".utf8).write(to: store.fileURL)
        XCTAssertEqual(store.load(), PetProfile())
        XCTAssertEqual(store.backupURL.lastPathComponent, "profile.corrupt.json")
        XCTAssertEqual(try Data(contentsOf: store.backupURL), Data("{nope".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testUnknownHatDecodesToNone() throws {
        let json = #"{"name":"Mochi","hat":"tophat","soundsOn":true,"askedForName":true}"#
        let p = try JSONDecoder().decode(PetProfile.self, from: Data(json.utf8))
        XCTAssertEqual(p, PetProfile(name: "Mochi", hat: .none, soundsOn: true, askedForName: true))
    }

    func testUnknownHatInFileLoadsWithoutBackup() throws {
        let store = ProfileStore(directory: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"name":"Mochi","hat":"crown","soundsOn":false,"askedForName":true}"#.utf8)
            .write(to: store.fileURL)
        XCTAssertEqual(store.load().hat, .none)
        XCTAssertEqual(store.load().name, "Mochi")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.backupURL.path))
    }

    func testMissingKeysUseDefaults() throws {
        let p = try JSONDecoder().decode(PetProfile.self, from: Data(#"{"name":"Pip"}"#.utf8))
        XCTAssertEqual(p, PetProfile(name: "Pip"))
    }

    func testSanitizedNameTrims() {
        XCTAssertEqual(PetProfile.sanitizedName("  Biscuit \n", keeping: "Corgi"), "Biscuit")
    }

    func testSanitizedNameCapsAt20() {
        let long = String(repeating: "a", count: 25)
        XCTAssertEqual(PetProfile.sanitizedName(long, keeping: "Corgi"), String(repeating: "a", count: 20))
        XCTAssertEqual(PetProfile.maxNameLength, 20)
    }

    func testSanitizedNameEmptyKeepsOld() {
        XCTAssertEqual(PetProfile.sanitizedName("   ", keeping: "Biscuit"), "Biscuit")
        XCTAssertEqual(PetProfile.sanitizedName("", keeping: "Biscuit"), "Biscuit")
    }

    func testRenameUsesSanitizing() {
        var p = PetProfile()
        p.rename(to: "  Waffles  ")
        XCTAssertEqual(p.name, "Waffles")
        p.rename(to: " ")
        XCTAssertEqual(p.name, "Waffles")
    }

    func testTagTextTruncates() {
        XCTAssertEqual(PetProfile.tagText(for: "Corgi"), "Corgi")
        XCTAssertEqual(PetProfile.tagText(for: "Biscui"), "Biscui")
        XCTAssertEqual(PetProfile.tagText(for: "Biscuit"), "Biscui…")
        XCTAssertEqual(PetProfile(name: "Sir Waffles").tagText, "Sir Wa…")
    }

    func testStatsTitle() {
        XCTAssertEqual(PetProfile(name: "Mochi").statsTitle(level: 3), "Mochi · Level 3")
    }
}
