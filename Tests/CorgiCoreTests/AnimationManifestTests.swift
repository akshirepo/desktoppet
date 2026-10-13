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
        XCTAssertEqual(animState(for: .walk, mode: .held, isMoving: false), .scared)
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
        XCTAssertEqual(animState(for: .greet, mode: .grounded, isMoving: false), .wave)
        XCTAssertEqual(animState(for: .idle, mode: .grounded, isMoving: false), .idle)
    }

    func testCompanionBehaviorsToAnimation() {
        XCTAssertEqual(animState(for: .chaseMe, mode: .roaming, isMoving: true), .roam)
        XCTAssertEqual(animState(for: .ballChase, mode: .roaming, isMoving: true, carrying: true), .holdBall)
        XCTAssertEqual(animState(for: .goHome, mode: .grounded, isMoving: true), .walk)
        XCTAssertEqual(animState(for: .goHome, mode: .grounded, isMoving: true, isRunning: true), .run)
        XCTAssertEqual(animState(for: .wave, mode: .grounded, isMoving: false), .wave)
        XCTAssertEqual(animState(for: .turnAround, mode: .grounded, isMoving: false), .back)
        XCTAssertEqual(animState(for: .read, mode: .grounded, isMoving: false), .read)
        XCTAssertEqual(animState(for: .readSleep, mode: .grounded, isMoving: false), .readSleep)
        XCTAssertEqual(animState(for: .music, mode: .grounded, isMoving: false), .music)
        XCTAssertEqual(animState(for: .watchTV, mode: .grounded, isMoving: false), .watch)
        XCTAssertEqual(animState(for: .yawn, mode: .grounded, isMoving: false), .yawn)
        XCTAssertEqual(animState(for: .idleSleep, mode: .grounded, isMoving: false), .sleep)
        XCTAssertEqual(animState(for: .playBallHome, mode: .grounded, isMoving: false), .kick)
    }

    func testNewStatesFallBackToIdleInOldPacks() throws {
        XCTAssertEqual(AnimState.allCases.count, 25)
        let m = try AnimationManifest.load(from: write(sample))
        for s in [AnimState.wave, .back, .read, .readSleep, .music, .watch, .yawn, .scared, .happy, .holdBall, .kick, .roam] {
            XCTAssertEqual(m.resolve(s)?.state, .idle, "\(s)")
            XCTAssertTrue(m.missingStates.contains(s), "\(s)")
        }
    }
}
