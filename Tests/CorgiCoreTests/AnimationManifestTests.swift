import XCTest
@testable import CorgiCore

final class AnimationManifestTests: XCTestCase {
    func write(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("manifest-\(UUID()).json")
        try Data(json.utf8).write(to: url)
        return url
    }

    let sample = """
    { "scale": 0.5, "states": {
        "idle": { "folder": "idle", "fps": 8, "loop": true, "anchor": [0.5, 0] },
        "walk": { "folder": "walk", "fps": 12, "loop": true, "anchor": [0.5, 0.1] } } }
    """

    func testLoadsManifest() throws {
        let m = try AnimationManifest.load(from: write(sample))
        XCTAssertEqual(m.scale, 0.5)
        XCTAssertEqual(m.states["walk"], AnimationSpec(folder: "walk", fps: 12, loop: true, anchor: [0.5, 0.1]))
    }

    func testMissingStateFallsBackToIdle() throws {
        let m = try AnimationManifest.load(from: write(sample))
        XCTAssertEqual(m.resolve(.walk)?.state, .walk)
        XCTAssertEqual(m.resolve(.bath)?.state, .idle)
        XCTAssertEqual(m.resolve(.bath)?.spec.folder, "idle")
        XCTAssertEqual(m.missingStates.count, AnimState.allCases.count - 2)
        XCTAssertFalse(m.missingStates.contains(.walk))
    }

    func testManifestWithoutIdleIsRejected() throws {
        let url = try write(#"{ "states": { "walk": { "folder": "w", "fps": 8, "loop": true, "anchor": [0.5, 0] } } }"#)
        XCTAssertThrowsError(try AnimationManifest.load(from: url)) {
            XCTAssertEqual($0 as? AnimationManifestError, .missingIdle)
        }
    }

    func testBehaviorToAnimation() {
        XCTAssertEqual(animState(for: .walk, mode: .held, isMoving: false), .dangle)
        XCTAssertEqual(animState(for: .hopToWindow, mode: .airborne, isMoving: true), .fall)
        XCTAssertEqual(animState(for: .walk, mode: .grounded, isMoving: true), .walk)
        XCTAssertEqual(animState(for: .zoomies, mode: .grounded, isMoving: true), .run)
        XCTAssertEqual(animState(for: .chaseCursor, mode: .grounded, isMoving: true), .run)
        XCTAssertEqual(animState(for: .chaseCursor, mode: .grounded, isMoving: false), .sit)
        XCTAssertEqual(animState(for: .fetch, mode: .grounded, isMoving: true), .run)
        XCTAssertEqual(animState(for: .fetch, mode: .grounded, isMoving: false), .fetch)
        XCTAssertEqual(animState(for: .sleep, mode: .grounded, isMoving: false), .sleep)
        XCTAssertEqual(animState(for: .beg, mode: .grounded, isMoving: false), .beg)
        XCTAssertEqual(animState(for: .eat, mode: .grounded, isMoving: false), .eat)
        XCTAssertEqual(animState(for: .bath, mode: .grounded, isMoving: false), .bath)
        XCTAssertEqual(animState(for: .greet, mode: .grounded, isMoving: false), .wiggle)
        XCTAssertEqual(animState(for: .idle, mode: .grounded, isMoving: false), .idle)
    }
}
