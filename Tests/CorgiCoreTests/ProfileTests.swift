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
        XCTAssertFalse(p.soundsOn)
        XCTAssertFalse(p.askedForName)
        XCTAssertEqual(p.character, .corgi)
        XCTAssertEqual(PetProfile.default, p)
    }

    func testCharacterNamesAndPackFolders() {
        XCTAssertEqual(Character.allCases, [.corgi, .sheep])
        XCTAssertEqual(Character.allCases.map(\.displayName), ["Corgi", "Sheep"])
        XCTAssertEqual(Character.allCases.map(\.packFolderName), ["CorgiPack", "SheepPack"])
        XCTAssertEqual(PetProfile(character: .sheep).packFolderName, "SheepPack")
    }

    func testOldFilesWithRemovedSettingsStillLoad() throws {
        let json = #"{"name":"Mochi","hat":"bow","showNameTag":true,"sheepCap":false,"soundsOn":true,"askedForName":true,"character":"sheep"}"#
        let p = try JSONDecoder().decode(PetProfile.self, from: Data(json.utf8))
        XCTAssertEqual(p, PetProfile(name: "Mochi", soundsOn: true, askedForName: true, character: .sheep))
    }

    func testMissingAndUnknownCharacterDecodeToCorgi() throws {
        let missing = try JSONDecoder().decode(PetProfile.self, from: Data(#"{"name":"Pip"}"#.utf8))
        XCTAssertEqual(missing, PetProfile(name: "Pip"))
        let unknown = try JSONDecoder().decode(PetProfile.self, from: Data(#"{"character":"dragon"}"#.utf8))
        XCTAssertEqual(unknown.character, .corgi)
    }

    func testEachCharacterHasItsOwnName() {
        var p = PetProfile()
        p.rename(to: "Biscuit")
        XCTAssertEqual(p.name, "Biscuit")
        p.character = .sheep
        XCTAssertEqual(p.name, "Sheep")              // its own default
        p.rename(to: "Wooly")
        p.character = .corgi
        XCTAssertEqual(p.name, "Biscuit")
        p.character = .sheep
        XCTAssertEqual(p.name, "Wooly")
    }

    func testEachCharacterIsAskedForANameOnce() {
        var p = PetProfile()
        p.askedForName = true
        p.character = .sheep
        XCTAssertFalse(p.askedForName)
        p.askedForName = true
        p.character = .corgi
        XCTAssertTrue(p.askedForName)
    }

    func testLegacySingleNameBelongsToTheSavedCharacter() throws {
        let json = #"{"name":"corgbrulee","askedForName":true,"character":"corgi","soundsOn":true}"#
        var p = try JSONDecoder().decode(PetProfile.self, from: Data(json.utf8))
        XCTAssertEqual(p.name, "corgbrulee")
        XCTAssertTrue(p.askedForName)
        p.character = .sheep
        XCTAssertEqual(p.name, "Sheep")
        XCTAssertFalse(p.askedForName)
    }

    func testPerCharacterNamesRoundTrip() throws {
        var p = PetProfile()
        p.rename(to: "Biscuit"); p.askedForName = true
        p.character = .sheep
        p.rename(to: "Wooly")
        let back = try JSONDecoder().decode(PetProfile.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
        XCTAssertEqual(back.name, "Wooly")
    }

    func testMissingFileLoadsDefaults() {
        let store = ProfileStore(directory: dir)
        XCTAssertEqual(store.load(), PetProfile())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.backupURL.path))
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = ProfileStore(directory: dir)
        let p = PetProfile(name: "Biscuit", soundsOn: true, askedForName: true, character: .sheep)
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

    func testSanitizedName() {
        XCTAssertEqual(PetProfile.sanitizedName("  Biscuit \n", keeping: "Corgi"), "Biscuit")
        XCTAssertEqual(PetProfile.sanitizedName(String(repeating: "a", count: 25), keeping: "Corgi"),
                       String(repeating: "a", count: 20))
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

    func testStatsTitle() {
        XCTAssertEqual(PetProfile(name: "Mochi").statsTitle(level: 3), "Mochi · Level 3")
    }

    func testDecodedNameIsSanitized() throws {
        let blank = try JSONDecoder().decode(PetProfile.self, from: Data(#"{"name":"   "}"#.utf8))
        XCTAssertEqual(blank.name, PetProfile.defaultName)
        let long = String(repeating: "b", count: 30)
        let p = try JSONDecoder().decode(PetProfile.self, from: Data("{\"name\":\" \(long) \"}".utf8))
        XCTAssertEqual(p.name, String(repeating: "b", count: 20))
    }
}
