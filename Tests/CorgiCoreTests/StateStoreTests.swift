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
}
