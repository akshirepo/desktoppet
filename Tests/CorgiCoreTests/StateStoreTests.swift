import XCTest
@testable import CorgiCore

final class StateStoreTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("corgi-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testMissingFileLoadsNil() throws {
        XCTAssertNil(try StateStore(directory: dir).load())
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = StateStore(directory: dir)
        var s = NeedsState.fresh(at: Date(timeIntervalSince1970: 1_234_567.5))
        s.hunger = 12.25
        s.isAsleep = true
        s.careXP = 42
        try store.save(s)
        XCTAssertEqual(try store.load(), s)
    }

    func testCorruptFileIsBackedUpAndThrows() throws {
        let store = StateStore(directory: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: store.fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? StateStoreError, .corrupt(backupURL: store.backupURL))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertEqual(try Data(contentsOf: store.backupURL), Data("{not json".utf8))
        XCTAssertNil(try store.load())
    }

    func testSecondCorruptFileReplacesOldBackup() throws {
        let store = StateStore(directory: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("bad1".utf8).write(to: store.fileURL)
        _ = try? store.load()
        try Data("bad2".utf8).write(to: store.fileURL)
        _ = try? store.load()
        XCTAssertEqual(try Data(contentsOf: store.backupURL), Data("bad2".utf8))
    }

    func testEachCharacterHasItsOwnStateFile() throws {
        XCTAssertEqual(StateStore.fileName(for: .corgi), "state-corgi.json")
        XCTAssertEqual(StateStore.fileName(for: .sheep), "state-sheep.json")
        let corgi = StateStore(directory: dir, character: .corgi)
        let sheep = StateStore(directory: dir, character: .sheep)
        var s = NeedsState.fresh(at: Date(timeIntervalSince1970: 100))
        s.hunger = 12
        try corgi.save(s)
        XCTAssertEqual(try corgi.load()?.hunger, 12)
        XCTAssertNil(try sheep.load())
        XCTAssertEqual(sheep.backupURL.lastPathComponent, "state-sheep.corrupt.json")
    }

    func testLegacyStateMovesToTheCharacterItBelongedTo() throws {
        let legacy = StateStore(directory: dir)
        var s = NeedsState.fresh(at: Date(timeIntervalSince1970: 100))
        s.careXP = 42
        try legacy.save(s)
        StateStore.migrateLegacy(in: dir, to: .corgi)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.fileURL.path))
        XCTAssertEqual(try StateStore(directory: dir, character: .corgi).load()?.careXP, 42)
        StateStore.migrateLegacy(in: dir, to: .sheep)              // nothing left to move
        XCTAssertNil(try StateStore(directory: dir, character: .sheep).load())
    }

    func testLegacyMigrationNeverOverwritesExistingCharacterState() throws {
        var mine = NeedsState.fresh(at: Date(timeIntervalSince1970: 100)); mine.careXP = 7
        try StateStore(directory: dir, character: .corgi).save(mine)
        var old = NeedsState.fresh(at: Date(timeIntervalSince1970: 100)); old.careXP = 99
        try StateStore(directory: dir).save(old)
        StateStore.migrateLegacy(in: dir, to: .corgi)
        XCTAssertEqual(try StateStore(directory: dir, character: .corgi).load()?.careXP, 7)
    }

    func testOldAppFolderMovesToTheNewName() throws {
        let base = dir!
        let old = base.appendingPathComponent("DesktopCorgi")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: old.appendingPathComponent("profile.json"))
        let moved = StateStore.migrateAppFolder(in: base)
        XCTAssertEqual(moved.lastPathComponent, "DesktopPet")
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.appendingPathComponent("profile.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
    }

    func testAppFolderMigrationLeavesAnExistingNewFolderAlone() throws {
        let base = dir!
        let old = base.appendingPathComponent("DesktopCorgi"), new = base.appendingPathComponent("DesktopPet")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        StateStore.migrateAppFolder(in: base)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: new.path))
    }
}
