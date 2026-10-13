# Desktop Corgi Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A menu bar macOS app with a Tamagotchi-style cartoon corgi that walks the screen bottom, hops onto window top edges, has needs, and reacts to petting, dragging, feeding, play, bath, and the cursor.

**Architecture:** A Swift package with two targets. `CorgiCore` is pure Foundation logic (needs, persistence, world geometry, physics, brain, behavior steering, animation manifest) and is fully unit tested. `DesktopCorgi` is the AppKit/SpriteKit/SwiftUI shell (overlay windows, window list, rendering, input, menus) and is verified by a manual checklist.

**Tech Stack:** Swift 5.9+, Swift Package Manager, XCTest, AppKit, SpriteKit, SwiftUI, ServiceManagement. No third party dependencies.

**Spec:** `docs/superpowers/specs/2026-10-11-desktop-corgi-design.md`

## Global Constraints

- macOS 14+ only (`platforms: [.macOS(.v14)]`).
- Must be built and run on a Mac with Xcode installed. The Linux cloud desktop has no Swift toolchain.
- No third party packages in v1.
- Menu bar only, no Dock icon (`LSUIElement = true` and `.accessory` activation policy).
- Need rates/hr: hunger -8, happiness -5, energy -6 awake / +20 asleep, cleanliness -3.
- Restores: feed +40, pet +5 (max 10 pets/min), play +25, bath +60.
- Low threshold 30. Offline catch-up floor 15. Fresh/corrupt reset value 70.
- State file: `~/Library/Application Support/DesktopCorgi/state.json`, saved every 60s and on quit. Corrupt file backed up as `state.corrupt.json`.
- Asset pack folder: `~/Library/Application Support/DesktopCorgi/CorgiPack/` with `manifest.json`.
- Window list via `CGWindowListCopyWindowInfo(.optionOnScreenOnly)`, layer 0 only, refreshed every 0.5s and on app activation. No Accessibility or Screen Recording permission.
- Frame rate: 30fps moving, 10fps idle/sleeping, paused when screen locked or asleep.
- Greeting plays on launch if away more than 1 hour. v2 (Task 24): wave + "Hi!" on every launch, plus "Missed you!" if away more than 1 hour.
- Coordinates: all `CorgiCore` geometry uses AppKit global coordinates (origin bottom-left of the primary screen, y up). Positions are the corgi's feet.
- Linux dev builds: `CorgiCore` must also build and test on Linux (Swift 6.4 at `~/.local/swift-6.4.0/usr/bin`). In `CorgiCore`, write `#if canImport(CoreGraphics)` / `import CoreGraphics` / `#endif` instead of a bare `import CoreGraphics`, and keep `Sources/CorgiCore/LinuxShims.swift` (created in Task 1) defining `CGVector` (Equatable, Hashable, `init(dx:dy:)`, `.zero`) inside `#if !canImport(CoreGraphics)`. Every file in `Sources/DesktopCorgi` is wrapped in `#if canImport(AppKit)` ... `#endif`; `main.swift` has an `#else` branch that prints "DesktopCorgi needs macOS". `swift test` must pass on Linux and macOS.

## Review Focus

- A window whose top edge is covered by a window in front of it: corgi must not stand on the hidden part. Test in Task 4.
- A maximized window whose top edge sits at the top of the visible screen: no perch there (corgi would overlap the menu bar). Test in Task 4.
- The system clock jumps backwards (manual time change, restored backup): elapsed time is treated as zero, stats never go up from decay. Test in Task 1.
- A window moves or closes while the corgi is being held or is mid-jump: no ride-along, no forced drop while held. Test in Task 6.
- A monitor is unplugged while the corgi is on it: corgi is clamped back onto a remaining screen. Test in Task 6.
- v2: Idle sleep while the user is dragging the corgi, or a drag starting mid-yawn: no sleep, the yawn is cancelled. Test in Task 22.
- v2: Full screen turns on during Chase Me: the corgi keeps roaming and only sleeps once Chase Me ends. Test in Task 22.
- v2: The monitor the ball (or the roaming corgi) is on gets unplugged: both are pulled back onto a remaining screen. Tests in Tasks 18 and 23.
- v2: Hover pet while the corgi is asleep or held: no pet, and the hover timer starts over. Test in Task 22.
- v2: Home spot on a monitor that was unplugged: home moves to the remaining screen, and there is no home with no screens. Test in Task 21.

## File Structure

```
corgi-pet/
  Package.swift
  Sources/CorgiCore/
    Clock.swift              Clock protocol + SystemClock
    SeededRandom.swift       SplitMix64 RNG for deterministic tests
    Needs.swift              Need, NeedsConfig, NeedsState, NeedsEngine
    StateStore.swift         JSON save/load, corrupt-file backup
    Geometry.swift           WindowInfo, FloorSegment, coord conversion, interval subtraction
    World.swift              WindowListProvider, World, WorldUpdate
    Body.swift               BodyConfig, Body physics (walk, jump, gravity, held, carry, clamp)
    Brain.swift              Behavior, BrainConfig, Brain (weights, weighted pick, interrupts)
    BehaviorExecutor.swift   Per-tick steering for each behavior
    AnimationManifest.swift  AnimState, AnimationSpec, AnimationManifest, behavior->anim mapping
    Home.swift               HomeTracker (home spot, time away), Greeting lines (v2)
    Rest.swift               isFullScreen, RestMonitor (idle and full screen sleep) (v2)
    Attention.swift          HoverPet, BoredomTimer (v2)
    Ball.swift               Ball path model for the ball chase (v2)
  Sources/DesktopCorgi/
    main.swift               App entry
    AppDelegate.swift        Lifecycle, status item, timers, save, lock/sleep observers
    LoginItem.swift          SMAppService wrapper
    CGWindowListProvider.swift  Real WindowListProvider
    OverlayWindow.swift      Transparent click-through NSPanel + OverlayScene
    OverlayManager.swift     One overlay per screen, moves the corgi node between them
    Animation/AnimationBackend.swift      Protocol
    Animation/PlaceholderBackend.swift    Code-drawn corgi
    Animation/FrameSequenceBackend.swift  PNG frames from the asset pack
    PetController.swift      Wires needs, brain, body, world, executor, animation, input
    Effects.swift            Hearts, bubbles, zzz, ball node
    PetMenu.swift            NSMenu builder for right-click and status item
    StatsView.swift          SwiftUI stats popover + observable model
    DebugOverlay.swift       Floor lines, hit box, behavior label
  Tests/CorgiCoreTests/
    FakeClock.swift
    NeedsTests.swift
    StateStoreTests.swift
    WorldTests.swift
    BodyTests.swift
    BrainTests.swift
    BehaviorExecutorTests.swift
    AnimationManifestTests.swift
    RoamingBodyTests.swift   (v2)
    HomeTests.swift          (v2)
    RestTests.swift          RestTests + AttentionTests (v2)
    BallTests.swift          BallTests + RoamSteeringTests (v2)
  scripts/bundle.sh          Builds DesktopCorgi.app (Info.plist, ad-hoc signed)
  docs/MANUAL_CHECKLIST.md
  README.md
```

## Setup (once, on the Mac)

- [ ] Install Xcode from the App Store, open it once to accept the license, then run `xcode-select -p` and confirm it prints a path inside `Xcode.app`.
- [ ] Copy the repo from the cloud desktop to the Mac (run on the Mac): `rsync -av <cloud-desktop-host>:~/corgi-pet/ ~/corgi-pet/`
- [ ] `cd ~/corgi-pet && git log --oneline` shows the spec and plan commits.

---

### Task 1: Package scaffold, Clock, and needs decay

**Files:**
- Create: `Package.swift`
- Create: `Sources/CorgiCore/Clock.swift`
- Create: `Sources/CorgiCore/Needs.swift`
- Create: `Sources/DesktopCorgi/main.swift` (temporary stub so the package builds)
- Create: `Tests/CorgiCoreTests/FakeClock.swift`
- Test: `Tests/CorgiCoreTests/NeedsTests.swift`

**Interfaces:**
- Produces:
  - `protocol Clock { var now: Date { get } }`, `struct SystemClock: Clock`
  - `enum Need: String, Codable, CaseIterable { hunger, happiness, energy, cleanliness }`
  - `struct NeedsConfig: Codable, Equatable` (fields below, `static let default`)
  - `struct NeedsState: Codable, Equatable { hunger, happiness, energy, cleanliness: Double; isAsleep: Bool; careXP: Int; lastSaved: Date; firstMet: Date; static func fresh(at: Date) -> NeedsState; subscript(Need) -> Double }`
  - `final class NeedsEngine { init(state:config:clock:); private(set) var state: NeedsState; let config: NeedsConfig; func catchUpOffline() -> TimeInterval; func tick(); func isLow(_ need: Need) -> Bool }`

- [ ] **Step 1: Create the package skeleton**

`Package.swift`:
```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DesktopCorgi",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CorgiCore"),
        .executableTarget(name: "DesktopCorgi", dependencies: ["CorgiCore"]),
        .testTarget(name: "CorgiCoreTests", dependencies: ["CorgiCore"]),
    ]
)
```

`Sources/DesktopCorgi/main.swift` (replaced in Task 9):
```swift
print("DesktopCorgi stub")
```

`Sources/CorgiCore/Clock.swift`:
```swift
import Foundation

public protocol Clock {
    var now: Date { get }
}

public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}
```

`Tests/CorgiCoreTests/FakeClock.swift`:
```swift
import Foundation
@testable import CorgiCore

final class FakeClock: Clock {
    var now: Date
    init(_ now: Date = Date(timeIntervalSince1970: 1_000_000)) { self.now = now }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/CorgiCoreTests/NeedsTests.swift`:
```swift
import XCTest
@testable import CorgiCore

final class NeedsTests: XCTestCase {
    func makeEngine(_ clock: FakeClock, state: NeedsState? = nil) -> NeedsEngine {
        NeedsEngine(state: state ?? .fresh(at: clock.now), config: .default, clock: clock)
    }

    func testFreshStateIsSeventy() {
        let s = NeedsState.fresh(at: Date(timeIntervalSince1970: 0))
        for need in Need.allCases { XCTAssertEqual(s[need], 70) }
        XCTAssertFalse(s.isAsleep)
        XCTAssertEqual(s.careXP, 0)
    }

    func testTickDecaysByHourlyRates() {
        let clock = FakeClock()
        let engine = makeEngine(clock)
        clock.advance(3600)
        engine.tick()
        XCTAssertEqual(engine.state.hunger, 62, accuracy: 0.001)
        XCTAssertEqual(engine.state.happiness, 65, accuracy: 0.001)
        XCTAssertEqual(engine.state.energy, 64, accuracy: 0.001)
        XCTAssertEqual(engine.state.cleanliness, 67, accuracy: 0.001)
    }

    func testEnergyRisesWhileAsleepAndCapsAt100() {
        let clock = FakeClock()
        var s = NeedsState.fresh(at: clock.now)
        s.isAsleep = true
        let engine = makeEngine(clock, state: s)
        clock.advance(3600 * 3)
        engine.tick()
        XCTAssertEqual(engine.state.energy, 100)
    }

    func testLiveTickClampsAtZero() {
        let clock = FakeClock()
        let engine = makeEngine(clock)
        clock.advance(3600 * 20)
        engine.tick()
        XCTAssertEqual(engine.state.hunger, 0)
    }

    func testOfflineCatchUpStopsAtFloor() {
        let clock = FakeClock()
        let engine = makeEngine(clock)
        clock.advance(3600 * 48)
        let away = engine.catchUpOffline()
        XCTAssertEqual(away, 3600 * 48, accuracy: 0.001)
        for need in Need.allCases { XCTAssertEqual(engine.state[need], 15, accuracy: 0.001) }
    }

    func testOfflineCatchUpDoesNotRaiseStatsAlreadyBelowFloor() {
        let clock = FakeClock()
        var s = NeedsState.fresh(at: clock.now)
        s.hunger = 5
        let engine = makeEngine(clock, state: s)
        clock.advance(3600)
        engine.catchUpOffline()
        XCTAssertEqual(engine.state.hunger, 5)
    }

    func testClockGoingBackwardsChangesNothing() {
        let clock = FakeClock()
        let engine = makeEngine(clock)
        clock.advance(-3600)
        XCTAssertEqual(engine.catchUpOffline(), 0)
        engine.tick()
        for need in Need.allCases { XCTAssertEqual(engine.state[need], 70) }
    }

    func testIsLowUsesThreshold() {
        let clock = FakeClock()
        var s = NeedsState.fresh(at: clock.now)
        s.hunger = 29.9
        s.energy = 30
        let engine = makeEngine(clock, state: s)
        XCTAssertTrue(engine.isLow(.hunger))
        XCTAssertFalse(engine.isLow(.energy))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter NeedsTests`
Expected: compile error, `cannot find 'NeedsEngine' in scope`.

- [ ] **Step 4: Implement**

`Sources/CorgiCore/Needs.swift`:
```swift
import Foundation

public enum Need: String, Codable, CaseIterable {
    case hunger, happiness, energy, cleanliness
}

public struct NeedsConfig: Codable, Equatable {
    public var hungerPerHour = -8.0
    public var happinessPerHour = -5.0
    public var energyAwakePerHour = -6.0
    public var energyAsleepPerHour = 20.0
    public var cleanlinessPerHour = -3.0
    public var lowThreshold = 30.0
    public var offlineFloor = 15.0
    public var feedAmount = 40.0
    public var petAmount = 5.0
    public var petsPerMinute = 10
    public var playAmount = 25.0
    public var bathAmount = 60.0

    public init() {}
    public static let `default` = NeedsConfig()
}

public struct NeedsState: Codable, Equatable {
    public var hunger: Double
    public var happiness: Double
    public var energy: Double
    public var cleanliness: Double
    public var isAsleep: Bool
    public var careXP: Int
    public var lastSaved: Date
    public var firstMet: Date

    public static func fresh(at date: Date) -> NeedsState {
        NeedsState(hunger: 70, happiness: 70, energy: 70, cleanliness: 70,
                   isAsleep: false, careXP: 0, lastSaved: date, firstMet: date)
    }

    public subscript(need: Need) -> Double {
        get {
            switch need {
            case .hunger: return hunger
            case .happiness: return happiness
            case .energy: return energy
            case .cleanliness: return cleanliness
            }
        }
        set {
            switch need {
            case .hunger: hunger = newValue
            case .happiness: happiness = newValue
            case .energy: energy = newValue
            case .cleanliness: cleanliness = newValue
            }
        }
    }
}

public final class NeedsEngine {
    public private(set) var state: NeedsState
    public let config: NeedsConfig
    let clock: Clock
    private var lastTick: Date

    public init(state: NeedsState, config: NeedsConfig = .default, clock: Clock) {
        self.state = state
        self.config = config
        self.clock = clock
        self.lastTick = clock.now
    }

    func ratePerHour(_ need: Need, asleep: Bool) -> Double {
        switch need {
        case .hunger: return config.hungerPerHour
        case .happiness: return config.happinessPerHour
        case .energy: return asleep ? config.energyAsleepPerHour : config.energyAwakePerHour
        case .cleanliness: return config.cleanlinessPerHour
        }
    }

    /// Applies decay since `state.lastSaved`, never pushing a need below the offline floor.
    @discardableResult
    public func catchUpOffline() -> TimeInterval {
        let elapsed = max(0, clock.now.timeIntervalSince(state.lastSaved))
        let hours = elapsed / 3600
        for need in Need.allCases {
            let old = state[need]
            let decayed = old + ratePerHour(need, asleep: false) * hours
            state[need] = min(100, max(min(old, config.offlineFloor), decayed))
        }
        lastTick = clock.now
        return elapsed
    }

    public func tick() {
        let now = clock.now
        let hours = max(0, now.timeIntervalSince(lastTick)) / 3600
        lastTick = max(lastTick, now)
        for need in Need.allCases {
            state[need] = min(100, max(0, state[need] + ratePerHour(need, asleep: state.isAsleep) * hours))
        }
    }

    public func isLow(_ need: Need) -> Bool {
        state[need] < config.lowThreshold
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter NeedsTests`
Expected: 8 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: package scaffold and needs decay"
```

### Task 2: Care actions, pet rate limit, level

**Files:**
- Modify: `Sources/CorgiCore/Needs.swift` (inside `NeedsEngine`)
- Test: `Tests/CorgiCoreTests/NeedsTests.swift` (append a new test class)

**Interfaces:**
- Consumes: `NeedsEngine`, `NeedsConfig`, `NeedsState` from Task 1.
- Produces on `NeedsEngine`: `func feed()`, `func play()`, `func bath()`, `@discardableResult func pet() -> Bool`, `func setAsleep(_ asleep: Bool)`, `func markSaved()`, `var level: Int`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/CorgiCoreTests/NeedsTests.swift`:
```swift
final class CareActionTests: XCTestCase {
    func engine(_ clock: FakeClock) -> NeedsEngine {
        NeedsEngine(state: .fresh(at: clock.now), config: .default, clock: clock)
    }

    func testFeedPlayBathRestoreAndCapAt100() {
        let clock = FakeClock()
        let e = engine(clock)
        e.feed()
        XCTAssertEqual(e.state.hunger, 100)
        e.bath()
        XCTAssertEqual(e.state.cleanliness, 100)
        e.play()
        XCTAssertEqual(e.state.happiness, 95)
        XCTAssertEqual(e.state.careXP, 3)
    }

    func testPetIsRateLimitedToTenPerMinute() {
        let clock = FakeClock()
        var s = NeedsState.fresh(at: clock.now)
        s.happiness = 0
        let e = NeedsEngine(state: s, config: .default, clock: clock)
        for _ in 0..<10 { XCTAssertTrue(e.pet()); clock.advance(1) }
        XCTAssertFalse(e.pet())
        XCTAssertEqual(e.state.happiness, 50, accuracy: 0.1)
        XCTAssertEqual(e.state.careXP, 10)
        clock.advance(60)
        XCTAssertTrue(e.pet())
    }

    func testActionsApplyPendingDecayFirst() {
        let clock = FakeClock()
        let e = engine(clock)
        clock.advance(3600)
        e.bath()
        XCTAssertEqual(e.state.hunger, 62, accuracy: 0.001)
        XCTAssertEqual(e.state.cleanliness, 100)
    }

    func testSetAsleepSwitchesEnergyRate() {
        let clock = FakeClock()
        let e = engine(clock)
        e.setAsleep(true)
        clock.advance(3600)
        e.tick()
        XCTAssertEqual(e.state.energy, 90, accuracy: 0.001)
        e.setAsleep(false)
        clock.advance(3600)
        e.tick()
        XCTAssertEqual(e.state.energy, 84, accuracy: 0.001)
    }

    func testMarkSavedStampsNow() {
        let clock = FakeClock()
        let e = engine(clock)
        clock.advance(120)
        e.markSaved()
        XCTAssertEqual(e.state.lastSaved, clock.now)
    }

    func testLevelGrowsWithCareXP() {
        let clock = FakeClock()
        var s = NeedsState.fresh(at: clock.now)
        let cases: [(Int, Int)] = [(0, 1), (9, 1), (10, 2), (40, 3), (90, 4)]
        for (xp, level) in cases {
            s.careXP = xp
            XCTAssertEqual(NeedsEngine(state: s, clock: clock).level, level, "xp \(xp)")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CareActionTests`
Expected: compile error, `value of type 'NeedsEngine' has no member 'feed'`.

- [ ] **Step 3: Implement**

Add inside `final class NeedsEngine` in `Sources/CorgiCore/Needs.swift`, below `isLow`:
```swift
    private var petTimes: [Date] = []

    public var level: Int {
        1 + Int((Double(state.careXP) / 10).squareRoot())
    }

    private func restore(_ need: Need, by amount: Double) {
        tick()
        state[need] = min(100, state[need] + amount)
        state.careXP += 1
    }

    public func feed() { restore(.hunger, by: config.feedAmount) }
    public func play() { restore(.happiness, by: config.playAmount) }
    public func bath() { restore(.cleanliness, by: config.bathAmount) }

    /// Returns false when the per-minute pet limit is reached.
    @discardableResult
    public func pet() -> Bool {
        let now = clock.now
        petTimes.removeAll { now.timeIntervalSince($0) >= 60 }
        guard petTimes.count < config.petsPerMinute else { return false }
        petTimes.append(now)
        restore(.happiness, by: config.petAmount)
        return true
    }

    public func setAsleep(_ asleep: Bool) {
        tick()
        state.isAsleep = asleep
    }

    public func markSaved() {
        tick()
        state.lastSaved = clock.now
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "NeedsTests|CareActionTests"`
Expected: 14 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CorgiCore/Needs.swift Tests/CorgiCoreTests/NeedsTests.swift
git commit -m "feat: care actions, pet rate limit, level"
```

### Task 3: StateStore persistence

**Files:**
- Create: `Sources/CorgiCore/StateStore.swift`
- Test: `Tests/CorgiCoreTests/StateStoreTests.swift`

**Interfaces:**
- Consumes: `NeedsState` from Task 1.
- Produces:
  - `enum StateStoreError: Error, Equatable { case corrupt(backupURL: URL) }`
  - `final class StateStore { init(directory: URL); static var defaultDirectory: URL; var fileURL: URL; var backupURL: URL; func load() throws -> NeedsState?; func save(_ state: NeedsState) throws }`
  - `load()` returns `nil` when no file exists, throws `.corrupt` after moving a bad file to `backupURL`.

- [ ] **Step 1: Write the failing tests**

`Tests/CorgiCoreTests/StateStoreTests.swift`:
```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter StateStoreTests`
Expected: compile error, `cannot find 'StateStore' in scope`.

- [ ] **Step 3: Implement**

`Sources/CorgiCore/StateStore.swift`:
```swift
import Foundation

public enum StateStoreError: Error, Equatable {
    case corrupt(backupURL: URL)
}

public final class StateStore {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("state.json") }
    public var backupURL: URL { directory.appendingPathComponent("state.corrupt.json") }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DesktopCorgi")
    }

    public init(directory: URL) {
        self.directory = directory
    }

    public func load() throws -> NeedsState? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return nil }
        do {
            return try JSONDecoder().decode(NeedsState.self, from: Data(contentsOf: fileURL))
        } catch {
            try? fm.removeItem(at: backupURL)
            try fm.moveItem(at: fileURL, to: backupURL)
            throw StateStoreError.corrupt(backupURL: backupURL)
        }
    }

    public func save(_ state: NeedsState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter StateStoreTests`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CorgiCore/StateStore.swift Tests/CorgiCoreTests/StateStoreTests.swift
git commit -m "feat: state persistence with corrupt-file backup"
```

### Task 4: Geometry and floor segments

**Files:**
- Create: `Sources/CorgiCore/Geometry.swift`
- Create: `Sources/CorgiCore/World.swift`
- Test: `Tests/CorgiCoreTests/WorldTests.swift`

**Interfaces:**
- Produces:
  - `struct WindowInfo: Equatable { let id: Int; let frame: CGRect }` (AppKit global coords)
  - `struct FloorSegment: Equatable { enum Kind: Equatable { case ground(screen: Int), window(id: Int) }; var kind; var y, minX, maxX: CGFloat; var width: CGFloat; var windowID: Int?; func contains(x:) -> Bool; func clampX(_:) -> CGFloat }`
  - `func appKitRect(fromCGBounds: CGRect, primaryScreenHeight: CGFloat) -> CGRect`
  - `func subtractIntervals(_ base: ClosedRange<CGFloat>, _ cuts: [ClosedRange<CGFloat>]) -> [ClosedRange<CGFloat>]`
  - `protocol WindowListProvider: AnyObject { func visibleWindows() -> [WindowInfo] }` (front to back)
  - `struct WorldConfig { var minSegmentWidth: CGFloat = 80; var headroom: CGFloat = 90 }`
  - `final class World { init(provider:screens:config:); private(set) var screens: [CGRect]; private(set) var windows: [WindowInfo]; private(set) var segments: [FloorSegment]; func setScreens(_:); @discardableResult func refresh() -> WorldUpdate }` (`WorldUpdate` is filled in by Task 5; here it is an empty struct)
  - `screens` are each screen's `visibleFrame` (excludes menu bar and Dock).

- [ ] **Step 1: Write the failing tests**

`Tests/CorgiCoreTests/WorldTests.swift`:
```swift
import XCTest
@testable import CorgiCore

final class FakeWindows: WindowListProvider {
    var windows: [WindowInfo] = []
    func visibleWindows() -> [WindowInfo] { windows }
}

let screen0 = CGRect(x: 0, y: 0, width: 1440, height: 875)

final class GeometryTests: XCTestCase {
    func testCGBoundsConvertToAppKit() {
        let r = appKitRect(fromCGBounds: CGRect(x: 10, y: 100, width: 200, height: 50),
                           primaryScreenHeight: 900)
        XCTAssertEqual(r, CGRect(x: 10, y: 750, width: 200, height: 50))
    }

    func testSubtractIntervals() {
        XCTAssertEqual(subtractIntervals(0...100, []), [0...100])
        XCTAssertEqual(subtractIntervals(0...100, [40...60]), [0...40, 60...100])
        XCTAssertEqual(subtractIntervals(0...100, [-10...20, 90...200]), [20...90])
        XCTAssertEqual(subtractIntervals(0...100, [-1...101]), [])
        XCTAssertEqual(subtractIntervals(0...100, [50...70, 30...55]), [0...30, 70...100])
    }
}

final class FloorSegmentTests: XCTestCase {
    func world(_ windows: [WindowInfo]) -> World {
        let p = FakeWindows()
        p.windows = windows
        let w = World(provider: p, screens: [screen0])
        w.refresh()
        return w
    }

    func testGroundSegmentPerScreen() {
        let p = FakeWindows()
        let w = World(provider: p, screens: [screen0, CGRect(x: 1440, y: 100, width: 1920, height: 1000)])
        w.refresh()
        XCTAssertEqual(w.segments, [
            FloorSegment(kind: .ground(screen: 0), y: 0, minX: 0, maxX: 1440),
            FloorSegment(kind: .ground(screen: 1), y: 100, minX: 1440, maxX: 3360),
        ])
    }

    func testWindowTopEdgeBecomesSegment() {
        let w = world([WindowInfo(id: 7, frame: CGRect(x: 100, y: 200, width: 600, height: 400))])
        XCTAssertTrue(w.segments.contains(FloorSegment(kind: .window(id: 7), y: 600, minX: 100, maxX: 700)))
    }

    func testFrontWindowHidesPartOfBackWindowEdge() {
        let w = world([
            WindowInfo(id: 2, frame: CGRect(x: 400, y: 500, width: 600, height: 200)),  // front, top 700
            WindowInfo(id: 1, frame: CGRect(x: 100, y: 200, width: 600, height: 400)),  // back, top 600
        ])
        let back = w.segments.filter { $0.windowID == 1 }
        XCTAssertEqual(back, [FloorSegment(kind: .window(id: 1), y: 600, minX: 100, maxX: 400)])
    }

    func testWindowJustAboveEdgeAlsoHidesIt() {
        // Front window starts 30pt above the back edge, inside the corgi's headroom.
        let w = world([
            WindowInfo(id: 2, frame: CGRect(x: 0, y: 630, width: 1440, height: 100)),
            WindowInfo(id: 1, frame: CGRect(x: 100, y: 200, width: 600, height: 400)),
        ])
        XCTAssertTrue(w.segments.filter { $0.windowID == 1 }.isEmpty)
    }

    func testMaximizedWindowHasNoPerch() {
        let w = world([WindowInfo(id: 3, frame: CGRect(x: 0, y: 0, width: 1440, height: 875))])
        XCTAssertTrue(w.segments.filter { $0.windowID == 3 }.isEmpty)
    }

    func testNarrowPiecesAreDropped() {
        let w = world([
            WindowInfo(id: 2, frame: CGRect(x: 150, y: 500, width: 600, height: 200)),
            WindowInfo(id: 1, frame: CGRect(x: 100, y: 200, width: 600, height: 400)),  // only 100..150 left
        ])
        XCTAssertTrue(w.segments.filter { $0.windowID == 1 }.isEmpty)
    }

    func testWindowEdgeClippedToScreen() {
        let w = world([WindowInfo(id: 4, frame: CGRect(x: -200, y: 100, width: 600, height: 300))])
        XCTAssertEqual(w.segments.filter { $0.windowID == 4 },
                       [FloorSegment(kind: .window(id: 4), y: 400, minX: 0, maxX: 400)])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "GeometryTests|FloorSegmentTests"`
Expected: compile error, `cannot find 'appKitRect' in scope`.

- [ ] **Step 3: Implement geometry**

`Sources/CorgiCore/Geometry.swift`:
```swift
import CoreGraphics
import Foundation

public struct WindowInfo: Equatable {
    public let id: Int
    public let frame: CGRect

    public init(id: Int, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

public struct FloorSegment: Equatable {
    public enum Kind: Equatable {
        case ground(screen: Int)
        case window(id: Int)
    }

    public var kind: Kind
    public var y: CGFloat
    public var minX: CGFloat
    public var maxX: CGFloat

    public init(kind: Kind, y: CGFloat, minX: CGFloat, maxX: CGFloat) {
        self.kind = kind
        self.y = y
        self.minX = minX
        self.maxX = maxX
    }

    public var width: CGFloat { maxX - minX }

    public var windowID: Int? {
        if case .window(let id) = kind { return id }
        return nil
    }

    public func contains(x: CGFloat) -> Bool { x >= minX && x <= maxX }

    public func clampX(_ x: CGFloat) -> CGFloat { min(max(x, minX), maxX) }
}

/// CGWindowList bounds use a top-left origin on the primary screen; AppKit uses bottom-left.
public func appKitRect(fromCGBounds b: CGRect, primaryScreenHeight h: CGFloat) -> CGRect {
    CGRect(x: b.minX, y: h - b.maxY, width: b.width, height: b.height)
}

public func subtractIntervals(_ base: ClosedRange<CGFloat>,
                              _ cuts: [ClosedRange<CGFloat>]) -> [ClosedRange<CGFloat>] {
    var pieces = [base]
    for cut in cuts {
        pieces = pieces.flatMap { piece -> [ClosedRange<CGFloat>] in
            guard cut.overlaps(piece) else { return [piece] }
            var out: [ClosedRange<CGFloat>] = []
            if cut.lowerBound > piece.lowerBound { out.append(piece.lowerBound...cut.lowerBound) }
            if cut.upperBound < piece.upperBound { out.append(cut.upperBound...piece.upperBound) }
            return out
        }
    }
    return pieces
}
```

- [ ] **Step 4: Implement World segment building**

`Sources/CorgiCore/World.swift`:
```swift
import CoreGraphics
import Foundation

public protocol WindowListProvider: AnyObject {
    /// Visible normal windows, front to back, in AppKit global coordinates.
    func visibleWindows() -> [WindowInfo]
}

public struct WorldConfig {
    public var minSegmentWidth: CGFloat = 80
    /// Space the corgi needs above an edge. Edges closer than this to the screen top,
    /// or with another window this close above them, are not perches.
    public var headroom: CGFloat = 90

    public init() {}
}

public struct WorldUpdate: Equatable {
    public init() {}
}

public final class World {
    let provider: WindowListProvider
    public let config: WorldConfig
    public private(set) var screens: [CGRect]
    public private(set) var windows: [WindowInfo] = []
    public private(set) var segments: [FloorSegment] = []

    public init(provider: WindowListProvider, screens: [CGRect], config: WorldConfig = .init()) {
        self.provider = provider
        self.screens = screens
        self.config = config
        rebuildSegments()
    }

    public func setScreens(_ screens: [CGRect]) {
        self.screens = screens
        rebuildSegments()
    }

    @discardableResult
    public func refresh() -> WorldUpdate {
        windows = provider.visibleWindows()
        rebuildSegments()
        return WorldUpdate()
    }

    func rebuildSegments() {
        var result = screens.enumerated().map { i, s in
            FloorSegment(kind: .ground(screen: i), y: s.minY, minX: s.minX, maxX: s.maxX)
        }
        for (k, window) in windows.enumerated() {
            let top = window.frame.maxY
            guard let screen = screens.first(where: {
                $0.minX <= window.frame.midX && window.frame.midX <= $0.maxX
                    && top > $0.minY && top <= $0.maxY - config.headroom
            }) else { continue }
            let base = max(window.frame.minX, screen.minX)...min(window.frame.maxX, screen.maxX)
            let cuts = windows[..<k]
                .filter { $0.frame.minY <= top + config.headroom && $0.frame.maxY >= top }
                .map { $0.frame.minX...$0.frame.maxX }
            for piece in subtractIntervals(base, cuts)
            where piece.upperBound - piece.lowerBound >= config.minSegmentWidth {
                result.append(FloorSegment(kind: .window(id: window.id), y: top,
                                           minX: piece.lowerBound, maxX: piece.upperBound))
            }
        }
        segments = result
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter "GeometryTests|FloorSegmentTests"`
Expected: 9 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/CorgiCore/Geometry.swift Sources/CorgiCore/World.swift Tests/CorgiCoreTests/WorldTests.swift
git commit -m "feat: floor segments from screens and window edges"
```

### Task 5: World updates, lookup, reachability

**Files:**
- Modify: `Sources/CorgiCore/World.swift`
- Test: `Tests/CorgiCoreTests/WorldTests.swift` (append)

**Interfaces:**
- Consumes: Task 4 types.
- Produces:
  - `struct WorldUpdate: Equatable { var moved: [Int: CGVector]; var vanished: Set<Int>; var isEmpty: Bool }` where `moved[id]` is the change in the window's top-left corner (x, top edge y).
  - `World.segment(under p: CGPoint, tolerance: CGFloat = 2) -> FloorSegment?` (highest matching segment wins)
  - `World.reachableSegments(from p: CGPoint, maxJumpUp: CGFloat, maxJumpAcross: CGFloat) -> [FloorSegment]` (excludes the segment under `p`, highest first)
  - `World.screenIndex(containing p: CGPoint) -> Int?` (uses `screens`, x range only, nearest screen if none)

- [ ] **Step 1: Write the failing tests**

Append to `Tests/CorgiCoreTests/WorldTests.swift`:
```swift
final class WorldUpdateTests: XCTestCase {
    func testRefreshReportsMovedAndVanishedWindows() {
        let p = FakeWindows()
        p.windows = [WindowInfo(id: 1, frame: CGRect(x: 100, y: 200, width: 600, height: 400)),
                     WindowInfo(id: 2, frame: CGRect(x: 800, y: 100, width: 400, height: 300))]
        let w = World(provider: p, screens: [screen0])
        w.refresh()
        p.windows = [WindowInfo(id: 1, frame: CGRect(x: 130, y: 180, width: 600, height: 400))]
        let update = w.refresh()
        XCTAssertEqual(update.moved, [1: CGVector(dx: 30, dy: -20)])
        XCTAssertEqual(update.vanished, [2])
        XCTAssertFalse(update.isEmpty)
        XCTAssertTrue(w.refresh().isEmpty)
    }

    func testResizeFromBottomIsNotAMove() {
        let p = FakeWindows()
        p.windows = [WindowInfo(id: 1, frame: CGRect(x: 100, y: 200, width: 600, height: 400))]
        let w = World(provider: p, screens: [screen0])
        w.refresh()
        p.windows = [WindowInfo(id: 1, frame: CGRect(x: 100, y: 100, width: 600, height: 500))]
        XCTAssertTrue(w.refresh().isEmpty)
    }

    func testSegmentUnderPrefersHighestWithinTolerance() {
        let p = FakeWindows()
        p.windows = [WindowInfo(id: 1, frame: CGRect(x: 100, y: 200, width: 600, height: 400))]
        let w = World(provider: p, screens: [screen0])
        w.refresh()
        XCTAssertEqual(w.segment(under: CGPoint(x: 300, y: 601))?.windowID, 1)
        XCTAssertEqual(w.segment(under: CGPoint(x: 300, y: 0))?.kind, .ground(screen: 0))
        XCTAssertNil(w.segment(under: CGPoint(x: 300, y: 300)))
        XCTAssertNil(w.segment(under: CGPoint(x: 50, y: 600)))
    }

    func testReachableSegments() {
        let p = FakeWindows()
        p.windows = [WindowInfo(id: 1, frame: CGRect(x: 100, y: 0, width: 400, height: 300)),   // top 300
                     WindowInfo(id: 2, frame: CGRect(x: 900, y: 0, width: 400, height: 700)),   // top 700
                     WindowInfo(id: 3, frame: CGRect(x: 600, y: 0, width: 200, height: 250))]   // top 250
        let w = World(provider: p, screens: [screen0])
        w.refresh()
        let fromGround = w.reachableSegments(from: CGPoint(x: 550, y: 0), maxJumpUp: 400, maxJumpAcross: 500)
        XCTAssertEqual(fromGround.compactMap(\.windowID), [1, 3])   // 2 is too high, sorted highest first
        let fromWindow1 = w.reachableSegments(from: CGPoint(x: 300, y: 300), maxJumpUp: 400, maxJumpAcross: 350)
        XCTAssertEqual(fromWindow1.map(\.kind), [.window(id: 3), .ground(screen: 0)])
    }

    func testScreenIndexContaining() {
        let w = World(provider: FakeWindows(),
                      screens: [screen0, CGRect(x: 1440, y: 0, width: 1920, height: 1000)])
        XCTAssertEqual(w.screenIndex(containing: CGPoint(x: 10, y: 5)), 0)
        XCTAssertEqual(w.screenIndex(containing: CGPoint(x: 2000, y: 5)), 1)
        XCTAssertEqual(w.screenIndex(containing: CGPoint(x: 9000, y: 5)), 1)
        XCTAssertNil(World(provider: FakeWindows(), screens: []).screenIndex(containing: .zero))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter WorldUpdateTests`
Expected: compile error, `value of type 'WorldUpdate' has no member 'moved'`.

- [ ] **Step 3: Implement**

In `Sources/CorgiCore/World.swift`, replace the `WorldUpdate` struct with:
```swift
public struct WorldUpdate: Equatable {
    public var moved: [Int: CGVector] = [:]
    public var vanished: Set<Int> = []

    public init(moved: [Int: CGVector] = [:], vanished: Set<Int> = []) {
        self.moved = moved
        self.vanished = vanished
    }

    public var isEmpty: Bool { moved.isEmpty && vanished.isEmpty }
}
```

Replace `refresh()` with:
```swift
    @discardableResult
    public func refresh() -> WorldUpdate {
        let old = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.frame) })
        windows = provider.visibleWindows()
        var update = WorldUpdate()
        var seen = Set<Int>()
        for window in windows {
            seen.insert(window.id)
            guard let before = old[window.id] else { continue }
            let delta = CGVector(dx: window.frame.minX - before.minX, dy: window.frame.maxY - before.maxY)
            if delta.dx != 0 || delta.dy != 0 { update.moved[window.id] = delta }
        }
        update.vanished = Set(old.keys).subtracting(seen)
        rebuildSegments()
        return update
    }
```

Add these methods to `World`:
```swift
    public func segment(under p: CGPoint, tolerance: CGFloat = 2) -> FloorSegment? {
        segments
            .filter { $0.contains(x: p.x) && abs($0.y - p.y) <= tolerance }
            .max { $0.y < $1.y }
    }

    public func reachableSegments(from p: CGPoint, maxJumpUp: CGFloat, maxJumpAcross: CGFloat) -> [FloorSegment] {
        let current = segment(under: p)
        return segments
            .filter { $0 != current }
            .filter { $0.y - p.y <= maxJumpUp }
            .filter { abs($0.clampX(p.x) - p.x) <= maxJumpAcross }
            .sorted { $0.y > $1.y }
    }

    public func screenIndex(containing p: CGPoint) -> Int? {
        if let i = screens.firstIndex(where: { $0.minX <= p.x && p.x < $0.maxX }) { return i }
        return screens.indices.min { abs(screens[$0].midX - p.x) < abs(screens[$1].midX - p.x) }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "WorldUpdateTests|FloorSegmentTests|GeometryTests"`
Expected: 14 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CorgiCore/World.swift Tests/CorgiCoreTests/WorldTests.swift
git commit -m "feat: world updates, segment lookup, reachability"
```

### Task 6: Body physics

**Files:**
- Create: `Sources/CorgiCore/Body.swift`
- Test: `Tests/CorgiCoreTests/BodyTests.swift`

**Interfaces:**
- Consumes: `World`, `WorldUpdate`, `FloorSegment` from Tasks 4-5.
- Produces:
  - `struct BodyConfig { gravity = 2200, walkSpeed = 70, runSpeed = 240, maxJumpUp = 420, maxJumpAcross = 520, jumpClearance = 50, maxFallSpeed = 1800 }` (all `CGFloat`, points and seconds)
  - `enum BodyMode: Equatable { case grounded, airborne, held }`
  - `enum BodyEvent: Equatable { case landed, hitEdge, startedFalling }`
  - `final class Body { init(position:config:); let config; private(set) var position: CGPoint; private(set) var velocity: CGVector; private(set) var mode: BodyMode; private(set) var standingOn: FloorSegment?; private(set) var facingRight: Bool; var isMoving: Bool; func walk(direction: CGFloat, speed: CGFloat); func stop(); func face(right: Bool); func jump(to: CGPoint); func leap(direction: CGFloat); func pickUp(); func moveHeld(to: CGPoint); func release(); @discardableResult func apply(_ update: WorldUpdate) -> BodyEvent?; @discardableResult func step(dt: TimeInterval, world: World) -> BodyEvent?; func clamp(to screens: [CGRect]) }`
  - A new `Body` starts `.airborne` and lands on the first `step` that crosses a segment.

- [ ] **Step 1: Write the failing tests**

`Tests/CorgiCoreTests/BodyTests.swift`:
```swift
import XCTest
@testable import CorgiCore

final class BodyTests: XCTestCase {
    var windows: FakeWindows!
    var world: World!

    override func setUp() {
        windows = FakeWindows()
        windows.windows = [WindowInfo(id: 1, frame: CGRect(x: 100, y: 0, width: 400, height: 300))]  // top 300
        world = World(provider: windows, screens: [screen0])
        world.refresh()
    }

    @discardableResult
    func run(_ body: Body, seconds: Double, dt: Double = 1.0 / 60) -> [BodyEvent] {
        var events: [BodyEvent] = []
        for _ in 0..<Int(seconds / dt) {
            if let e = body.step(dt: dt, world: world) { events.append(e) }
        }
        return events
    }

    func testFallsAndLandsOnGround() {
        let body = Body(position: CGPoint(x: 800, y: 500))
        XCTAssertEqual(run(body, seconds: 2), [.landed])
        XCTAssertEqual(body.mode, .grounded)
        XCTAssertEqual(body.position.y, 0)
        XCTAssertEqual(body.standingOn?.kind, .ground(screen: 0))
    }

    func testFallingOntoWindowEdge() {
        let body = Body(position: CGPoint(x: 300, y: 700))
        run(body, seconds: 2)
        XCTAssertEqual(body.standingOn?.windowID, 1)
        XCTAssertEqual(body.position.y, 300)
    }

    func testWalkStopsAtSegmentEdge() {
        let body = Body(position: CGPoint(x: 450, y: 300))
        run(body, seconds: 0.1)
        body.walk(direction: 1, speed: 100)
        XCTAssertTrue(body.facingRight)
        let events = run(body, seconds: 1)
        XCTAssertEqual(events, [.hitEdge])
        XCTAssertEqual(body.position.x, 500)
        XCTAssertFalse(body.isMoving)
    }

    func testJumpLandsOnHigherWindow() {
        let body = Body(position: CGPoint(x: 50, y: 0))
        run(body, seconds: 0.1)
        body.jump(to: CGPoint(x: 300, y: 300))
        XCTAssertEqual(body.mode, .airborne)
        run(body, seconds: 2)
        XCTAssertEqual(body.standingOn?.windowID, 1)
        XCTAssertEqual(body.position.x, 300, accuracy: 15)
    }

    func testLeapOffEdgeFallsToGround() {
        let body = Body(position: CGPoint(x: 120, y: 300))
        run(body, seconds: 0.1)
        body.leap(direction: -1)
        XCTAssertEqual(body.mode, .airborne)
        XCTAssertLessThan(body.position.x, 100)
        run(body, seconds: 2)
        XCTAssertEqual(body.standingOn?.kind, .ground(screen: 0))
    }

    func testRidesAlongWhenWindowMoves() {
        let body = Body(position: CGPoint(x: 300, y: 300))
        run(body, seconds: 0.1)
        windows.windows = [WindowInfo(id: 1, frame: CGRect(x: 150, y: 50, width: 400, height: 300))]
        body.apply(world.refresh())
        XCTAssertEqual(body.position, CGPoint(x: 350, y: 350))
        run(body, seconds: 0.1)
        XCTAssertEqual(body.standingOn?.windowID, 1)
    }

    func testFallsWhenWindowCloses() {
        let body = Body(position: CGPoint(x: 300, y: 300))
        run(body, seconds: 0.1)
        windows.windows = []
        XCTAssertEqual(body.apply(world.refresh()), .startedFalling)
        XCTAssertEqual(body.mode, .airborne)
        run(body, seconds: 2)
        XCTAssertEqual(body.standingOn?.kind, .ground(screen: 0))
    }

    func testFallsWhenEdgeGetsCovered() {
        let body = Body(position: CGPoint(x: 300, y: 300))
        run(body, seconds: 0.1)
        windows.windows.insert(WindowInfo(id: 2, frame: CGRect(x: 0, y: 250, width: 1440, height: 200)), at: 0)
        world.refresh()
        XCTAssertEqual(body.step(dt: 1.0 / 60, world: world), .startedFalling)
    }

    func testHeldBodyIgnoresWindowChanges() {
        let body = Body(position: CGPoint(x: 300, y: 300))
        run(body, seconds: 0.1)
        body.pickUp()
        body.moveHeld(to: CGPoint(x: 700, y: 600))
        windows.windows = []
        XCTAssertNil(body.apply(world.refresh()))
        run(body, seconds: 1)
        XCTAssertEqual(body.mode, .held)
        XCTAssertEqual(body.position, CGPoint(x: 700, y: 600))
        body.release()
        run(body, seconds: 2)
        XCTAssertEqual(body.mode, .grounded)
        XCTAssertEqual(body.position.y, 0)
    }

    func testAirborneBodyIsNotCarried() {
        let body = Body(position: CGPoint(x: 300, y: 300))
        run(body, seconds: 0.1)
        body.jump(to: CGPoint(x: 800, y: 0))
        let before = body.position
        windows.windows = [WindowInfo(id: 1, frame: CGRect(x: 150, y: 50, width: 400, height: 300))]
        XCTAssertNil(body.apply(world.refresh()))
        XCTAssertEqual(body.position, before)
    }

    func testClampAfterMonitorUnplugged() {
        let screen1 = CGRect(x: 1440, y: 0, width: 1920, height: 1000)
        world.setScreens([screen0, screen1])
        let body = Body(position: CGPoint(x: 2000, y: 0))
        run(body, seconds: 0.1)
        world.setScreens([screen0])
        body.clamp(to: world.screens)
        XCTAssertLessThanOrEqual(body.position.x, 1440)
        run(body, seconds: 2)
        XCTAssertEqual(body.mode, .grounded)
        XCTAssertEqual(body.standingOn?.kind, .ground(screen: 0))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter BodyTests`
Expected: compile error, `cannot find 'Body' in scope`.

- [ ] **Step 3: Implement**

`Sources/CorgiCore/Body.swift`:
```swift
import CoreGraphics
import Foundation

public struct BodyConfig {
    public var gravity: CGFloat = 2200
    public var walkSpeed: CGFloat = 70
    public var runSpeed: CGFloat = 240
    public var maxJumpUp: CGFloat = 420
    public var maxJumpAcross: CGFloat = 520
    public var jumpClearance: CGFloat = 50
    public var maxFallSpeed: CGFloat = 1800

    public init() {}
}

public enum BodyMode: Equatable { case grounded, airborne, held }

public enum BodyEvent: Equatable { case landed, hitEdge, startedFalling }

public final class Body {
    public let config: BodyConfig
    public private(set) var position: CGPoint
    public private(set) var velocity: CGVector = .zero
    public private(set) var mode: BodyMode = .airborne
    public private(set) var standingOn: FloorSegment?
    public private(set) var facingRight = true
    private var walkVelocity: CGFloat = 0

    public init(position: CGPoint, config: BodyConfig = .init()) {
        self.position = position
        self.config = config
    }

    public var isMoving: Bool { mode == .airborne || walkVelocity != 0 }

    public func walk(direction: CGFloat, speed: CGFloat) {
        guard mode == .grounded else { return }
        walkVelocity = direction.sign == .minus ? -speed : (direction == 0 ? 0 : speed)
        if direction != 0 { facingRight = direction > 0 }
    }

    public func stop() { walkVelocity = 0 }

    public func face(right: Bool) { facingRight = right }

    public func jump(to target: CGPoint) {
        guard mode == .grounded else { return }
        let g = config.gravity
        let apex = max(target.y, position.y) - position.y + config.jumpClearance
        let vy = (2 * g * apex).squareRoot()
        let tUp = vy / g
        let tDown = (2 * (position.y + apex - target.y) / g).squareRoot()
        velocity = CGVector(dx: (target.x - position.x) / (tUp + tDown), dy: vy)
        facingRight = target.x >= position.x
        walkVelocity = 0
        standingOn = nil
        mode = .airborne
    }

    /// Small hop off the end of the current segment, used to get down from a perch.
    public func leap(direction: CGFloat) {
        guard mode == .grounded, let s = standingOn else { return }
        position.x = direction < 0 ? s.minX - 1 : s.maxX + 1
        velocity = CGVector(dx: direction < 0 ? -150 : 150, dy: 250)
        facingRight = direction > 0
        walkVelocity = 0
        standingOn = nil
        mode = .airborne
    }

    public func pickUp() {
        mode = .held
        standingOn = nil
        velocity = .zero
        walkVelocity = 0
    }

    public func moveHeld(to point: CGPoint) {
        guard mode == .held else { return }
        position = point
    }

    public func release() {
        guard mode == .held else { return }
        mode = .airborne
        velocity = .zero
    }

    @discardableResult
    public func apply(_ update: WorldUpdate) -> BodyEvent? {
        guard mode == .grounded, let id = standingOn?.windowID else { return nil }
        if update.vanished.contains(id) {
            return startFalling()
        }
        if let delta = update.moved[id] {
            position.x += delta.dx
            position.y += delta.dy
        }
        return nil
    }

    @discardableResult
    public func step(dt: TimeInterval, world: World) -> BodyEvent? {
        let dt = CGFloat(dt)
        switch mode {
        case .held:
            return nil
        case .grounded:
            guard let segment = world.segment(under: position) else { return startFalling() }
            standingOn = segment
            position.y = segment.y
            let nextX = position.x + walkVelocity * dt
            if segment.contains(x: nextX) {
                position.x = nextX
                return nil
            }
            position.x = segment.clampX(nextX)
            walkVelocity = 0
            return .hitEdge
        case .airborne:
            velocity.dy = max(velocity.dy - config.gravity * dt, -config.maxFallSpeed)
            let next = CGPoint(x: position.x + velocity.dx * dt, y: position.y + velocity.dy * dt)
            if velocity.dy <= 0,
               let landing = world.segments
                .filter({ $0.contains(x: next.x) && position.y >= $0.y && next.y <= $0.y })
                .max(by: { $0.y < $1.y }) {
                position = CGPoint(x: next.x, y: landing.y)
                velocity = .zero
                standingOn = landing
                mode = .grounded
                return .landed
            }
            position = next
            return nil
        }
    }

    /// Pulls the body back onto the nearest screen if it ended up outside every screen.
    public func clamp(to screens: [CGRect]) {
        guard !screens.isEmpty else { return }
        let p = position
        if screens.contains(where: { $0.minX <= p.x && p.x <= $0.maxX && $0.minY <= p.y && p.y <= $0.maxY }) {
            return
        }
        let screen = screens.first { $0.minX <= p.x && p.x <= $0.maxX }
            ?? screens.min { abs($0.midX - p.x) < abs($1.midX - p.x) }!
        let clamped = CGPoint(x: min(max(position.x, screen.minX + 20), screen.maxX - 20),
                              y: min(max(position.y, screen.minY), screen.maxY - 10))
        guard clamped != position else { return }
        position = clamped
        if mode != .held { startFalling() }
    }

    @discardableResult
    private func startFalling() -> BodyEvent {
        mode = .airborne
        standingOn = nil
        velocity = .zero
        walkVelocity = 0
        return .startedFalling
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter BodyTests`
Expected: 11 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CorgiCore/Body.swift Tests/CorgiCoreTests/BodyTests.swift
git commit -m "feat: body physics with ride-along, falling, clamping"
```

### Task 7: Brain (behavior choice)

**Files:**
- Create: `Sources/CorgiCore/SeededRandom.swift`
- Create: `Sources/CorgiCore/Brain.swift`
- Test: `Tests/CorgiCoreTests/BrainTests.swift`

**Interfaces:**
- Consumes: `NeedsState` from Task 1.
- Produces:
  - `struct SeededRandom: RandomNumberGenerator { init(seed: UInt64) }` (SplitMix64)
  - `enum Behavior: String, CaseIterable { idle, walk, sit, sleep, zoomies, chaseCursor, hopToWindow, beg, eat, fetch, bath, dangle, fall, greet; static let autonomous: [Behavior] }`
  - `struct BrainConfig { var durations: [Behavior: ClosedRange<Double>]; var wakeEnergy = 95.0 }`
  - `struct BrainContext { var needs: NeedsState; var lowThreshold: Double; var canHop: Bool }`
  - `final class Brain { init(config:rng:); private(set) var current: Behavior; private(set) var remaining: TimeInterval; func weights(_ ctx: BrainContext) -> [Behavior: Double]; func choose(_ ctx: BrainContext) -> Behavior; @discardableResult func update(dt: TimeInterval, _ ctx: BrainContext) -> Behavior?; func interrupt(with: Behavior, duration: TimeInterval); func finishCurrent() }`
  - `update` returns the new behavior when it switches, else `nil`. `finishCurrent()` makes the next `update` pick again.

- [ ] **Step 1: Write the failing tests**

`Tests/CorgiCoreTests/BrainTests.swift`:
```swift
import XCTest
@testable import CorgiCore

final class BrainTests: XCTestCase {
    func ctx(hunger: Double = 70, happiness: Double = 70, energy: Double = 70,
             asleep: Bool = false, canHop: Bool = true) -> BrainContext {
        var s = NeedsState.fresh(at: Date(timeIntervalSince1970: 0))
        s.hunger = hunger
        s.happiness = happiness
        s.energy = energy
        s.isAsleep = asleep
        return BrainContext(needs: s, lowThreshold: 30, canHop: canHop)
    }

    func brain(seed: UInt64 = 1) -> Brain { Brain(rng: SeededRandom(seed: seed)) }

    func testSeededRandomIsDeterministic() {
        var a = SeededRandom(seed: 42), b = SeededRandom(seed: 42)
        XCTAssertEqual((0..<5).map { _ in a.next() }, (0..<5).map { _ in b.next() })
    }

    func testOnlyAutonomousBehaviorsHaveWeight() {
        let w = brain().weights(ctx())
        for b in Behavior.allCases where !Behavior.autonomous.contains(b) {
            XCTAssertNil(w[b], "\(b)")
        }
    }

    func testLowEnergyFavorsSleepAndBlocksActiveBehaviors() {
        let w = brain().weights(ctx(energy: 10))
        XCTAssertEqual(w[.zoomies], 0)
        XCTAssertEqual(w[.chaseCursor], 0)
        XCTAssertEqual(w[.hopToWindow], 0)
        XCTAssertGreaterThan(w[.sleep]!, w.values.filter { $0 != w[.sleep]! }.max()!)
    }

    func testLowHungerFavorsBeg() {
        XCTAssertEqual(brain().weights(ctx())[.beg], 0)
        XCTAssertGreaterThan(brain().weights(ctx(hunger: 10))[.beg]!, 5)
    }

    func testHappyAndRestedBoostsPlayfulBehaviors() {
        let normal = brain().weights(ctx(happiness: 50, energy: 50))
        let happy = brain().weights(ctx(happiness: 90, energy: 90))
        for b in [Behavior.zoomies, .chaseCursor, .hopToWindow] {
            XCTAssertGreaterThan(happy[b]!, normal[b]!, "\(b)")
        }
    }

    func testCannotHopWhenNoPerchReachable() {
        XCTAssertEqual(brain().weights(ctx(canHop: false))[.hopToWindow], 0)
    }

    func testChoiceFollowsWeightsOverManyPicks() {
        let b = brain(seed: 7)
        let c = ctx(energy: 5)
        let picks = (0..<500).map { _ in b.choose(c) }
        let sleeps = picks.filter { $0 == .sleep }.count
        XCTAssertGreaterThan(sleeps, 200)   // expected share is about 54%
        XCTAssertFalse(picks.contains(.zoomies))
    }

    func testUpdateSwitchesWhenDurationEnds() {
        let b = brain()
        let rested = ctx(energy: 100)                    // rested, so sleep is never picked
        XCTAssertNotNil(b.update(dt: 0, rested))         // first pick
        let first = b.current
        XCTAssertNil(b.update(dt: 0.5, rested))
        XCTAssertEqual(b.current, first)
        XCTAssertNotNil(b.update(dt: 1000, rested))
    }

    func testInterruptOverridesAndFinishCurrentRepicks() {
        let b = brain()
        b.update(dt: 0, ctx())
        b.interrupt(with: .eat, duration: 3)
        XCTAssertEqual(b.current, .eat)
        XCTAssertNil(b.update(dt: 1, ctx()))
        XCTAssertEqual(b.current, .eat)
        b.finishCurrent()
        XCTAssertNotNil(b.update(dt: 0, ctx()))
        XCTAssertTrue(Behavior.autonomous.contains(b.current))
    }

    func testKeepsSleepingUntilRested() {
        let b = brain()
        b.interrupt(with: .sleep, duration: 1)
        XCTAssertNil(b.update(dt: 2, ctx(energy: 60, asleep: true)))
        XCTAssertEqual(b.current, .sleep)
        XCTAssertNotNil(b.update(dt: 20, ctx(energy: 96, asleep: true)))
        XCTAssertNotEqual(b.current, .sleep)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter BrainTests`
Expected: compile error, `cannot find 'Brain' in scope`.

- [ ] **Step 3: Implement**

`Sources/CorgiCore/SeededRandom.swift`:
```swift
public struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
```

`Sources/CorgiCore/Brain.swift`:
```swift
import Foundation

public enum Behavior: String, CaseIterable {
    case idle, walk, sit, sleep, zoomies, chaseCursor, hopToWindow, beg
    case eat, fetch, bath, dangle, fall, greet

    /// Behaviors the brain picks on its own. The rest only happen through `interrupt`.
    public static let autonomous: [Behavior] = [.idle, .walk, .sit, .sleep, .zoomies, .chaseCursor, .hopToWindow, .beg]
}

public struct BrainConfig {
    public var durations: [Behavior: ClosedRange<Double>] = [
        .idle: 3...8, .walk: 3...8, .sit: 4...10, .sleep: 60...180,
        .zoomies: 4...8, .chaseCursor: 5...5, .hopToWindow: 6...8, .beg: 6...10,
    ]
    public var wakeEnergy = 95.0

    public init() {}
}

public struct BrainContext {
    public var needs: NeedsState
    public var lowThreshold: Double
    public var canHop: Bool

    public init(needs: NeedsState, lowThreshold: Double, canHop: Bool) {
        self.needs = needs
        self.lowThreshold = lowThreshold
        self.canHop = canHop
    }
}

public final class Brain {
    public let config: BrainConfig
    private var rng: any RandomNumberGenerator
    public private(set) var current: Behavior = .idle
    public private(set) var remaining: TimeInterval = 0

    public init(config: BrainConfig = .init(), rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.config = config
        self.rng = rng
    }

    private func random() -> Double {
        Double(rng.next() >> 11) / Double(1 << 53)
    }

    public func weights(_ ctx: BrainContext) -> [Behavior: Double] {
        let n = ctx.needs
        var w: [Behavior: Double] = [
            .idle: 3, .walk: 4, .sit: 2, .sleep: 0.5,
            .zoomies: 0.5, .chaseCursor: 0.5, .hopToWindow: 1, .beg: 0,
        ]
        if n.happiness > 70 && n.energy > 60 {
            w[.zoomies]! += 1.5
            w[.chaseCursor]! += 1.5
            w[.hopToWindow]! += 1.5
        }
        if n.happiness < ctx.lowThreshold {
            w[.zoomies] = 0
            w[.walk]! *= 0.5
            w[.sit]! += 2
        }
        if n.hunger < ctx.lowThreshold {
            w[.beg]! += 6
        }
        if n.energy < ctx.lowThreshold {
            w[.sleep]! += 10
            w[.zoomies] = 0
            w[.chaseCursor] = 0
            w[.hopToWindow] = 0
        }
        if n.energy >= config.wakeEnergy { w[.sleep] = 0 }
        if !ctx.canHop { w[.hopToWindow] = 0 }
        return w
    }

    public func choose(_ ctx: BrainContext) -> Behavior {
        let w = weights(ctx)
        let total = Behavior.autonomous.reduce(0) { $0 + (w[$1] ?? 0) }
        var roll = random() * total
        for b in Behavior.autonomous {
            roll -= w[b] ?? 0
            if roll < 0 { return b }
        }
        return .idle
    }

    @discardableResult
    public func update(dt: TimeInterval, _ ctx: BrainContext) -> Behavior? {
        remaining -= dt
        guard remaining <= 0 else { return nil }
        if current == .sleep && ctx.needs.energy < config.wakeEnergy {
            remaining = 10
            return nil
        }
        let next = choose(ctx)
        current = next
        let range = config.durations[next] ?? 3...8
        remaining = range.lowerBound + random() * (range.upperBound - range.lowerBound)
        return next
    }

    public func interrupt(with behavior: Behavior, duration: TimeInterval) {
        current = behavior
        remaining = duration
    }

    public func finishCurrent() {
        remaining = 0
        if current == .sleep { current = .idle }
    }
}
```

Note: `finishCurrent()` resets `.sleep` to `.idle` so an explicit wake (for example the user clicks a sleeping corgi) is never blocked by the keep-sleeping rule.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter BrainTests`
Expected: 10 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CorgiCore/SeededRandom.swift Sources/CorgiCore/Brain.swift Tests/CorgiCoreTests/BrainTests.swift
git commit -m "feat: needs-weighted behavior brain"
```

### Task 8: Behavior executor (steering)

**Files:**
- Create: `Sources/CorgiCore/BehaviorExecutor.swift`
- Test: `Tests/CorgiCoreTests/BehaviorExecutorTests.swift`

**Interfaces:**
- Consumes: `Body`, `BodyEvent`, `BodyConfig` (Task 6), `World` (Tasks 4-5), `Behavior` (Task 7).
- Produces:
  - `final class BehaviorExecutor { init(rng:); var targetX: CGFloat?; var speedScale: CGFloat = 1; func begin(_ b: Behavior, body: Body, world: World, cursor: CGPoint); func step(_ b: Behavior, body: Body, world: World, cursor: CGPoint) -> Bool; func handle(_ event: BodyEvent, behavior: Behavior, body: Body) -> Bool }`
  - `step` and `handle` return `true` when the behavior is finished early (target reached, landed, nothing to do).
  - Call order per tick: `executor.step` then `body.step`, then feed any `BodyEvent` to `executor.handle`.
  - `fetch` and `greet` walk to `targetX`; the caller may overwrite `targetX` after `begin`.

- [ ] **Step 1: Write the failing tests**

`Tests/CorgiCoreTests/BehaviorExecutorTests.swift`:
```swift
import XCTest
@testable import CorgiCore

final class BehaviorExecutorTests: XCTestCase {
    var windows: FakeWindows!
    var world: World!
    let dt = 1.0 / 60

    override func setUp() {
        windows = FakeWindows()
        windows.windows = [WindowInfo(id: 1, frame: CGRect(x: 600, y: 0, width: 400, height: 300))]  // top 300
        world = World(provider: windows, screens: [screen0])
        world.refresh()
    }

    func groundedBody(x: CGFloat, y: CGFloat = 0) -> Body {
        let body = Body(position: CGPoint(x: x, y: y))
        body.step(dt: dt, world: world)
        return body
    }

    /// Runs until the executor reports done or time runs out. Returns true if done.
    func run(_ ex: BehaviorExecutor, _ b: Behavior, _ body: Body, cursor: CGPoint = .zero,
             seconds: Double) -> Bool {
        for _ in 0..<Int(seconds / dt) {
            if ex.step(b, body: body, world: world, cursor: cursor) { return true }
            if let e = body.step(dt: dt, world: world), ex.handle(e, behavior: b, body: body) { return true }
        }
        return false
    }

    func testWalkReachesRandomTargetOnSegment() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 3))
        let body = groundedBody(x: 200)
        ex.begin(.walk, body: body, world: world, cursor: .zero)
        let target = try! XCTUnwrap(ex.targetX)
        XCTAssertTrue((20...1420).contains(target))
        XCTAssertTrue(run(ex, .walk, body, seconds: 30))
        XCTAssertEqual(body.position.x, target, accuracy: 4)
    }

    func testChaseRunsTowardCursorOnSameSegment() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        let body = groundedBody(x: 100)
        let cursor = CGPoint(x: 500, y: 400)
        ex.begin(.chaseCursor, body: body, world: world, cursor: cursor)
        _ = run(ex, .chaseCursor, body, cursor: cursor, seconds: 3)
        XCTAssertEqual(body.position.x, 500, accuracy: 31)
        XCTAssertTrue(body.facingRight)
    }

    func testChaseWithCursorOffSegmentJustFacesIt() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        let body = groundedBody(x: 800, y: 300)       // on window 1 (600...1000)
        let cursor = CGPoint(x: 100, y: 50)
        ex.begin(.chaseCursor, body: body, world: world, cursor: cursor)
        _ = run(ex, .chaseCursor, body, cursor: cursor, seconds: 1)
        XCTAssertEqual(body.position.x, 800)
        XCTAssertFalse(body.facingRight)
    }

    func testHopJumpsOntoReachableWindowAndFinishesOnLanding() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        let body = groundedBody(x: 400)
        ex.begin(.hopToWindow, body: body, world: world, cursor: .zero)
        XCTAssertEqual(body.mode, .airborne)
        XCTAssertTrue(run(ex, .hopToWindow, body, seconds: 3))
        XCTAssertEqual(body.standingOn?.windowID, 1)
    }

    func testHopFromWindowCanGoBackDown() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        let body = groundedBody(x: 800, y: 300)       // on window 1, only the ground is reachable
        ex.begin(.hopToWindow, body: body, world: world, cursor: .zero)
        XCTAssertTrue(run(ex, .hopToWindow, body, seconds: 6))
        XCTAssertEqual(body.standingOn?.kind, .ground(screen: 0))
    }

    func testHopWithNothingReachableFinishesImmediately() {
        windows.windows = []
        world.refresh()
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        let body = groundedBody(x: 400)
        ex.begin(.hopToWindow, body: body, world: world, cursor: .zero)
        XCTAssertTrue(ex.step(.hopToWindow, body: body, world: world, cursor: .zero))
    }

    func testZoomiesBounceBetweenEdges() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        let body = groundedBody(x: 800, y: 300)
        ex.begin(.zoomies, body: body, world: world, cursor: .zero)
        var facings = Set<Bool>()
        for _ in 0..<Int(6 / dt) {
            _ = ex.step(.zoomies, body: body, world: world, cursor: .zero)
            if let e = body.step(dt: dt, world: world) { _ = ex.handle(e, behavior: .zoomies, body: body) }
            facings.insert(body.facingRight)
            XCTAssertTrue((600...1000).contains(body.position.x))
        }
        XCTAssertEqual(facings, [true, false])
    }

    func testFetchWalksToCallerTarget() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        let body = groundedBody(x: 100)
        ex.begin(.fetch, body: body, world: world, cursor: .zero)
        ex.targetX = 400
        XCTAssertTrue(run(ex, .fetch, body, seconds: 5))
        XCTAssertEqual(body.position.x, 400, accuracy: 4)
    }

    func testStationaryBehaviorsStop() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        let body = groundedBody(x: 100)
        body.walk(direction: 1, speed: 70)
        ex.begin(.sleep, body: body, world: world, cursor: .zero)
        XCTAssertFalse(run(ex, .sleep, body, seconds: 1))
        XCTAssertEqual(body.position.x, 100)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter BehaviorExecutorTests`
Expected: compile error, `cannot find 'BehaviorExecutor' in scope`.

- [ ] **Step 3: Implement**

`Sources/CorgiCore/BehaviorExecutor.swift`:
```swift
import CoreGraphics
import Foundation

public final class BehaviorExecutor {
    public var targetX: CGFloat?
    public var speedScale: CGFloat = 1
    private var rng: any RandomNumberGenerator
    private var zoomDirection: CGFloat = 1
    private var hopStarted = false
    private var hopDownDirection: CGFloat?

    public init(rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.rng = rng
    }

    private func random() -> CGFloat {
        CGFloat(Double(rng.next() >> 11) / Double(1 << 53))
    }

    public func begin(_ b: Behavior, body: Body, world: World, cursor: CGPoint) {
        targetX = nil
        hopStarted = false
        hopDownDirection = nil
        body.stop()
        let segment = body.standingOn ?? world.segment(under: body.position)
        switch b {
        case .walk:
            if let s = segment {
                let lo = s.minX + 20, hi = max(lo, s.maxX - 20)
                targetX = lo + random() * (hi - lo)
            }
        case .greet:
            targetX = segment?.clampX(cursor.x)
        case .zoomies:
            zoomDirection = random() < 0.5 ? -1 : 1
        case .hopToWindow:
            let options = world.reachableSegments(from: body.position,
                                                  maxJumpUp: body.config.maxJumpUp,
                                                  maxJumpAcross: body.config.maxJumpAcross)
                .prefix(3)
            guard !options.isEmpty else { return }
            let pick = options[options.startIndex + Int(random() * CGFloat(options.count)) % options.count]
            if let s = segment, pick.y < s.y {
                // Going down: walk to the edge on the side where the lower segment continues, then leap.
                let sides: [(dir: CGFloat, edge: CGFloat, landX: CGFloat)] = [(-1, s.minX, s.minX - 40), (1, s.maxX, s.maxX + 40)]
                guard let side = sides
                    .filter({ pick.contains(x: $0.landX) })
                    .min(by: { abs($0.edge - body.position.x) < abs($1.edge - body.position.x) })
                else { return }
                hopDownDirection = side.dir
                targetX = side.edge
            } else {
                let x = min(max(body.position.x, pick.minX + 30), pick.maxX - 30)
                body.jump(to: CGPoint(x: x, y: pick.y))
            }
            hopStarted = true
        default:
            break
        }
    }

    public func step(_ b: Behavior, body: Body, world: World, cursor: CGPoint) -> Bool {
        if b == .hopToWindow {
            guard hopStarted else { return true }
            if let dir = hopDownDirection, body.mode == .grounded, let target = targetX {
                if abs(target - body.position.x) < 4 {
                    body.leap(direction: dir)
                    hopDownDirection = nil
                } else {
                    body.walk(direction: target - body.position.x, speed: body.config.walkSpeed * 1.5)
                }
            }
            return false
        }
        guard body.mode == .grounded else { return false }
        switch b {
        case .walk, .fetch, .greet:
            guard let target = targetX else { return b == .walk }
            let dx = target - body.position.x
            if abs(dx) < 4 {
                body.stop()
                return true
            }
            let speed = b == .walk ? body.config.walkSpeed * speedScale : body.config.runSpeed
            body.walk(direction: dx, speed: speed)
        case .zoomies:
            body.walk(direction: zoomDirection, speed: body.config.runSpeed * 1.2)
        case .chaseCursor:
            let segment = body.standingOn ?? world.segment(under: body.position)
            let dx = cursor.x - body.position.x
            if let s = segment, s.contains(x: cursor.x), abs(dx) > 30 {
                body.walk(direction: dx, speed: body.config.runSpeed)
            } else {
                body.stop()
                body.face(right: dx >= 0)
            }
        default:
            body.stop()
        }
        return false
    }

    public func handle(_ event: BodyEvent, behavior: Behavior, body: Body) -> Bool {
        switch (behavior, event) {
        case (.zoomies, .hitEdge):
            zoomDirection = -zoomDirection
            return false
        case (.walk, .hitEdge):
            return true
        case (.hopToWindow, .landed):
            return true
        case (.hopToWindow, .hitEdge):
            if let dir = hopDownDirection {
                body.leap(direction: dir)
                hopDownDirection = nil
            }
            return false
        default:
            return false
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter BehaviorExecutorTests`
Expected: 9 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CorgiCore/BehaviorExecutor.swift Tests/CorgiCoreTests/BehaviorExecutorTests.swift
git commit -m "feat: per-behavior steering"
```

### Task 9: Animation manifest and behavior-to-animation mapping

**Files:**
- Create: `Sources/CorgiCore/AnimationManifest.swift`
- Test: `Tests/CorgiCoreTests/AnimationManifestTests.swift`

**Interfaces:**
- Consumes: `Behavior` (Task 7), `BodyMode` (Task 6).
- Produces:
  - `enum AnimState: String, CaseIterable, Codable { idle, walk, run, sit, sleep, eat, beg, dangle, fall, land, wiggle, bath, fetch }`
  - `struct AnimationSpec: Codable, Equatable { var folder: String; var fps: Double; var loop: Bool; var anchor: [Double] }` (anchor is normalized `[x, y]`, `[0.5, 0]` = bottom center = feet)
  - `struct AnimationManifest: Codable, Equatable { var scale: Double?; var states: [String: AnimationSpec]; static func load(from: URL) throws -> AnimationManifest; func resolve(_ state: AnimState) -> (state: AnimState, spec: AnimationSpec)?; var missingStates: [AnimState] }`
  - `func animState(for behavior: Behavior, mode: BodyMode, isMoving: Bool) -> AnimState`
  - `AnimationManifestError.missingIdle` thrown by `load` when the manifest has no `idle`.

Example `manifest.json` (this is the format to convert a bought pack into):
```json
{
  "scale": 0.5,
  "states": {
    "idle":  { "folder": "idle",  "fps": 8,  "loop": true,  "anchor": [0.5, 0.0] },
    "walk":  { "folder": "walk",  "fps": 12, "loop": true,  "anchor": [0.5, 0.0] },
    "sleep": { "folder": "sleep", "fps": 4,  "loop": true,  "anchor": [0.5, 0.0] },
    "land":  { "folder": "land",  "fps": 16, "loop": false, "anchor": [0.5, 0.0] }
  }
}
```

- [ ] **Step 1: Write the failing tests**

`Tests/CorgiCoreTests/AnimationManifestTests.swift`:
```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AnimationManifestTests`
Expected: compile error, `cannot find 'AnimationManifest' in scope`.

- [ ] **Step 3: Implement**

`Sources/CorgiCore/AnimationManifest.swift`:
```swift
import Foundation

public enum AnimState: String, CaseIterable, Codable {
    case idle, walk, run, sit, sleep, eat, beg, dangle, fall, land, wiggle, bath, fetch
}

public struct AnimationSpec: Codable, Equatable {
    public var folder: String
    public var fps: Double
    public var loop: Bool
    public var anchor: [Double]

    public init(folder: String, fps: Double, loop: Bool, anchor: [Double]) {
        self.folder = folder
        self.fps = fps
        self.loop = loop
        self.anchor = anchor
    }
}

public enum AnimationManifestError: Error, Equatable {
    case missingIdle
}

public struct AnimationManifest: Codable, Equatable {
    public var scale: Double?
    public var states: [String: AnimationSpec]

    public static func load(from url: URL) throws -> AnimationManifest {
        let m = try JSONDecoder().decode(AnimationManifest.self, from: Data(contentsOf: url))
        guard m.states[AnimState.idle.rawValue] != nil else { throw AnimationManifestError.missingIdle }
        return m
    }

    public func resolve(_ state: AnimState) -> (state: AnimState, spec: AnimationSpec)? {
        if let spec = states[state.rawValue] { return (state, spec) }
        if let idle = states[AnimState.idle.rawValue] { return (.idle, idle) }
        return nil
    }

    public var missingStates: [AnimState] {
        AnimState.allCases.filter { states[$0.rawValue] == nil }
    }
}

public func animState(for behavior: Behavior, mode: BodyMode, isMoving: Bool) -> AnimState {
    switch mode {
    case .held: return .dangle
    case .airborne: return .fall
    case .grounded: break
    }
    if isMoving {
        switch behavior {
        case .zoomies, .chaseCursor, .fetch, .greet: return .run
        default: return .walk
        }
    }
    switch behavior {
    case .sit, .chaseCursor: return .sit
    case .sleep: return .sleep
    case .beg: return .beg
    case .eat: return .eat
    case .bath: return .bath
    case .fetch: return .fetch
    case .greet: return .wiggle
    case .dangle: return .dangle
    case .fall: return .fall
    default: return .idle
    }
}
```

- [ ] **Step 4: Run all core tests**

Run: `swift test`
Expected: all 66 CorgiCore tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CorgiCore/AnimationManifest.swift Tests/CorgiCoreTests/AnimationManifestTests.swift
git commit -m "feat: animation manifest with idle fallback"
```

### Task 10: App shell (menu bar, login item, app bundle)

**Files:**
- Replace: `Sources/DesktopCorgi/main.swift`
- Create: `Sources/DesktopCorgi/AppDelegate.swift`
- Create: `Sources/DesktopCorgi/LoginItem.swift`
- Create: `scripts/bundle.sh`
- Create: `.gitignore`

**Interfaces:**
- Produces: `final class AppDelegate: NSObject, NSApplicationDelegate` (grown in later tasks), `enum LoginItem { static var isEnabled: Bool; static func setEnabled(_ on: Bool) }`, `scripts/bundle.sh` builds `build/DesktopCorgi.app`.

The app layer is AppKit glue, so these tasks are verified by running the app, not by unit tests.

- [ ] **Step 1: Write the files**

`.gitignore`:
```
.build/
build/
.swiftpm/
```

`Sources/DesktopCorgi/main.swift`:
```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

`Sources/DesktopCorgi/LoginItem.swift`:
```swift
import Foundation
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("DesktopCorgi: login item change failed: \(error)")
        }
    }
}
```

`Sources/DesktopCorgi/AppDelegate.swift`:
```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐶"
        let menu = NSMenu()
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        sender.state = LoginItem.isEnabled ? .on : .off
    }
}
```

`scripts/bundle.sh`:
```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/DesktopCorgi.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DesktopCorgi "$APP/Contents/MacOS/DesktopCorgi"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.desktopcorgi</string>
  <key>CFBundleName</key><string>DesktopCorgi</string>
  <key>CFBundleExecutable</key><string>DesktopCorgi</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
```

- [ ] **Step 2: Build and run**

Run: `chmod +x scripts/bundle.sh && ./scripts/bundle.sh && open build/DesktopCorgi.app`
Expected: "Built build/DesktopCorgi.app". A 🐶 appears in the menu bar, nothing in the Dock.

- [ ] **Step 3: Check login item**

Run: `cp -R build/DesktopCorgi.app /Applications/ && open /Applications/DesktopCorgi.app`, quit the copy from `build/` first. Click 🐶 then "Launch at Login".
Expected: item shows a check mark; System Settings > General > Login Items lists DesktopCorgi. Untick it again.

- [ ] **Step 4: Commit**

```bash
git add .gitignore Sources/DesktopCorgi scripts/bundle.sh
git commit -m "feat: menu bar app shell with login item and bundler"
```

### Task 11: Overlay windows and placeholder corgi

**Files:**
- Create: `Sources/DesktopCorgi/Animation/AnimationBackend.swift`
- Create: `Sources/DesktopCorgi/Animation/PlaceholderBackend.swift`
- Create: `Sources/DesktopCorgi/OverlayWindow.swift`
- Create: `Sources/DesktopCorgi/OverlayManager.swift`
- Modify: `Sources/DesktopCorgi/AppDelegate.swift`

**Interfaces:**
- Consumes: `AnimState` (Task 9).
- Produces:
  - `protocol AnimationBackend: AnyObject { var node: SKNode { get }; var size: CGSize { get }; func play(_ state: AnimState); func setFacing(right: Bool) }` (feet at `node` origin)
  - `final class PlaceholderBackend: AnimationBackend`
  - `protocol SceneInputHandler: AnyObject { func mouseDown(at: CGPoint); func mouseDragged(to: CGPoint); func mouseUp(at: CGPoint); func rightMouseDown(_ event: NSEvent, in view: NSView) }` (points are AppKit global)
  - `final class OverlayWindow: NSPanel { let skView: SKView; let scene: OverlayScene }`, `final class OverlayScene: SKScene { weak var input: SceneInputHandler? }`
  - `final class OverlayManager { init(corgiNode: SKNode); weak var input: SceneInputHandler?; var currentScene: OverlayScene?; func rebuild(); func place(globalFeet: CGPoint); func setClickThrough(_: Bool); func setFPS(_: Int); func setPaused(_: Bool); func toScene(_ global: CGPoint) -> CGPoint }`

- [ ] **Step 1: Animation protocol and placeholder corgi**

`Sources/DesktopCorgi/Animation/AnimationBackend.swift`:
```swift
import CorgiCore
import SpriteKit

protocol AnimationBackend: AnyObject {
    /// Root node. Its origin is the corgi's feet.
    var node: SKNode { get }
    /// Size in points, used for the hit box.
    var size: CGSize { get }
    func play(_ state: AnimState)
    func setFacing(right: Bool)
}
```

`Sources/DesktopCorgi/Animation/PlaceholderBackend.swift`:
```swift
import CorgiCore
import SpriteKit

/// Code-drawn corgi used until an asset pack is installed. Faces right by default.
final class PlaceholderBackend: AnimationBackend {
    let node = SKNode()
    let size = CGSize(width: 96, height: 72)
    private let figure = SKNode()
    private var facingRight = true

    private static let fur = NSColor(red: 0.91, green: 0.64, blue: 0.24, alpha: 1)

    init() {
        node.addChild(figure)
        for x in [-22.0, -12.0, 14.0, 24.0] {
            figure.addChild(shape(SKShapeNode(rect: CGRect(x: x - 3, y: 0, width: 6, height: 14), cornerRadius: 3), Self.fur))
        }
        figure.addChild(shape(SKShapeNode(ellipseOf: CGSize(width: 74, height: 38)), Self.fur, at: CGPoint(x: 0, y: 24)))
        figure.addChild(shape(SKShapeNode(ellipseOf: CGSize(width: 40, height: 16)), .white, at: CGPoint(x: 4, y: 16)))
        figure.addChild(shape(SKShapeNode(circleOfRadius: 6), .white, at: CGPoint(x: -38, y: 32)))
        figure.addChild(shape(SKShapeNode(circleOfRadius: 17), Self.fur, at: CGPoint(x: 36, y: 46)))
        figure.addChild(shape(SKShapeNode(ellipseOf: CGSize(width: 18, height: 11)), .white, at: CGPoint(x: 48, y: 41)))
        figure.addChild(shape(SKShapeNode(circleOfRadius: 2.5), .black, at: CGPoint(x: 56, y: 43)))
        figure.addChild(shape(SKShapeNode(circleOfRadius: 2.5), .black, at: CGPoint(x: 41, y: 51)))
        for (a, b, c) in [(CGPoint(x: 24, y: 56), CGPoint(x: 27, y: 74), CGPoint(x: 35, y: 60)),
                          (CGPoint(x: 37, y: 61), CGPoint(x: 44, y: 76), CGPoint(x: 48, y: 57))] {
            let path = CGMutablePath()
            path.addLines(between: [a, b, c])
            path.closeSubpath()
            figure.addChild(shape(SKShapeNode(path: path), Self.fur))
        }
    }

    private func shape(_ s: SKShapeNode, _ color: NSColor, at p: CGPoint = .zero) -> SKShapeNode {
        s.fillColor = color
        s.strokeColor = color.blended(withFraction: 0.3, of: .black) ?? color
        s.lineWidth = 1
        s.position = p
        return s
    }

    func setFacing(right: Bool) {
        facingRight = right
        figure.xScale = right ? abs(figure.xScale) : -abs(figure.xScale)
    }

    func play(_ state: AnimState) {
        figure.removeAllActions()
        figure.position = .zero
        figure.zRotation = 0
        figure.setScale(1)
        setFacing(right: facingRight)
        switch state {
        case .walk, .run:
            let t = state == .run ? 0.08 : 0.16
            figure.run(.repeatForever(.sequence([.moveBy(x: 0, y: 3, duration: t), .moveBy(x: 0, y: -3, duration: t)])))
        case .sleep:
            figure.yScale = 0.7
        case .sit:
            figure.yScale = 0.9
        case .beg:
            figure.zRotation = 0.25
        case .eat:
            figure.run(.repeatForever(.sequence([.rotate(toAngle: -0.15, duration: 0.2), .rotate(toAngle: 0, duration: 0.2)])))
        case .dangle:
            figure.run(.repeatForever(.sequence([.rotate(toAngle: 0.2, duration: 0.4), .rotate(toAngle: -0.2, duration: 0.4)])))
        case .wiggle:
            figure.run(.repeat(.sequence([.rotate(toAngle: 0.15, duration: 0.08), .rotate(toAngle: -0.15, duration: 0.08)]), count: 4))
        case .bath:
            figure.run(.repeatForever(.sequence([.moveBy(x: 3, y: 0, duration: 0.05), .moveBy(x: -3, y: 0, duration: 0.05)])))
        case .fall:
            figure.yScale = 1.05
        case .land:
            figure.yScale = 0.85
        case .idle, .fetch:
            break
        }
    }
}
```

- [ ] **Step 2: Overlay window and scene**

`Sources/DesktopCorgi/OverlayWindow.swift`:
```swift
import AppKit
import SpriteKit

protocol SceneInputHandler: AnyObject {
    func mouseDown(at global: CGPoint)
    func mouseDragged(to global: CGPoint)
    func mouseUp(at global: CGPoint)
    func rightMouseDown(_ event: NSEvent, in view: NSView)
}

final class OverlayScene: SKScene {
    weak var input: SceneInputHandler?

    override func mouseDown(with event: NSEvent) { input?.mouseDown(at: NSEvent.mouseLocation) }
    override func mouseDragged(with event: NSEvent) { input?.mouseDragged(to: NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) { input?.mouseUp(at: NSEvent.mouseLocation) }
    override func rightMouseDown(with event: NSEvent) {
        if let view { input?.rightMouseDown(event, in: view) }
    }
}

/// Transparent, borderless, always-on-top panel covering one screen.
final class OverlayWindow: NSPanel {
    let skView: SKView
    let scene: OverlayScene

    init(screen: NSScreen) {
        let frame = screen.frame
        skView = SKView(frame: NSRect(origin: .zero, size: frame.size))
        scene = OverlayScene(size: frame.size)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        skView.allowsTransparency = true
        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)
        contentView = skView
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

Note: without `.fullScreenAuxiliary` the panel does not show on full screen Spaces, which is how the corgi hides during full screen apps.

- [ ] **Step 3: Overlay manager**

`Sources/DesktopCorgi/OverlayManager.swift`:
```swift
import AppKit
import SpriteKit

final class OverlayManager {
    private(set) var overlays: [OverlayWindow] = []
    let corgiNode: SKNode
    weak var input: SceneInputHandler? {
        didSet { overlays.forEach { $0.scene.input = input } }
    }

    init(corgiNode: SKNode) {
        self.corgiNode = corgiNode
        rebuild()
    }

    var currentScene: OverlayScene? { corgiNode.scene as? OverlayScene }

    private var currentOverlay: OverlayWindow? {
        overlays.first { $0.scene === corgiNode.scene }
    }

    func rebuild() {
        corgiNode.removeFromParent()
        overlays.forEach { $0.close() }
        overlays = NSScreen.screens.map { OverlayWindow(screen: $0) }
        overlays.forEach {
            $0.scene.input = input
            $0.orderFrontRegardless()
        }
    }

    func toScene(_ global: CGPoint) -> CGPoint {
        guard let o = currentOverlay else { return global }
        return CGPoint(x: global.x - o.frame.minX, y: global.y - o.frame.minY)
    }

    func place(globalFeet p: CGPoint) {
        guard let target = overlays.first(where: { $0.frame.minX <= p.x && p.x < $0.frame.maxX }) ?? overlays.first
        else { return }
        if corgiNode.scene !== target.scene {
            corgiNode.removeFromParent()
            target.scene.addChild(corgiNode)
        }
        corgiNode.position = CGPoint(x: p.x - target.frame.minX, y: p.y - target.frame.minY)
    }

    func setClickThrough(_ through: Bool) {
        for o in overlays where o.ignoresMouseEvents != through { o.ignoresMouseEvents = through }
    }

    func setFPS(_ fps: Int) {
        for o in overlays where o.skView.preferredFramesPerSecond != fps { o.skView.preferredFramesPerSecond = fps }
    }

    func setPaused(_ paused: Bool) {
        overlays.forEach { $0.skView.isPaused = paused }
    }
}
```

- [ ] **Step 4: Show a static corgi**

In `AppDelegate`, add properties and append to the end of `applicationDidFinishLaunching` (temporary, replaced in Task 12):
```swift
    var backend: AnimationBackend!
    var overlays: OverlayManager!
```
```swift
        backend = PlaceholderBackend()
        overlays = OverlayManager(corgiNode: backend.node)
        if let vf = NSScreen.main?.visibleFrame {
            overlays.place(globalFeet: CGPoint(x: vf.midX, y: vf.minY))
        }
        backend.play(.walk)
```

- [ ] **Step 5: Run and verify**

Run: `./scripts/bundle.sh && open build/DesktopCorgi.app`
Expected: an orange cartoon corgi bobs at the bottom center of the main screen, just above the Dock, on top of other windows. Clicking on or around it reaches the app underneath. Switching Spaces keeps it visible. Putting a window in full screen hides it.

- [ ] **Step 6: Commit**

```bash
git add Sources/DesktopCorgi
git commit -m "feat: transparent overlay windows with placeholder corgi"
```

### Task 12: Window list, controller loop, saving

**Files:**
- Create: `Sources/DesktopCorgi/CGWindowListProvider.swift`
- Create: `Sources/DesktopCorgi/PetController.swift`
- Replace: `Sources/DesktopCorgi/AppDelegate.swift`

**Interfaces:**
- Consumes: everything in `CorgiCore`; `AnimationBackend`, `OverlayManager` (Task 11); `LoginItem` (Task 10).
- Produces:
  - `final class CGWindowListProvider: WindowListProvider`
  - `final class PetController { init(needs: NeedsEngine, backend: AnimationBackend); let needs, brain, executor, world, body, backend, overlays; func start(); func tick(); func refreshWorld(); func screensChanged(); func beginBehavior(_: Behavior); func stepFinished(); var animOverride: (state: AnimState, until: CFTimeInterval)?; var hitRect: CGRect }`
  - `AppDelegate` owns `store: StateStore`, `needs: NeedsEngine`, `controller: PetController`, and saves every 60s and on quit.

- [ ] **Step 1: Real window list**

`Sources/DesktopCorgi/CGWindowListProvider.swift`:
```swift
import AppKit
import CorgiCore

/// Reads on-screen normal windows. Window bounds need no special permission.
final class CGWindowListProvider: WindowListProvider {
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    func visibleWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.height
        else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let id = info[kCGWindowNumber as String] as? Int,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  bounds.height >= 50
            else { return nil }
            return WindowInfo(id: id, frame: appKitRect(fromCGBounds: bounds, primaryScreenHeight: primaryHeight))
        }
    }
}
```

- [ ] **Step 2: Controller**

`Sources/DesktopCorgi/PetController.swift`:
```swift
import AppKit
import CorgiCore
import SpriteKit

final class PetController {
    let needs: NeedsEngine
    let brain = Brain()
    let executor = BehaviorExecutor()
    let world: World
    let body: Body
    let backend: AnimationBackend
    let overlays: OverlayManager

    var animOverride: (state: AnimState, until: CFTimeInterval)?
    private var currentAnim: AnimState?
    private var timer: Timer?
    private var timerFPS = 0
    private var worldTimer: Timer?
    private var lastTick = CACurrentMediaTime()

    init(needs: NeedsEngine, backend: AnimationBackend) {
        self.needs = needs
        self.backend = backend
        overlays = OverlayManager(corgiNode: backend.node)
        world = World(provider: CGWindowListProvider(), screens: NSScreen.screens.map(\.visibleFrame))
        let vf = NSScreen.main?.visibleFrame ?? .zero
        body = Body(position: CGPoint(x: vf.midX, y: vf.maxY - 100))
    }

    var hitRect: CGRect {
        CGRect(x: body.position.x - backend.size.width / 2, y: body.position.y,
               width: backend.size.width, height: backend.size.height)
    }

    func start() {
        world.refresh()
        worldTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshWorld() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshWorld() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.screensChanged() }
        setRate(30)
    }

    private func setRate(_ fps: Int) {
        guard fps != timerFPS else { return }
        timerFPS = fps
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / Double(fps), repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        overlays.setFPS(fps)
    }

    func refreshWorld() {
        if body.apply(world.refresh()) == .startedFalling { fell() }
    }

    func screensChanged() {
        world.setScreens(NSScreen.screens.map(\.visibleFrame))
        overlays.rebuild()
        body.clamp(to: world.screens)
    }

    /// Called when the floor disappears under the corgi.
    func fell() {
        brain.interrupt(with: .fall, duration: 5)
        beginBehavior(.fall)
    }

    func beginBehavior(_ b: Behavior) {
        if needs.state.isAsleep != (b == .sleep) { needs.setAsleep(b == .sleep) }
        executor.speedScale = needs.isLow(.happiness) ? 0.6 : 1
        executor.begin(b, body: body, world: world, cursor: NSEvent.mouseLocation)
    }

    /// The executor says the current behavior is done.
    func stepFinished() {
        brain.finishCurrent()
    }

    func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now
        needs.tick()

        let canHop = !world.reachableSegments(from: body.position, maxJumpUp: body.config.maxJumpUp,
                                              maxJumpAcross: body.config.maxJumpAcross).isEmpty
        let ctx = BrainContext(needs: needs.state, lowThreshold: needs.config.lowThreshold, canHop: canHop)
        if let next = brain.update(dt: dt, ctx) { beginBehavior(next) }

        let cursor = NSEvent.mouseLocation
        if executor.step(brain.current, body: body, world: world, cursor: cursor) { stepFinished() }
        if let event = body.step(dt: dt, world: world) {
            if executor.handle(event, behavior: brain.current, body: body) { stepFinished() }
            if event == .landed {
                animOverride = (.land, now + 0.25)
                if brain.current == .fall { brain.finishCurrent() }
            }
            if event == .startedFalling { fell() }
        }
        body.clamp(to: world.screens)

        overlays.place(globalFeet: body.position)
        backend.setFacing(right: body.facingRight)
        updateAnimation(now)
        overlays.setClickThrough(!(body.mode == .held || hitRect.contains(cursor)))
        setRate(body.isMoving || body.mode == .held || animOverride != nil ? 30 : 10)
    }

    private func updateAnimation(_ now: CFTimeInterval) {
        if let o = animOverride, o.until <= now { animOverride = nil }
        let state = animOverride?.state
            ?? animState(for: brain.current, mode: body.mode, isMoving: body.isMoving)
        if state != currentAnim {
            currentAnim = state
            backend.play(state)
        }
    }
}
```

Note: the click-through check runs at 10fps when idle, so a click right after the cursor arrives on a still corgi can take up to 0.1s to register. That is fine.

- [ ] **Step 3: AppDelegate with loading and saving**

Replace `Sources/DesktopCorgi/AppDelegate.swift`:
```swift
import AppKit
import CorgiCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let store = StateStore(directory: StateStore.defaultDirectory)
    var needs: NeedsEngine!
    var controller: PetController!
    var awaySeconds: TimeInterval = 0
    private var saveTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        var loaded: NeedsState?
        do {
            loaded = try store.load()
        } catch {
            NSLog("DesktopCorgi: state file was corrupt, starting fresh: \(error)")
        }
        needs = NeedsEngine(state: loaded ?? .fresh(at: Date()), clock: SystemClock())
        if loaded != nil { awaySeconds = needs.catchUpOffline() }

        controller = PetController(needs: needs, backend: PlaceholderBackend())
        controller.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐶"
        let menu = NSMenu()
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        save()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.save() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        save()
    }

    func save() {
        needs.markSaved()
        do { try store.save(needs.state) } catch { NSLog("DesktopCorgi: save failed: \(error)") }
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        sender.state = LoginItem.isEnabled ? .on : .off
    }
}
```

- [ ] **Step 4: Build, run, verify**

Run: `swift test && ./scripts/bundle.sh && open build/DesktopCorgi.app`
Expected:
- The corgi drops in from the top of the main screen and lands on the screen bottom or on a window.
- Over a minute or two it walks, sits, and hops onto window title bars. Dragging that window carries it. Closing that window makes it fall.
- `cat ~/Library/Application\ Support/DesktopCorgi/state.json` shows the needs. Quit, wait 2 minutes, relaunch: `lastSaved` changes and hunger is a bit lower.

- [ ] **Step 5: Commit**

```bash
git add Sources/DesktopCorgi
git commit -m "feat: live world, controller loop, and saving"
```

### Task 13: Asset pack backend

**Files:**
- Create: `Sources/DesktopCorgi/Animation/FrameSequenceBackend.swift`
- Modify: `Sources/DesktopCorgi/AppDelegate.swift` (backend choice)

**Interfaces:**
- Consumes: `AnimationManifest`, `AnimState`, `AnimationManifestError` (Task 9), `AnimationBackend` (Task 11), `StateStore.defaultDirectory` (Task 3).
- Produces: `final class FrameSequenceBackend: AnimationBackend { init(packURL: URL) throws }`, `func makeBackend() -> AnimationBackend` on `AppDelegate`.
- Pack frames must face right. Frames inside each folder play in natural filename order (`2.png` before `10.png`).

- [ ] **Step 1: Write the backend**

`Sources/DesktopCorgi/Animation/FrameSequenceBackend.swift`:
```swift
import AppKit
import CorgiCore
import SpriteKit

final class FrameSequenceBackend: AnimationBackend {
    let node = SKNode()
    let size: CGSize
    private let sprite = SKSpriteNode()
    private let scale: CGFloat
    private var animations: [AnimState: (spec: AnimationSpec, frames: [SKTexture])] = [:]
    private var facingRight = true

    init(packURL: URL) throws {
        let manifest = try AnimationManifest.load(from: packURL.appendingPathComponent("manifest.json"))
        for (key, spec) in manifest.states {
            guard let state = AnimState(rawValue: key) else {
                NSLog("DesktopCorgi: manifest has unknown state '\(key)', skipping")
                continue
            }
            let dir = packURL.appendingPathComponent(spec.folder)
            let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "png" }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            let frames = files.compactMap { NSImage(contentsOf: $0) }.map { SKTexture(image: $0) }
            guard !frames.isEmpty else {
                NSLog("DesktopCorgi: no PNG frames in \(dir.path), '\(key)' will use idle")
                continue
            }
            animations[state] = (spec, frames)
        }
        guard let idle = animations[.idle] else { throw AnimationManifestError.missingIdle }
        let missing = AnimState.allCases.filter { animations[$0] == nil }
        if !missing.isEmpty {
            NSLog("DesktopCorgi: pack has no \(missing.map(\.rawValue).joined(separator: ", ")); using idle for those")
        }
        scale = CGFloat(manifest.scale ?? 1)
        let frameSize = idle.frames[0].size()
        size = CGSize(width: frameSize.width * scale, height: frameSize.height * scale)
        sprite.setScale(scale)
        node.addChild(sprite)
        play(.idle)
    }

    func play(_ state: AnimState) {
        guard let entry = animations[state] ?? animations[.idle] else { return }
        sprite.removeAllActions()
        if entry.spec.anchor.count == 2 {
            sprite.anchorPoint = CGPoint(x: entry.spec.anchor[0], y: entry.spec.anchor[1])
        }
        sprite.texture = entry.frames[0]
        sprite.size = entry.frames[0].size()
        sprite.setScale(scale)
        setFacing(right: facingRight)
        let animation = SKAction.animate(with: entry.frames, timePerFrame: 1 / max(entry.spec.fps, 1),
                                         resize: true, restore: false)
        sprite.run(entry.spec.loop ? .repeatForever(animation) : animation)
    }

    func setFacing(right: Bool) {
        facingRight = right
        sprite.xScale = (right ? 1 : -1) * scale
    }
}
```

- [ ] **Step 2: Choose the backend at launch**

Add to `AppDelegate`:
```swift
    func makeBackend() -> AnimationBackend {
        let pack = StateStore.defaultDirectory.appendingPathComponent("CorgiPack")
        guard FileManager.default.fileExists(atPath: pack.appendingPathComponent("manifest.json").path) else {
            return PlaceholderBackend()
        }
        do {
            return try FrameSequenceBackend(packURL: pack)
        } catch {
            NSLog("DesktopCorgi: could not load asset pack, using placeholder: \(error)")
            return PlaceholderBackend()
        }
    }
```
In `applicationDidFinishLaunching`, change `PetController(needs: needs, backend: PlaceholderBackend())` to `PetController(needs: needs, backend: makeBackend())`.

- [ ] **Step 3: Make a tiny test pack and verify**

Run (makes a 2-state pack from macOS system images, just to prove loading works):
```bash
P=~/Library/Application\ Support/DesktopCorgi/CorgiPack
mkdir -p "$P/idle" "$P/walk"
sips -s format png -z 80 80 /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns --out "$P/idle/1.png"
sips -s format png -z 80 80 /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericFolderIcon.icns --out "$P/walk/1.png"
cat > "$P/manifest.json" <<'JSON'
{ "scale": 1, "states": {
  "idle": { "folder": "idle", "fps": 4, "loop": true, "anchor": [0.5, 0] },
  "walk": { "folder": "walk", "fps": 4, "loop": true, "anchor": [0.5, 0] } } }
JSON
./scripts/bundle.sh && open build/DesktopCorgi.app
```
Expected: the corgi is replaced by the app icon while idle and the folder icon while walking. `log show --last 1m --predicate 'process == "DesktopCorgi"' | grep "using idle"` lists the missing states.
Then delete the test pack: `rm -rf "$P"`. Relaunch shows the placeholder corgi again.

- [ ] **Step 4: Commit**

```bash
git add Sources/DesktopCorgi
git commit -m "feat: PNG frame sequence asset pack backend"
```

### Task 14: Pet and drag input, effects

**Files:**
- Create: `Sources/DesktopCorgi/Effects.swift`
- Modify: `Sources/DesktopCorgi/PetController.swift`

**Interfaces:**
- Consumes: `SceneInputHandler` (Task 11), `PetController` (Task 12).
- Produces:
  - `enum Effects { static func floatEmoji(_ text: String, on node: SKNode, height: CGFloat, count: Int = 1); static func makeBall() -> SKShapeNode }`
  - `extension PetController: SceneInputHandler`, `func pet()`
  - `PetController` gains `var onRightClick: ((NSEvent, NSView) -> Void)?` (wired in Task 15)

- [ ] **Step 1: Effects**

`Sources/DesktopCorgi/Effects.swift`:
```swift
import AppKit
import SpriteKit

enum Effects {
    /// Emoji that floats up from above the corgi and fades out.
    static func floatEmoji(_ text: String, on node: SKNode, height: CGFloat, count: Int = 1) {
        for i in 0..<count {
            let label = SKLabelNode(text: text)
            label.fontSize = 18
            label.position = CGPoint(x: CGFloat.random(in: -18...18), y: height)
            label.alpha = 0
            node.addChild(label)
            label.run(.sequence([
                .wait(forDuration: Double(i) * 0.15),
                .fadeIn(withDuration: 0.1),
                .group([.moveBy(x: 0, y: 40, duration: 1.0), .fadeOut(withDuration: 1.0)]),
                .removeFromParent(),
            ]))
        }
    }

    static func makeBall() -> SKShapeNode {
        let ball = SKShapeNode(circleOfRadius: 7)
        ball.fillColor = .systemRed
        ball.strokeColor = .white
        ball.lineWidth = 1.5
        return ball
    }
}
```

- [ ] **Step 2: Input handling**

Add properties to `PetController`:
```swift
    var onRightClick: ((NSEvent, NSView) -> Void)?
    private var pressPoint: CGPoint?
    private var dragging = false
```

At the end of `PetController.init`, add:
```swift
        overlays.input = self
```

Add at the bottom of `Sources/DesktopCorgi/PetController.swift`:
```swift
extension PetController: SceneInputHandler {
    func mouseDown(at global: CGPoint) {
        pressPoint = global
        dragging = false
    }

    func mouseDragged(to global: CGPoint) {
        guard let start = pressPoint else { return }
        if !dragging && hypot(global.x - start.x, global.y - start.y) > 4 {
            dragging = true
            body.pickUp()
            brain.interrupt(with: .dangle, duration: .infinity)
            beginBehavior(.dangle)
        }
        if dragging {
            body.moveHeld(to: CGPoint(x: global.x, y: global.y - backend.size.height * 0.8))
        }
    }

    func mouseUp(at global: CGPoint) {
        defer {
            pressPoint = nil
            dragging = false
        }
        if dragging {
            body.release()
            brain.interrupt(with: .fall, duration: 5)
            beginBehavior(.fall)
        } else if pressPoint != nil {
            pet()
        }
    }

    func rightMouseDown(_ event: NSEvent, in view: NSView) {
        onRightClick?(event, view)
    }

    func pet() {
        if brain.current == .sleep {
            brain.finishCurrent()
            needs.setAsleep(false)
        }
        if needs.pet() {
            Effects.floatEmoji("❤️", on: backend.node, height: backend.size.height, count: 3)
            animOverride = (.wiggle, CACurrentMediaTime() + 0.8)
        }
    }
}
```

In `fell()`, add a surprised mark as the first line:
```swift
        Effects.floatEmoji("❗", on: backend.node, height: backend.size.height)
```

- [ ] **Step 3: Run and verify**

Run: `./scripts/bundle.sh && open build/DesktopCorgi.app`
Expected:
- Click the corgi: it wiggles, 3 hearts float up. Clicking 11 times in a few seconds shows hearts only 10 times.
- Click a sleeping corgi: it wakes up.
- Drag it: it dangles and swings below the cursor and follows it across screens. Drop it over a window title bar: it lands there. Drop it in mid air: it falls to the bottom.
- Clicking anywhere not on the corgi still reaches the app underneath, including while it walks.
- Closing a window it sits on shows ❗ and it falls.

- [ ] **Step 4: Commit**

```bash
git add Sources/DesktopCorgi
git commit -m "feat: pet and drag input with effects"
```

### Task 15: Menu, care actions, fetch

**Files:**
- Create: `Sources/DesktopCorgi/PetMenu.swift`
- Modify: `Sources/DesktopCorgi/PetController.swift`
- Modify: `Sources/DesktopCorgi/AppDelegate.swift`

**Interfaces:**
- Consumes: `PetController` (Tasks 12, 14), `Effects` (Task 14), `LoginItem` (Task 10).
- Produces:
  - `struct PetMenuActions { var feed, play, bath, nap, toggleLogin: () -> Void; var loginOn: Bool }` (Task 16 adds `stats`, `toggleDebug`, `debugOn`)
  - `enum PetMenu { static func populate(_ menu: NSMenu, _ actions: PetMenuActions) }`
  - `PetController.feed()`, `.bath()`, `.nap()`, `.playBall()`
  - `AppDelegate: NSMenuDelegate`, `func makeMenuActions() -> PetMenuActions`

- [ ] **Step 1: Menu builder**

`Sources/DesktopCorgi/PetMenu.swift`:
```swift
import AppKit

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}

struct PetMenuActions {
    var feed: () -> Void
    var play: () -> Void
    var bath: () -> Void
    var nap: () -> Void
    var toggleLogin: () -> Void
    var loginOn: Bool
}

enum PetMenu {
    static func populate(_ menu: NSMenu, _ a: PetMenuActions) {
        menu.removeAllItems()
        menu.addItem(ClosureMenuItem("🍖 Feed", handler: a.feed))
        menu.addItem(ClosureMenuItem("🎾 Play Ball", handler: a.play))
        menu.addItem(ClosureMenuItem("🫧 Bath", handler: a.bath))
        menu.addItem(ClosureMenuItem("💤 Nap", handler: a.nap))
        menu.addItem(.separator())
        let login = ClosureMenuItem("Launch at Login", handler: a.toggleLogin)
        login.state = a.loginOn ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }
}
```

- [ ] **Step 2: Care actions and fetch in the controller**

Add to `PetController`:
```swift
    private enum FetchPhase { case chasing(returnX: CGFloat), returning }
    private var fetchPhase: FetchPhase?
    private var ball: SKShapeNode?

    func feed() {
        wake()
        brain.interrupt(with: .eat, duration: 4)
        beginBehavior(.eat)
        needs.feed()
        Effects.floatEmoji("🍖", on: backend.node, height: backend.size.height)
    }

    func bath() {
        wake()
        brain.interrupt(with: .bath, duration: 4)
        beginBehavior(.bath)
        needs.bath()
        Effects.floatEmoji("🫧", on: backend.node, height: backend.size.height, count: 5)
    }

    func nap() {
        brain.interrupt(with: .sleep, duration: 120)
        beginBehavior(.sleep)
    }

    func playBall() {
        wake()
        guard body.mode == .grounded, let segment = body.standingOn, segment.width > 200,
              let scene = overlays.currentScene else {
            needs.play()
            Effects.floatEmoji("❤️", on: backend.node, height: backend.size.height, count: 3)
            animOverride = (.wiggle, CACurrentMediaTime() + 0.8)
            return
        }
        let start = body.position.x
        let roomRight = segment.maxX - 20 - start, roomLeft = start - (segment.minX + 20)
        let ballX = roomRight >= roomLeft ? start + CGFloat.random(in: 100...max(100, roomRight))
                                          : start - CGFloat.random(in: 100...max(100, roomLeft))
        let landing = overlays.toScene(CGPoint(x: ballX, y: segment.y + 7))
        let launch = overlays.toScene(CGPoint(x: start, y: segment.y + 40))
        let ball = Effects.makeBall()
        ball.position = launch
        scene.addChild(ball)
        let path = CGMutablePath()
        path.move(to: launch)
        path.addQuadCurve(to: landing, control: CGPoint(x: (launch.x + landing.x) / 2, y: launch.y + 160))
        ball.run(.follow(path, asOffset: false, orientToPath: false, duration: 0.7))
        self.ball = ball

        brain.interrupt(with: .fetch, duration: 20)
        beginBehavior(.fetch)
        executor.targetX = ballX
        fetchPhase = .chasing(returnX: start)
    }

    private func wake() {
        if brain.current == .sleep { brain.finishCurrent() }
        if needs.state.isAsleep { needs.setAsleep(false) }
    }

    /// Moves the fetch along. Returns true while fetch still has work to do.
    private func advanceFetch() -> Bool {
        switch fetchPhase {
        case .chasing(let returnX):
            ball?.removeAllActions()
            ball?.removeFromParent()
            if let ball {
                ball.position = CGPoint(x: 26, y: 30)
                backend.node.addChild(ball)
            }
            executor.targetX = returnX
            fetchPhase = .returning
            return true
        case .returning:
            clearFetch()
            needs.play()
            Effects.floatEmoji("❤️", on: backend.node, height: backend.size.height, count: 3)
            return false
        case nil:
            return false
        }
    }

    private func clearFetch() {
        ball?.removeFromParent()
        ball = nil
        fetchPhase = nil
    }
```

Replace `stepFinished()` with:
```swift
    func stepFinished() {
        if brain.current == .fetch && advanceFetch() { return }
        brain.finishCurrent()
    }
```

At the top of `beginBehavior(_:)`, add:
```swift
        if b != .fetch && fetchPhase != nil { clearFetch() }
```

- [ ] **Step 3: Wire menus in AppDelegate**

Make `AppDelegate` conform to `NSMenuDelegate` (`final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate`).

In `applicationDidFinishLaunching`, replace everything from `let menu = NSMenu()` through `statusItem.menu = menu` with:
```swift
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        controller.onRightClick = { [weak self] event, view in
            guard let self else { return }
            let popup = NSMenu()
            PetMenu.populate(popup, self.makeMenuActions())
            NSMenu.popUpContextMenu(popup, with: event, for: view)
        }
```

Delete the `@objc func toggleLogin` method and add:
```swift
    func menuNeedsUpdate(_ menu: NSMenu) {
        PetMenu.populate(menu, makeMenuActions())
    }

    func makeMenuActions() -> PetMenuActions {
        PetMenuActions(
            feed: { [weak self] in self?.controller.feed() },
            play: { [weak self] in self?.controller.playBall() },
            bath: { [weak self] in self?.controller.bath() },
            nap: { [weak self] in self?.controller.nap() },
            toggleLogin: { LoginItem.setEnabled(!LoginItem.isEnabled) },
            loginOn: LoginItem.isEnabled
        )
    }
```

- [ ] **Step 4: Run and verify**

Run: `./scripts/bundle.sh && open build/DesktopCorgi.app`
Expected:
- Right-click the corgi and click the 🐶 menu bar icon: both show Feed, Play Ball, Bath, Nap, Launch at Login, Quit.
- Feed: 🍖 floats, eat animation for about 4s. `state.json` hunger goes up after the next save (or quit).
- Bath: bubbles. Nap: it sleeps until energy reaches 95 or you click it.
- Play Ball on the screen bottom: a red ball arcs away, the corgi runs to it, carries it back, then hearts. Dragging the corgi mid-fetch removes the ball.
- Play Ball on a narrow perch: just hearts and a wiggle.

- [ ] **Step 5: Commit**

```bash
git add Sources/DesktopCorgi
git commit -m "feat: care menu and ball fetch"
```

### Task 16: Stats, greeting, sleep z's, lock pause, debug overlay

**Files:**
- Create: `Sources/DesktopCorgi/StatsView.swift`
- Create: `Sources/DesktopCorgi/DebugOverlay.swift`
- Modify: `Sources/DesktopCorgi/PetMenu.swift`
- Modify: `Sources/DesktopCorgi/PetController.swift`
- Modify: `Sources/DesktopCorgi/AppDelegate.swift`

**Interfaces:**
- Consumes: `NeedsState`, `NeedsEngine.level` (Tasks 1-2), `World.segments`, `PetController.hitRect`, `OverlayManager.overlays`.
- Produces:
  - `struct StatsView: View { let state: NeedsState; let level: Int }`
  - `final class DebugOverlay { var enabled: Bool; func update(world:hitRect:behavior:overlays:) }`
  - `PetMenuActions` gains `stats: () -> Void`, `toggleDebug: () -> Void`, `debugOn: Bool`
  - `PetController.greet()`, `PetController.setPaused(_:)`, `PetController.debug: DebugOverlay`

- [ ] **Step 1: Stats view**

`Sources/DesktopCorgi/StatsView.swift`:
```swift
import CorgiCore
import SwiftUI

struct StatsView: View {
    let state: NeedsState
    let level: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Corgi · Level \(level)").font(.headline)
            bar("🍖 Hunger", state.hunger)
            bar("❤️ Happiness", state.happiness)
            bar("⚡️ Energy", state.energy)
            bar("🫧 Cleanliness", state.cleanliness)
            Text("Together since \(state.firstMet.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 240)
    }

    private func bar(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(label)  \(Int(value.rounded()))").font(.caption)
            ProgressView(value: value, total: 100)
                .tint(value < 30 ? .red : .accentColor)
        }
    }
}
```

- [ ] **Step 2: Debug overlay**

`Sources/DesktopCorgi/DebugOverlay.swift`:
```swift
import AppKit
import CorgiCore
import SpriteKit

/// Draws floor segments (green ground, blue windows), the hit box, and the behavior name.
final class DebugOverlay {
    var enabled = false {
        didSet { if !enabled { clear() } }
    }
    private var nodes: [SKNode] = []

    func update(world: World, hitRect: CGRect, behavior: Behavior, overlays: OverlayManager) {
        clear()
        guard enabled else { return }
        for overlay in overlays.overlays {
            let origin = overlay.frame.origin
            let root = SKNode()
            root.zPosition = 100
            for s in world.segments {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: s.minX - origin.x, y: s.y - origin.y))
                path.addLine(to: CGPoint(x: s.maxX - origin.x, y: s.y - origin.y))
                let line = SKShapeNode(path: path)
                line.strokeColor = s.windowID == nil ? .systemGreen : .systemBlue
                line.lineWidth = 2
                root.addChild(line)
            }
            let box = SKShapeNode(rect: hitRect.offsetBy(dx: -origin.x, dy: -origin.y))
            box.strokeColor = .systemRed
            root.addChild(box)
            let label = SKLabelNode(text: behavior.rawValue)
            label.fontSize = 12
            label.fontColor = .systemRed
            label.position = CGPoint(x: hitRect.midX - origin.x, y: hitRect.maxY - origin.y + 4)
            root.addChild(label)
            overlay.scene.addChild(root)
            nodes.append(root)
        }
    }

    private func clear() {
        nodes.forEach { $0.removeFromParent() }
        nodes = []
    }
}
```

- [ ] **Step 3: Menu items**

In `Sources/DesktopCorgi/PetMenu.swift`, add three fields to `PetMenuActions` after `nap`:
```swift
    var stats: () -> Void
    var toggleDebug: () -> Void
    var debugOn: Bool
```
In `PetMenu.populate`, insert after the Nap item (before the first separator):
```swift
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("📊 Stats…", handler: a.stats))
        let debug = ClosureMenuItem("Debug Overlay", handler: a.toggleDebug)
        debug.state = a.debugOn ? .on : .off
        menu.addItem(debug)
```

- [ ] **Step 4: Controller additions**

Add properties to `PetController`:
```swift
    let debug = DebugOverlay()
    private var paused = false
    private var lastZzz: CFTimeInterval = 0
```

Add methods:
```swift
    func greet() {
        brain.interrupt(with: .greet, duration: 4)
        beginBehavior(.greet)
        Effects.floatEmoji("👋", on: backend.node, height: backend.size.height)
    }

    func setPaused(_ paused: Bool) {
        guard paused != self.paused else { return }
        self.paused = paused
        overlays.setPaused(paused)
        if paused {
            timer?.invalidate()
            timer = nil
            timerFPS = 0
        } else {
            lastTick = CACurrentMediaTime()
            setRate(30)
        }
    }
```

At the end of `start()`, add the lock and display sleep observers:
```swift
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.setPaused(true)
        }
        distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.setPaused(false)
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setPaused(true)
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setPaused(false)
        }
```

In `tick()`, add after `updateAnimation(now)`:
```swift
        if brain.current == .sleep && now - lastZzz > 2 {
            lastZzz = now
            Effects.floatEmoji("💤", on: backend.node, height: backend.size.height * 0.8)
        }
        debug.update(world: world, hitRect: hitRect, behavior: brain.current, overlays: overlays)
```

Note: needs keep counting while paused because `NeedsEngine.tick()` uses wall clock time since its last tick.

- [ ] **Step 5: AppDelegate additions**

Add a property: `private var popover: NSPopover?`

In `applicationDidFinishLaunching`, after `controller.start()`:
```swift
        if awaySeconds > 3600 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.controller.greet() }
        }
```

Add a method:
```swift
    func showStats() {
        guard let button = statusItem.button else { return }
        let p = NSPopover()
        p.behavior = .transient
        p.contentViewController = NSHostingController(rootView: StatsView(state: needs.state, level: needs.level))
        p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover = p
    }
```
Add `import SwiftUI` at the top of `AppDelegate.swift`.

In `makeMenuActions()`, add after `nap:`:
```swift
            stats: { [weak self] in DispatchQueue.main.async { self?.showStats() } },
            toggleDebug: { [weak self] in self?.controller.debug.enabled.toggle() },
            debugOn: controller.debug.enabled,
```
(`async` lets the menu finish closing before the popover opens.)

- [ ] **Step 6: Run and verify**

Run: `./scripts/bundle.sh && open build/DesktopCorgi.app`
Expected:
- 🐶 > 📊 Stats… opens a popover under the menu bar icon with 4 bars, the level, and the date you met. Low bars are red.
- 🐶 > Debug Overlay draws green lines on screen bottoms, blue lines on window tops, a red box around the corgi, and its behavior name. Blue lines vanish where a window in front covers the edge.
- A sleeping corgi puffs 💤 every 2s.
- Lock the screen (Ctrl+Cmd+Q) for 1 minute and unlock: the corgi is where you left it and Activity Monitor shows DesktopCorgi near 0% CPU while locked.
- Set `lastSaved` in `state.json` to 2 hours ago while the app is quit (edit the number: subtract 7200), relaunch: 👋 and the corgi runs toward your cursor.

- [ ] **Step 7: Commit**

```bash
git add Sources/DesktopCorgi
git commit -m "feat: stats popover, greeting, lock pause, debug overlay"
```

### Task 17: README, asset pack guide, manual checklist

**Files:**
- Create: `README.md`
- Create: `docs/MANUAL_CHECKLIST.md`

**Interfaces:** none (docs only).

- [ ] **Step 1: Write README.md**

`README.md`:
````markdown
# Desktop Corgi

A cartoon corgi that lives on your Mac screen. It walks along the bottom, hops onto window title bars, and has needs (hunger, happiness, energy, cleanliness) you look after.

## Build and run

Needs macOS 14+ and Xcode.

```bash
swift test                 # core logic tests
./scripts/bundle.sh        # builds build/DesktopCorgi.app
open build/DesktopCorgi.app
```

For launch at login, copy the app to `/Applications` first and turn it on from the 🐶 menu.

## Playing

- Click: pet (hearts). Click a sleeping corgi to wake it.
- Drag: pick it up, drop it anywhere.
- Right-click it or click 🐶 in the menu bar: Feed, Play Ball, Bath, Nap, Stats, Debug Overlay.
- Needs drop over time, also while the app is closed, but never below 15.

Save file: `~/Library/Application Support/DesktopCorgi/state.json`. Delete it to start over.

## Using a bought art pack

Put the pack in `~/Library/Application Support/DesktopCorgi/CorgiPack/`:

```
CorgiPack/
  manifest.json
  idle/0001.png 0002.png ...
  walk/...
```

`manifest.json`:
```json
{
  "scale": 0.5,
  "states": {
    "idle": { "folder": "idle", "fps": 8, "loop": true, "anchor": [0.5, 0.0] },
    "walk": { "folder": "walk", "fps": 12, "loop": true, "anchor": [0.5, 0.0] }
  }
}
```

- States: idle (required), walk, run, sit, sleep, eat, beg, dangle, fall, land, wiggle, bath, fetch. Missing ones use idle.
- `anchor` is where the feet are, as a fraction of the frame: `[0.5, 0.0]` is bottom center.
- `scale` shrinks or grows every frame.
- Frames must face right. Mirror them if the pack faces left: `for f in */*.png; do sips -f horizontal "$f"; done`
- Packs often come as GIFs or sprite sheets. Turn them into frames with:
  - GIF: `ffmpeg -i walk.gif walk/%04d.png`
  - Sprite sheet (for example 128x128 cells): `magick sheet.png -crop 128x128 +repage walk/%04d.png`
  (`brew install ffmpeg imagemagick`)

Restart the app after changing the pack. If the pack fails to load, the app logs why and uses the built-in placeholder corgi:
`log show --last 5m --predicate 'process == "DesktopCorgi"'`
````

- [ ] **Step 2: Write docs/MANUAL_CHECKLIST.md**

`docs/MANUAL_CHECKLIST.md`:
```markdown
# Manual checklist

Run after any change to `Sources/DesktopCorgi`. Turn on Debug Overlay for the window checks.

## Basics
- [ ] 🐶 in menu bar, no Dock icon.
- [ ] Corgi drops in at launch and lands.
- [ ] Clicks anywhere off the corgi reach the app underneath.
- [ ] Idle CPU under 2% in Activity Monitor after 1 minute of the corgi sitting or sleeping.

## Windows
- [ ] Corgi hops onto a window title bar within a few minutes (or force it with many windows open).
- [ ] Moving that window carries the corgi.
- [ ] Closing or minimizing that window makes it fall with ❗.
- [ ] A window in front covering the edge makes it fall.
- [ ] A maximized window has no blue line at its top.

## Input
- [ ] Click: hearts + wiggle, max 10 times a minute.
- [ ] Drag: dangles, follows cursor, lands where dropped.
- [ ] Right-click and 🐶 menus both work.
- [ ] Feed, Bath, Nap, Play Ball each do their thing. Fetch brings the ball back.

## Screens and Spaces
- [ ] Switching Spaces: corgi still there.
- [ ] Full screen app: corgi hidden, back when leaving full screen.
- [ ] Second monitor: corgi can be dragged there and walks on its bottom.
- [ ] Unplug the monitor the corgi is on: it reappears on the remaining screen.

## Persistence
- [ ] Quit and relaunch: stats roughly the same.
- [ ] Away more than 1 hour: 👋 greeting.
- [ ] Put `{bad` in `state.json`, relaunch: fresh corgi, `state.corrupt.json` exists.
- [ ] Lock screen: near 0% CPU, corgi in the same spot after unlock.
```

- [ ] **Step 3: Run the checklist**

Go through `docs/MANUAL_CHECKLIST.md` with the bundled app. Fix anything that fails before committing.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/MANUAL_CHECKLIST.md
git commit -m "docs: readme, asset pack guide, manual checklist"
```

---

## v2: Companion features (Tasks 18-26)

Spec section: "## v2: Companion features". Order: CorgiCore logic first (Tasks 18-23, all tested on Linux), then app wiring (Tasks 24-25, need a Mac), then docs (Task 26). Baseline before Task 18: 67 tests.

v2 replaces two v1 behaviors:
- The v1 ledge fetch (ball arcs onto the current floor, corgi walks to it and back) is removed in Task 25 and replaced by the free-flying ball chase. `Behavior.fetch` and `AnimState.fetch` stay in `CorgiCore` (existing tests and asset packs use them), they are just no longer triggered.
- The v1 overlay was not shown on full screen Spaces (no `.fullScreenAuxiliary`), so the corgi vanished there. Task 24 adds `.fullScreenAuxiliary` and makes the corgi sleep while a full screen window is in front.

Shared decisions for Tasks 18-26:
- Home is on the primary screen (the one with the menu bar, `NSScreen.screens[0]`, index 0 in `world.screens`). `NSScreen.main` follows the key window, so it would move home around.
- Full screen sleep and idle sleep both use the new behavior `idleSleep` (animation `sleep`). Full screen skips the yawn and sleeps right away; user inactivity yawns for 2s first.
- Chase Me, a ball chase, or holding the corgi blocks idle and full screen sleep. Full screen that starts during Chase Me only puts the corgi to sleep once Chase Me ends.
- Hover pet never fires while the corgi is asleep, yawning, held, airborne, or roaming. Only a click wakes a napping corgi.
- Catching the corgi in Chase Me does not end Chase Me. It gives hearts and +10 happiness (sharing the 10 pets/minute limit), and the chase goes on until the menu toggle turns it off.
- `greet` no longer runs toward the cursor. It stands, faces the cursor, waves, and says "Hi!".
- While held the animation is `scared` (was `dangle`). `AnimState.dangle` stays for packs, but the held corgi no longer uses it.

### Task 18: Body roaming mode

**Files:**
- Modify: `Sources/CorgiCore/Geometry.swift`
- Modify: `Sources/CorgiCore/Body.swift`
- Modify: `Sources/CorgiCore/AnimationManifest.swift` (one line, keeps the `BodyMode` switch exhaustive)
- Test: `Tests/CorgiCoreTests/RoamingBodyTests.swift`

**Interfaces:**
- Consumes: `Body`, `BodyConfig`, `BodyMode`, `BodyEvent` (Task 6), `World.screens` (Task 5).
- Produces:
  - `func insetRects(_ screens: [CGRect], side: CGFloat, top: CGFloat) -> [CGRect]`
  - `func rects(_ rects: [CGRect], contain p: CGPoint) -> Bool`
  - `func nearestPoint(to p: CGPoint, in rects: [CGRect]) -> CGPoint`
  - `BodyConfig.roamHeadroom: CGFloat = 80`
  - `enum BodyMode: Equatable { case grounded, airborne, held, roaming }`
  - `Body.startRoaming()`, `Body.roam(toward: CGPoint, speed: CGFloat)`, `Body.stopRoaming()`
  - `Body.step` in `.roaming`: no gravity, no floors, moves by velocity, stays inside `insetRects(world.screens, side: 20, top: roamHeadroom)`, returns `.hitEdge` when it gets pushed back inside.
  - `Body.clamp(to:)` only starts a fall for `.grounded` and `.airborne`; a roaming body is clamped and keeps roaming.

- [ ] **Step 1: Write the failing tests**

`Tests/CorgiCoreTests/RoamingBodyTests.swift`:
```swift
import XCTest
@testable import CorgiCore

final class RoamingBodyTests: XCTestCase {
    var world: World!

    override func setUp() {
        world = World(provider: FakeWindows(), screens: [screen0])
        world.refresh()
    }

    func run(_ body: Body, seconds: Double, dt: Double = 1.0 / 60) -> [BodyEvent] {
        var events: [BodyEvent] = []
        for _ in 0..<Int(seconds / dt) {
            if let e = body.step(dt: dt, world: world) { events.append(e) }
        }
        return events
    }

    func testRoamingFliesWithoutGravity() {
        let body = Body(position: CGPoint(x: 200, y: 400))
        body.startRoaming()
        body.roam(toward: CGPoint(x: 600, y: 400), speed: 240)
        XCTAssertTrue(body.isMoving)
        XCTAssertEqual(run(body, seconds: 1), [])
        XCTAssertEqual(body.mode, .roaming)
        XCTAssertEqual(body.position.x, 440, accuracy: 2)
        XCTAssertEqual(body.position.y, 400, accuracy: 0.001)
        XCTAssertTrue(body.facingRight)
    }

    func testRoamingStaysInsideScreenHeadroom() {
        let body = Body(position: CGPoint(x: 700, y: 700))
        body.startRoaming()
        body.roam(toward: CGPoint(x: 700, y: 5000), speed: 400)
        let events = run(body, seconds: 1)
        XCTAssertEqual(events.first, .hitEdge)
        XCTAssertEqual(body.position.y, 875 - body.config.roamHeadroom, accuracy: 0.001)
        XCTAssertEqual(body.mode, .roaming)
    }

    func testStopRoamingFallsToFloor() {
        let body = Body(position: CGPoint(x: 300, y: 500))
        body.startRoaming()
        body.stopRoaming()
        XCTAssertEqual(body.mode, .airborne)
        XCTAssertEqual(run(body, seconds: 2), [.landed])
        XCTAssertEqual(body.standingOn?.kind, .ground(screen: 0))
    }

    func testRoamingSurvivesMonitorUnplug() {
        let screen1 = CGRect(x: 1440, y: 0, width: 1920, height: 1000)
        world.setScreens([screen0, screen1])
        let body = Body(position: CGPoint(x: 2500, y: 600))
        body.startRoaming()
        world.setScreens([screen0])
        body.clamp(to: world.screens)
        XCTAssertEqual(body.mode, .roaming)
        _ = run(body, seconds: 0.1)
        XCTAssertLessThanOrEqual(body.position.x, 1420)
        XCTAssertLessThanOrEqual(body.position.y, 875 - body.config.roamHeadroom)
    }

    func testPickUpWhileRoamingThenReleaseFalls() {
        let body = Body(position: CGPoint(x: 300, y: 500))
        body.startRoaming()
        body.pickUp()
        XCTAssertEqual(body.mode, .held)
        body.startRoaming()
        XCTAssertEqual(body.mode, .held)
        body.release()
        XCTAssertEqual(run(body, seconds: 2), [.landed])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter RoamingBodyTests`
Expected: compile error, `value of type 'Body' has no member 'startRoaming'`.

- [ ] **Step 3: Implement**

Append to `Sources/CorgiCore/Geometry.swift`:
```swift
/// Screens shrunk by a side margin and a top headroom, so a free-moving corgi or ball stays fully visible.
public func insetRects(_ screens: [CGRect], side: CGFloat, top: CGFloat) -> [CGRect] {
    screens.map { CGRect(x: $0.minX + side, y: $0.minY,
                         width: max(0, $0.width - 2 * side), height: max(0, $0.height - top)) }
}

public func rects(_ rects: [CGRect], contain p: CGPoint) -> Bool {
    rects.contains { $0.minX <= p.x && p.x <= $0.maxX && $0.minY <= p.y && p.y <= $0.maxY }
}

/// Closest point to `p` inside any of `rects`. Returns `p` when `rects` is empty.
public func nearestPoint(to p: CGPoint, in rects: [CGRect]) -> CGPoint {
    rects.map { CGPoint(x: min(max(p.x, $0.minX), $0.maxX), y: min(max(p.y, $0.minY), $0.maxY)) }
        .min { hypot($0.x - p.x, $0.y - p.y) < hypot($1.x - p.x, $1.y - p.y) } ?? p
}
```

Replace `Sources/CorgiCore/Body.swift` with:
```swift
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

public struct BodyConfig {
    public var gravity: CGFloat = 2200
    public var walkSpeed: CGFloat = 70
    public var runSpeed: CGFloat = 240
    public var maxJumpUp: CGFloat = 420
    public var maxJumpAcross: CGFloat = 520
    public var jumpClearance: CGFloat = 50
    public var maxFallSpeed: CGFloat = 1800
    /// Room kept free above a roaming corgi's feet so it never slides under the menu bar.
    public var roamHeadroom: CGFloat = 80

    public init() {}
}

public enum BodyMode: Equatable { case grounded, airborne, held, roaming }

public enum BodyEvent: Equatable { case landed, hitEdge, startedFalling }

public final class Body {
    public let config: BodyConfig
    public private(set) var position: CGPoint
    public private(set) var velocity: CGVector = .zero
    public private(set) var mode: BodyMode = .airborne
    public private(set) var standingOn: FloorSegment?
    public private(set) var facingRight = true
    private var walkVelocity: CGFloat = 0

    public init(position: CGPoint, config: BodyConfig = .init()) {
        self.position = position
        self.config = config
    }

    public var isMoving: Bool {
        mode == .airborne || walkVelocity != 0 || (mode == .roaming && velocity != .zero)
    }

    public func walk(direction: CGFloat, speed: CGFloat) {
        guard mode == .grounded else { return }
        walkVelocity = direction.sign == .minus ? -speed : (direction == 0 ? 0 : speed)
        if direction != 0 { facingRight = direction > 0 }
    }

    public func stop() { walkVelocity = 0 }

    public func face(right: Bool) { facingRight = right }

    public func jump(to target: CGPoint) {
        guard mode == .grounded else { return }
        let g = config.gravity
        let apex = max(target.y, position.y) - position.y + config.jumpClearance
        let vy = (2 * g * apex).squareRoot()
        let tUp = vy / g
        let tDown = (2 * (position.y + apex - target.y) / g).squareRoot()
        velocity = CGVector(dx: (target.x - position.x) / (tUp + tDown), dy: vy)
        facingRight = target.x >= position.x
        walkVelocity = 0
        standingOn = nil
        mode = .airborne
    }

    /// Small hop off the end of the current segment, used to get down from a perch.
    public func leap(direction: CGFloat) {
        guard mode == .grounded, let s = standingOn else { return }
        position.x = direction < 0 ? s.minX - 1 : s.maxX + 1
        velocity = CGVector(dx: direction < 0 ? -150 : 150, dy: 250)
        facingRight = direction > 0
        walkVelocity = 0
        standingOn = nil
        mode = .airborne
    }

    /// Free flight with no gravity or floors (Chase Me and ball chase).
    public func startRoaming() {
        guard mode != .held else { return }
        mode = .roaming
        standingOn = nil
        velocity = .zero
        walkVelocity = 0
    }

    /// Sets the roaming velocity toward `target`. Stops when within 1pt of it.
    public func roam(toward target: CGPoint, speed: CGFloat) {
        guard mode == .roaming else { return }
        let dx = target.x - position.x, dy = target.y - position.y
        let dist = hypot(dx, dy)
        guard dist > 1 else {
            velocity = .zero
            return
        }
        velocity = CGVector(dx: dx / dist * speed, dy: dy / dist * speed)
        if abs(dx) > 1 { facingRight = dx > 0 }
    }

    /// Ends roaming. The body falls to whatever floor is below.
    public func stopRoaming() {
        guard mode == .roaming else { return }
        startFalling()
    }

    public func pickUp() {
        mode = .held
        standingOn = nil
        velocity = .zero
        walkVelocity = 0
    }

    public func moveHeld(to point: CGPoint) {
        guard mode == .held else { return }
        position = point
    }

    public func release() {
        guard mode == .held else { return }
        mode = .airborne
        velocity = .zero
    }

    @discardableResult
    public func apply(_ update: WorldUpdate) -> BodyEvent? {
        guard mode == .grounded, let id = standingOn?.windowID else { return nil }
        if update.vanished.contains(id) {
            return startFalling()
        }
        if let delta = update.moved[id] {
            position.x += delta.dx
            position.y += delta.dy
        }
        return nil
    }

    @discardableResult
    public func step(dt: TimeInterval, world: World) -> BodyEvent? {
        let dt = CGFloat(dt)
        switch mode {
        case .held:
            return nil
        case .grounded:
            guard let segment = world.segment(under: position) else { return startFalling() }
            standingOn = segment
            position.y = segment.y
            let nextX = position.x + walkVelocity * dt
            if segment.contains(x: nextX) {
                position.x = nextX
                return nil
            }
            position.x = segment.clampX(nextX)
            walkVelocity = 0
            return .hitEdge
        case .roaming:
            let area = insetRects(world.screens, side: 20, top: config.roamHeadroom)
            let next = CGPoint(x: position.x + velocity.dx * dt, y: position.y + velocity.dy * dt)
            if area.isEmpty || rects(area, contain: next) {
                position = next
                return nil
            }
            position = nearestPoint(to: next, in: area)
            velocity = .zero
            return .hitEdge
        case .airborne:
            velocity.dy = max(velocity.dy - config.gravity * dt, -config.maxFallSpeed)
            let next = CGPoint(x: position.x + velocity.dx * dt, y: position.y + velocity.dy * dt)
            if velocity.dy <= 0,
               let landing = world.segments
                .filter({ $0.contains(x: next.x) && position.y >= $0.y && next.y <= $0.y })
                .max(by: { $0.y < $1.y }) {
                position = CGPoint(x: next.x, y: landing.y)
                velocity = .zero
                standingOn = landing
                mode = .grounded
                return .landed
            }
            position = next
            return nil
        }
    }

    /// Pulls the body back onto the nearest screen if it ended up outside every screen.
    public func clamp(to screens: [CGRect]) {
        guard !screens.isEmpty else { return }
        let p = position
        if screens.contains(where: { $0.minX <= p.x && p.x <= $0.maxX && $0.minY <= p.y && p.y <= $0.maxY }) {
            return
        }
        let screen = screens.first { $0.minX <= p.x && p.x <= $0.maxX }
            ?? screens.min { abs($0.midX - p.x) < abs($1.midX - p.x) }!
        let clamped = CGPoint(x: min(max(position.x, screen.minX + 20), screen.maxX - 20),
                              y: min(max(position.y, screen.minY), screen.maxY - 10))
        guard clamped != position else { return }
        position = clamped
        if mode == .grounded || mode == .airborne { startFalling() }
    }

    @discardableResult
    private func startFalling() -> BodyEvent {
        mode = .airborne
        standingOn = nil
        velocity = .zero
        walkVelocity = 0
        return .startedFalling
    }
}
```

In `Sources/CorgiCore/AnimationManifest.swift`, inside `animState(for:mode:isMoving:)`, replace `    case .grounded: break` with:
```swift
    case .grounded, .roaming: break
```
(Task 19 gives roaming its own animation.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter RoamingBodyTests`
Expected: 5 tests PASS.
Run: `swift test`
Expected: 72 tests PASS (67 + 5).

- [ ] **Step 5: Commit**

```bash
git add Sources/CorgiCore/Geometry.swift Sources/CorgiCore/Body.swift Sources/CorgiCore/AnimationManifest.swift Tests/CorgiCoreTests/RoamingBodyTests.swift
git commit -m "feat: roaming body mode"
```

### Task 19: New behaviors, animation states, and the behavior-to-animation mapping

**Files:**
- Modify: `Sources/CorgiCore/Brain.swift`
- Modify: `Sources/CorgiCore/AnimationManifest.swift`
- Modify: `Sources/CorgiCore/Body.swift`
- Modify: `Sources/DesktopCorgi/Animation/PlaceholderBackend.swift` (its `switch` over `AnimState` must stay exhaustive or the Mac build breaks)
- Modify: `Sources/DesktopCorgi/PetController.swift`
- Test: `Tests/CorgiCoreTests/AnimationManifestTests.swift`, `Tests/CorgiCoreTests/BrainTests.swift`, `Tests/CorgiCoreTests/RoamingBodyTests.swift`

**Interfaces:**
- Consumes: `BodyMode.roaming` (Task 18).
- Produces:
  - `Behavior` gains `goHome, read, readSleep, music, watchTV, wave, turnAround, playBallHome, yawn, idleSleep, chaseMe, ballChase`. `Behavior.autonomous` is unchanged in this task (Task 20 adds the new autonomous ones with weights).
  - `Behavior.countsAsSleep: Bool` (true for `sleep`, `readSleep`, `idleSleep`). `Brain.finishCurrent()` resets any of them to `idle`.
  - `AnimState` gains `wave, back, read, readSleep, music, watch, yawn, scared, happy, holdBall, kick, roam` (25 states total).
  - `Body.isRunning: Bool` (walking faster than 1.6x walk speed).
  - `func animState(for behavior: Behavior, mode: BodyMode, isMoving: Bool, isRunning: Bool = false, carrying: Bool = false) -> AnimState`

Mapping (grounded and still unless noted):

| Behavior / mode | AnimState |
|---|---|
| held (any behavior) | `scared` (was `dangle`) |
| airborne | `fall` |
| roaming | `roam`, or `holdBall` when carrying the ball |
| moving, `zoomies`/`chaseCursor`/`fetch`/`greet` | `run` |
| moving, any other, `isRunning` | `run` |
| moving, any other | `walk` |
| `greet`, `wave` | `wave` (greet was `wiggle`) |
| `turnAround` | `back` |
| `read` / `readSleep` / `music` / `watchTV` | `read` / `readSleep` / `music` / `watch` |
| `yawn` | `yawn` |
| `idleSleep`, `sleep` | `sleep` |
| `playBallHome` | `kick` |
| hover pet (app override) | `happy` |

- [ ] **Step 1: Write the failing tests**

In `Tests/CorgiCoreTests/AnimationManifestTests.swift`, inside `testBehaviorToAnimation`, change two lines:
```swift
        XCTAssertEqual(animState(for: .walk, mode: .held, isMoving: false), .scared)
```
(was `.dangle`) and
```swift
        XCTAssertEqual(animState(for: .greet, mode: .grounded, isMoving: false), .wave)
```
(was `.wiggle`). Then add before the class's closing brace:
```swift
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
```

In `Tests/CorgiCoreTests/BrainTests.swift`, add before the class's closing brace:
```swift
    func testSleepLikeBehaviorsCountAsSleepAndFinishWakes() {
        XCTAssertEqual(Behavior.allCases.filter(\.countsAsSleep), [.sleep, .readSleep, .idleSleep])
        let b = brain()
        b.interrupt(with: .readSleep, duration: 60)
        b.finishCurrent()
        XCTAssertEqual(b.current, .idle)
        XCTAssertNotNil(b.update(dt: 0, ctx()))
    }
```

In `Tests/CorgiCoreTests/RoamingBodyTests.swift`, add before the class's closing brace:
```swift
    func testIsRunningOnlyAboveStrollPace() {
        let body = Body(position: CGPoint(x: 300, y: 0))
        _ = run(body, seconds: 0.1)
        body.walk(direction: 1, speed: body.config.walkSpeed)
        XCTAssertFalse(body.isRunning)
        body.walk(direction: 1, speed: body.config.runSpeed)
        XCTAssertTrue(body.isRunning)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "AnimationManifestTests|BrainTests|RoamingBodyTests"`
Expected: compile errors, `type 'Behavior' has no member 'chaseMe'`, `type 'AnimState' has no member 'scared'`, `value of type 'Body' has no member 'isRunning'`.

- [ ] **Step 3: Implement the core changes**

In `Sources/CorgiCore/Brain.swift`, replace the `Behavior` enum with:
```swift
public enum Behavior: String, CaseIterable {
    case idle, walk, sit, sleep, zoomies, chaseCursor, hopToWindow, beg
    case eat, fetch, bath, dangle, fall, greet
    case goHome, read, readSleep, music, watchTV, wave, turnAround, playBallHome
    case yawn, idleSleep, chaseMe, ballChase

    /// Behaviors the brain picks on its own. The rest only happen through `interrupt`.
    public static let autonomous: [Behavior] = [.idle, .walk, .sit, .sleep, .zoomies, .chaseCursor, .hopToWindow, .beg]

    /// Behaviors during which energy refills at the asleep rate.
    public var countsAsSleep: Bool { self == .sleep || self == .readSleep || self == .idleSleep }
}
```
and in `finishCurrent()` replace `if current == .sleep { current = .idle }` with:
```swift
        if current.countsAsSleep { current = .idle }
```

In `Sources/CorgiCore/Body.swift`, insert directly above `public func walk(direction: CGFloat, speed: CGFloat)`:
```swift
    /// True when walking faster than a stroll, so the animation should be `run`.
    public var isRunning: Bool { abs(walkVelocity) > config.walkSpeed * 1.6 }

```

Replace `Sources/CorgiCore/AnimationManifest.swift` with:
```swift
import Foundation

public enum AnimState: String, CaseIterable, Codable {
    case idle, walk, run, sit, sleep, eat, beg, dangle, fall, land, wiggle, bath, fetch
    case wave, back, read, readSleep, music, watch, yawn, scared, happy, holdBall, kick, roam
}

public struct AnimationSpec: Codable, Equatable {
    public var folder: String
    public var fps: Double
    public var loop: Bool
    public var anchor: [Double]

    public init(folder: String, fps: Double, loop: Bool, anchor: [Double]) {
        self.folder = folder
        self.fps = fps
        self.loop = loop
        self.anchor = anchor
    }
}

public enum AnimationManifestError: Error, Equatable {
    case missingIdle
}

public struct AnimationManifest: Codable, Equatable {
    public var scale: Double?
    public var states: [String: AnimationSpec]

    public static func load(from url: URL) throws -> AnimationManifest {
        let m = try JSONDecoder().decode(AnimationManifest.self, from: Data(contentsOf: url))
        guard m.states[AnimState.idle.rawValue] != nil else { throw AnimationManifestError.missingIdle }
        return m
    }

    public func resolve(_ state: AnimState) -> (state: AnimState, spec: AnimationSpec)? {
        if let spec = states[state.rawValue] { return (state, spec) }
        if let idle = states[AnimState.idle.rawValue] { return (.idle, idle) }
        return nil
    }

    public var missingStates: [AnimState] {
        AnimState.allCases.filter { states[$0.rawValue] == nil }
    }
}

public func animState(for behavior: Behavior, mode: BodyMode, isMoving: Bool,
                      isRunning: Bool = false, carrying: Bool = false) -> AnimState {
    switch mode {
    case .held: return .scared
    case .airborne: return .fall
    case .roaming: return carrying ? .holdBall : .roam
    case .grounded: break
    }
    if isMoving {
        switch behavior {
        case .zoomies, .chaseCursor, .fetch, .greet: return .run
        default: return isRunning ? .run : .walk
        }
    }
    switch behavior {
    case .sit, .chaseCursor: return .sit
    case .sleep, .idleSleep: return .sleep
    case .beg: return .beg
    case .eat: return .eat
    case .bath: return .bath
    case .fetch: return .fetch
    case .greet, .wave: return .wave
    case .dangle: return .dangle
    case .fall: return .fall
    case .turnAround: return .back
    case .read: return .read
    case .readSleep: return .readSleep
    case .music: return .music
    case .watchTV: return .watch
    case .yawn: return .yawn
    case .playBallHome: return .kick
    default: return .idle
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "AnimationManifestTests|BrainTests|RoamingBodyTests"`
Expected: 23 tests PASS (6 + 11 + 6).
Run: `swift test`
Expected: 76 tests PASS (72 + 4).

- [ ] **Step 5: Keep the app layer compiling**

In `Sources/DesktopCorgi/Animation/PlaceholderBackend.swift`, replace the whole `switch state { ... }` in `play(_:)` with:
```swift
        switch state {
        case .walk, .run, .roam, .holdBall:
            let t = state == .walk ? 0.16 : 0.08
            figure.run(.repeatForever(.sequence([.moveBy(x: 0, y: 3, duration: t), .moveBy(x: 0, y: -3, duration: t)])))
        case .sleep, .readSleep:
            figure.yScale = 0.7
        case .sit, .read, .music, .watch:
            figure.yScale = 0.9
        case .beg:
            figure.zRotation = 0.25
        case .eat:
            figure.run(.repeatForever(.sequence([.rotate(toAngle: -0.15, duration: 0.2), .rotate(toAngle: 0, duration: 0.2)])))
        case .dangle:
            figure.run(.repeatForever(.sequence([.rotate(toAngle: 0.2, duration: 0.4), .rotate(toAngle: -0.2, duration: 0.4)])))
        case .scared:
            figure.run(.repeatForever(.sequence([.moveBy(x: 2, y: 0, duration: 0.04), .moveBy(x: -2, y: 0, duration: 0.04)])))
        case .wiggle:
            figure.run(.repeat(.sequence([.rotate(toAngle: 0.15, duration: 0.08), .rotate(toAngle: -0.15, duration: 0.08)]), count: 4))
        case .wave:
            figure.run(.repeatForever(.sequence([.rotate(toAngle: 0.12, duration: 0.15), .rotate(toAngle: -0.04, duration: 0.15)])))
        case .happy:
            figure.run(.repeat(.sequence([.moveBy(x: 0, y: 6, duration: 0.12), .moveBy(x: 0, y: -6, duration: 0.12)]), count: 3))
        case .back:
            figure.run(.sequence([.scaleX(by: 0.3, y: 1, duration: 0.25), .wait(forDuration: 1.5),
                                  .scaleX(by: 1 / 0.3, y: 1, duration: 0.25)]))
        case .yawn:
            figure.run(.sequence([.scaleY(to: 1.1, duration: 0.6), .scaleY(to: 0.8, duration: 1.4)]))
        case .kick:
            figure.run(.repeatForever(.sequence([.rotate(toAngle: -0.2, duration: 0.15), .rotate(toAngle: 0, duration: 0.25),
                                                 .wait(forDuration: 0.1)])))
        case .bath:
            figure.run(.repeatForever(.sequence([.moveBy(x: 3, y: 0, duration: 0.05), .moveBy(x: -3, y: 0, duration: 0.05)])))
        case .fall:
            figure.yScale = 1.05
        case .land:
            figure.yScale = 0.85
        case .idle, .fetch:
            break
        }
```

In `Sources/DesktopCorgi/PetController.swift`:
- In `beginBehavior(_:)`, replace `if needs.state.isAsleep != (b == .sleep) { needs.setAsleep(b == .sleep) }` with:
```swift
        if needs.state.isAsleep != b.countsAsSleep { needs.setAsleep(b.countsAsSleep) }
```
- In `wake()`, replace `if brain.current == .sleep { brain.finishCurrent() }` with:
```swift
        if brain.current.countsAsSleep { brain.finishCurrent() }
```
- In `tick()`, replace `if brain.current == .sleep && now - lastZzz > 2 {` with:
```swift
        if brain.current.countsAsSleep && now - lastZzz > 2 {
```
- In `pet()`, replace `if brain.current == .sleep {` with:
```swift
        if brain.current.countsAsSleep {
```
- In `updateAnimation(_:)`, replace `?? animState(for: brain.current, mode: body.mode, isMoving: body.isMoving)` with:
```swift
            ?? animState(for: brain.current, mode: body.mode, isMoving: body.isMoving, isRunning: body.isRunning)
```

- [ ] **Step 6: Run and verify (needs Mac)**

Run: `swift build && swift test && ./scripts/bundle.sh && open build/DesktopCorgi.app`
Expected: 76 tests pass. Dragging the placeholder corgi shows the fast shiver (`scared`) instead of the swing. The greeting (Task 16, away more than 1 hour) ends in the wave rock instead of the wiggle once the corgi reaches the cursor. Everything else behaves as before.
On Linux: `swift build && swift test` still pass (76 tests).

- [ ] **Step 7: Commit**

```bash
git add Sources/CorgiCore Sources/DesktopCorgi Tests/CorgiCoreTests
git commit -m "feat: companion behaviors and animation states"
```

### Task 20: Brain weights for home, idle activities, boredom, and reading

**Files:**
- Modify: `Sources/CorgiCore/Brain.swift`
- Test: `Tests/CorgiCoreTests/BrainTests.swift`

**Interfaces:**
- Consumes: new `Behavior` cases (Task 19).
- Produces:
  - `Behavior.autonomous` adds `goHome, read, music, watchTV, wave, turnAround, playBallHome, ballChase`. (`readSleep`, `yawn`, `idleSleep`, `chaseMe` are never picked on their own.)
  - `BrainConfig.durations` adds goHome 30, read 20-60, readSleep 30-90, music 20-60, watchTV 30-90, wave 2, turnAround 3-5, playBallHome 8-15, ballChase 30 (seconds). `BrainConfig.readDozeAfter = 15`, `readDozeChance = 0.3`.
  - `BrainContext.init(needs:lowThreshold:canHop:atHome: Bool = false, secondsAwayFromHome: TimeInterval = 0, bored: Bool = false)` with matching `var`s. Defaults keep every existing call site compiling.
  - Weights: base read 1, music 1, watchTV 1, wave 0.5, turnAround 0.5, playBallHome 0.5; `goHome` = 0 at home, else `min(8, secondsAway / 60)`; `ballChase` = 6 when bored, else 0. At home: read/music/watchTV/playBallHome x3, wave/turnAround x2, walk/zoomies/hopToWindow x0.5. Low energy zeroes music, wave, turnAround, playBallHome, ballChase (read stays, it turns into readSleep).
  - `read` becomes `readSleep` right away when energy is low (both when picked and while reading), else one 30% roll after 15s of reading.

- [ ] **Step 1: Write the failing tests**

In `Tests/CorgiCoreTests/BrainTests.swift`, in `testChoiceFollowsWeightsOverManyPicks` change the comment on the `sleeps` assertion to `// expected share is about 49%` (the two new weights that survive low energy, read 1 and watchTV 1, lower the sleep share from 10.5/19.5 to 10.5/21.5; the assertion `> 200` stays). Then add before the class's closing brace:
```swift
    func homeCtx(atHome: Bool, away: TimeInterval = 0, bored: Bool = false,
                 energy: Double = 70) -> BrainContext {
        var c = ctx(energy: energy)
        c.atHome = atHome
        c.secondsAwayFromHome = away
        c.bored = bored
        return c
    }

    func testIdleActivitiesWeightedHigherAtHome() {
        let away = brain().weights(homeCtx(atHome: false))
        let home = brain().weights(homeCtx(atHome: true))
        for b in [Behavior.read, .music, .watchTV, .playBallHome] {
            XCTAssertEqual(home[b]!, away[b]! * 3, accuracy: 0.001, "\(b)")
        }
        for b in [Behavior.wave, .turnAround] { XCTAssertEqual(home[b]!, away[b]! * 2, accuracy: 0.001, "\(b)") }
        for b in [Behavior.walk, .zoomies, .hopToWindow] { XCTAssertEqual(home[b]!, away[b]! * 0.5, accuracy: 0.001, "\(b)") }
    }

    func testGoHomeGrowsWithTimeAwayAndCapsAtEight() {
        XCTAssertEqual(brain().weights(homeCtx(atHome: false, away: 0))[.goHome], 0)
        XCTAssertEqual(brain().weights(homeCtx(atHome: false, away: 120))[.goHome]!, 2, accuracy: 0.001)
        XCTAssertEqual(brain().weights(homeCtx(atHome: false, away: 3600))[.goHome], 8)
        XCTAssertEqual(brain().weights(homeCtx(atHome: true, away: 3600))[.goHome], 0)
    }

    func testBoredomAddsBallChaseUnlessTired() {
        XCTAssertEqual(brain().weights(homeCtx(atHome: true))[.ballChase], 0)
        XCTAssertEqual(brain().weights(homeCtx(atHome: true, bored: true))[.ballChase], 6)
        XCTAssertEqual(brain().weights(homeCtx(atHome: true, bored: true, energy: 10))[.ballChase], 0)
    }

    func testReadTurnsIntoReadSleepRightAwayWhenTired() {
        let b = brain()
        b.interrupt(with: .read, duration: 40)
        XCTAssertEqual(b.update(dt: 0.1, ctx(energy: 10)), .readSleep)
        XCTAssertTrue(b.current.countsAsSleep)
    }

    func testReadDozesOnceAfterFifteenSecondsAboutThirtyPercent() {
        var dozed = 0
        for seed in UInt64(1)...200 {
            let b = brain(seed: seed)
            b.interrupt(with: .read, duration: 60)
            XCTAssertNil(b.update(dt: 14.9, ctx()))
            if b.update(dt: 0.2, ctx()) == .readSleep {
                dozed += 1
            } else {
                XCTAssertNil(b.update(dt: 10, ctx()))   // the roll happens only once
                XCTAssertEqual(b.current, .read)
            }
        }
        XCTAssertTrue((40...80).contains(dozed), "\(dozed)")   // expected about 60
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter BrainTests`
Expected: compile error, `value of type 'BrainContext' has no member 'atHome'`.

- [ ] **Step 3: Implement**

Replace `Sources/CorgiCore/Brain.swift` with:
```swift
import Foundation

public enum Behavior: String, CaseIterable {
    case idle, walk, sit, sleep, zoomies, chaseCursor, hopToWindow, beg
    case eat, fetch, bath, dangle, fall, greet
    case goHome, read, readSleep, music, watchTV, wave, turnAround, playBallHome
    case yawn, idleSleep, chaseMe, ballChase

    /// Behaviors the brain picks on its own. The rest only happen through `interrupt`.
    public static let autonomous: [Behavior] = [
        .idle, .walk, .sit, .sleep, .zoomies, .chaseCursor, .hopToWindow, .beg,
        .goHome, .read, .music, .watchTV, .wave, .turnAround, .playBallHome, .ballChase,
    ]

    /// Behaviors during which energy refills at the asleep rate.
    public var countsAsSleep: Bool { self == .sleep || self == .readSleep || self == .idleSleep }
}

public struct BrainConfig {
    public var durations: [Behavior: ClosedRange<Double>] = [
        .idle: 3...8, .walk: 3...8, .sit: 4...10, .sleep: 60...180,
        .zoomies: 4...8, .chaseCursor: 5...5, .hopToWindow: 6...8, .beg: 6...10,
        .goHome: 30...30, .read: 20...60, .readSleep: 30...90, .music: 20...60, .watchTV: 30...90,
        .wave: 2...2, .turnAround: 3...5, .playBallHome: 8...15, .ballChase: 30...30,
    ]
    public var wakeEnergy = 95.0
    /// Seconds of reading before the one-time doze roll, and the chance it dozes off.
    public var readDozeAfter = 15.0
    public var readDozeChance = 0.3

    public init() {}
}

public struct BrainContext {
    public var needs: NeedsState
    public var lowThreshold: Double
    public var canHop: Bool
    public var atHome: Bool
    public var secondsAwayFromHome: TimeInterval
    public var bored: Bool

    public init(needs: NeedsState, lowThreshold: Double, canHop: Bool,
                atHome: Bool = false, secondsAwayFromHome: TimeInterval = 0, bored: Bool = false) {
        self.needs = needs
        self.lowThreshold = lowThreshold
        self.canHop = canHop
        self.atHome = atHome
        self.secondsAwayFromHome = secondsAwayFromHome
        self.bored = bored
    }
}

public final class Brain {
    public let config: BrainConfig
    private var rng: any RandomNumberGenerator
    public private(set) var current: Behavior = .idle
    public private(set) var remaining: TimeInterval = 0
    private var readElapsed: TimeInterval = 0
    private var readRolled = false

    public init(config: BrainConfig = .init(), rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.config = config
        self.rng = rng
    }

    private func random() -> Double {
        Double(rng.next() >> 11) / Double(1 << 53)
    }

    public func weights(_ ctx: BrainContext) -> [Behavior: Double] {
        let n = ctx.needs
        var w: [Behavior: Double] = [
            .idle: 3, .walk: 4, .sit: 2, .sleep: 0.5,
            .zoomies: 0.5, .chaseCursor: 0.5, .hopToWindow: 1, .beg: 0,
            .read: 1, .music: 1, .watchTV: 1, .wave: 0.5, .turnAround: 0.5, .playBallHome: 0.5,
            .goHome: ctx.atHome ? 0 : min(8, max(0, ctx.secondsAwayFromHome) / 60),
            .ballChase: ctx.bored ? 6 : 0,
        ]
        if ctx.atHome {
            for b in [Behavior.read, .music, .watchTV, .playBallHome] { w[b]! *= 3 }
            for b in [Behavior.wave, .turnAround] { w[b]! *= 2 }
            for b in [Behavior.walk, .zoomies, .hopToWindow] { w[b]! *= 0.5 }
        }
        if n.happiness > 70 && n.energy > 60 {
            w[.zoomies]! += 1.5
            w[.chaseCursor]! += 1.5
            w[.hopToWindow]! += 1.5
        }
        if n.happiness < ctx.lowThreshold {
            w[.zoomies] = 0
            w[.walk]! *= 0.5
            w[.sit]! += 2
        }
        if n.hunger < ctx.lowThreshold {
            w[.beg]! += 6
        }
        if n.energy < ctx.lowThreshold {
            w[.sleep]! += 10
            w[.zoomies] = 0
            w[.chaseCursor] = 0
            w[.hopToWindow] = 0
            w[.music] = 0
            w[.wave] = 0
            w[.turnAround] = 0
            w[.playBallHome] = 0
            w[.ballChase] = 0
        }
        if n.energy >= config.wakeEnergy { w[.sleep] = 0 }
        if !ctx.canHop { w[.hopToWindow] = 0 }
        return w
    }

    public func choose(_ ctx: BrainContext) -> Behavior {
        let w = weights(ctx)
        let total = Behavior.autonomous.reduce(0) { $0 + (w[$1] ?? 0) }
        var roll = random() * total
        for b in Behavior.autonomous {
            roll -= w[b] ?? 0
            if roll < 0 { return b }
        }
        return .idle
    }

    @discardableResult
    public func update(dt: TimeInterval, _ ctx: BrainContext) -> Behavior? {
        remaining -= dt
        if current == .read {
            readElapsed += dt
            if ctx.needs.energy < ctx.lowThreshold || (!readRolled && readElapsed >= config.readDozeAfter) {
                let doze = ctx.needs.energy < ctx.lowThreshold || random() < config.readDozeChance
                readRolled = true
                if doze { return start(.readSleep) }
            }
        }
        guard remaining <= 0 else { return nil }
        if current == .sleep && ctx.needs.energy < config.wakeEnergy {
            remaining = 10
            return nil
        }
        let pick = choose(ctx)
        return start(pick == .read && ctx.needs.energy < ctx.lowThreshold ? .readSleep : pick)
    }

    private func start(_ next: Behavior) -> Behavior {
        current = next
        readElapsed = 0
        readRolled = false
        let range = config.durations[next] ?? 3...8
        remaining = range.lowerBound + random() * (range.upperBound - range.lowerBound)
        return next
    }

    public func interrupt(with behavior: Behavior, duration: TimeInterval) {
        current = behavior
        remaining = duration
        readElapsed = 0
        readRolled = false
    }

    public func finishCurrent() {
        remaining = 0
        if current.countsAsSleep { current = .idle }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter BrainTests`
Expected: 16 tests PASS.
Run: `swift test`
Expected: 81 tests PASS (76 + 5).

The app still passes no home or boredom info (`BrainContext` defaults), so `goHome` and `ballChase` have weight 0 there until Tasks 24-25. The new idle activities can be picked now and just stand still with their animation.

- [ ] **Step 5: Commit**

```bash
git add Sources/CorgiCore/Brain.swift Tests/CorgiCoreTests/BrainTests.swift
git commit -m "feat: brain weights for home, idle activities, boredom"
```

### Task 21: Home spot, goHome steering, greeting lines

**Files:**
- Create: `Sources/CorgiCore/Home.swift`
- Modify: `Sources/CorgiCore/BehaviorExecutor.swift`
- Test: `Tests/CorgiCoreTests/HomeTests.swift`, `Tests/CorgiCoreTests/BehaviorExecutorTests.swift`

**Interfaces:**
- Consumes: `Clock` (Task 1), `Body.leap`/`jump`/`isRunning`/`stopRoaming` (Tasks 6, 18, 19), `World.segment(under:)`.
- Produces:
  - `struct HomeConfig { var insetFromRight: CGFloat = 80; var radius: CGFloat = 40 }`
  - `final class HomeTracker { init(clock: Clock, config: HomeConfig = .init()); private(set) var spot: CGPoint?; func setScreens(_ visibleFrames: [CGRect], mainIndex: Int); func isHome(_ p: CGPoint) -> Bool; func observe(_ p: CGPoint); var secondsAway: TimeInterval }`
  - Home spot = `(visibleFrame.maxX - 80, visibleFrame.minY)` of `visibleFrames[mainIndex]`, or of `visibleFrames[0]` when `mainIndex` is out of range (monitor unplugged), `nil` with no screens.
  - `enum Greeting { static let missedYouAfter: TimeInterval = 3600; static func lines(awaySeconds: TimeInterval) -> [String] }`
  - `BehaviorExecutor.home: CGPoint?`. `goHome` waits until grounded, then: same floor as home, walk (run if more than 300pt away) and finish within 4pt; home higher and in jump range, jump; otherwise walk to the edge facing home (nearer edge if home is below this floor), leap, and re-plan after landing.
  - `BehaviorExecutor.begin` ends roaming (`body.stopRoaming()`) for every behavior except `chaseMe` and `ballChase`.
  - `greet` no longer walks to the cursor. It stands still and faces it.

- [ ] **Step 1: Write the failing tests**

`Tests/CorgiCoreTests/HomeTests.swift`:
```swift
import XCTest
@testable import CorgiCore

final class HomeTests: XCTestCase {
    let screen1 = CGRect(x: 1440, y: 0, width: 1920, height: 1000)

    func testHomeIsBottomRightOfMainVisibleFrame() {
        let home = HomeTracker(clock: FakeClock())
        home.setScreens([screen0, screen1], mainIndex: 1)
        XCTAssertEqual(home.spot, CGPoint(x: 3360 - 80, y: 0))
        home.setScreens([CGRect(x: 0, y: 70, width: 1440, height: 805)], mainIndex: 0)  // Dock at the bottom
        XCTAssertEqual(home.spot, CGPoint(x: 1360, y: 70))
    }

    func testHomeMovesWhenItsMonitorIsUnplugged() {
        let home = HomeTracker(clock: FakeClock())
        home.setScreens([screen0, screen1], mainIndex: 1)
        home.setScreens([screen0], mainIndex: 1)          // main index now out of range
        XCTAssertEqual(home.spot, CGPoint(x: 1360, y: 0))
        home.setScreens([], mainIndex: 0)
        XCTAssertNil(home.spot)
        XCTAssertFalse(home.isHome(CGPoint(x: 1360, y: 0)))
    }

    func testIsHomeUsesRadiusAndSameFloor() {
        let home = HomeTracker(clock: FakeClock())
        home.setScreens([screen0], mainIndex: 0)
        XCTAssertTrue(home.isHome(CGPoint(x: 1330, y: 0)))
        XCTAssertFalse(home.isHome(CGPoint(x: 1300, y: 0)))
        XCTAssertFalse(home.isHome(CGPoint(x: 1360, y: 300)))   // on a window above home
    }

    func testTimeAwayCountsAndResetsAtHome() {
        let clock = FakeClock()
        let home = HomeTracker(clock: clock)
        home.setScreens([screen0], mainIndex: 0)
        home.observe(CGPoint(x: 200, y: 0))
        clock.advance(90)
        home.observe(CGPoint(x: 400, y: 0))
        XCTAssertEqual(home.secondsAway, 90, accuracy: 0.001)
        home.observe(CGPoint(x: 1360, y: 0))
        XCTAssertEqual(home.secondsAway, 0)
    }

    func testTimeAwayNeverNegativeWhenClockGoesBack() {
        let clock = FakeClock()
        let home = HomeTracker(clock: clock)
        home.setScreens([screen0], mainIndex: 0)
        home.observe(CGPoint(x: 200, y: 0))
        clock.advance(-600)
        XCTAssertEqual(home.secondsAway, 0)
    }

    func testGreetingLines() {
        XCTAssertEqual(Greeting.lines(awaySeconds: 0), ["Hi!"])
        XCTAssertEqual(Greeting.lines(awaySeconds: 3601), ["Hi!", "Missed you!"])
    }
}
```

In `Tests/CorgiCoreTests/BehaviorExecutorTests.swift`, add before the class's closing brace:
```swift
    func homeExecutor() -> BehaviorExecutor {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        ex.home = CGPoint(x: 1360, y: 0)
        return ex
    }

    func testGoHomeRunsWhenFarAndArrives() {
        let ex = homeExecutor()
        let body = groundedBody(x: 100)
        ex.begin(.goHome, body: body, world: world, cursor: .zero)
        _ = ex.step(.goHome, body: body, world: world, cursor: .zero)
        XCTAssertTrue(body.isRunning)
        XCTAssertTrue(run(ex, .goHome, body, seconds: 10))
        XCTAssertEqual(body.position.x, 1360, accuracy: 4)
    }

    func testGoHomeFromPerchLeapsDownThenWalksHome() {
        let ex = homeExecutor()
        let body = groundedBody(x: 800, y: 300)        // on window 1 (600...1000)
        ex.begin(.goHome, body: body, world: world, cursor: .zero)
        XCTAssertTrue(run(ex, .goHome, body, seconds: 15))
        XCTAssertEqual(body.standingOn?.kind, .ground(screen: 0))
        XCTAssertEqual(body.position.x, 1360, accuracy: 4)
    }

    func testGoHomeFromOtherMonitorCrossesOver() {
        world.setScreens([screen0, CGRect(x: 1440, y: 0, width: 1920, height: 1000)])
        let ex = homeExecutor()
        let body = groundedBody(x: 2400)
        ex.begin(.goHome, body: body, world: world, cursor: .zero)
        XCTAssertTrue(run(ex, .goHome, body, seconds: 15))
        XCTAssertEqual(body.standingOn?.kind, .ground(screen: 0))
        XCTAssertEqual(body.position.x, 1360, accuracy: 4)
    }

    func testGoHomeAfterDropWaitsForLanding() {
        let ex = homeExecutor()
        let body = Body(position: CGPoint(x: 500, y: 600))   // just released, still in the air
        ex.begin(.goHome, body: body, world: world, cursor: .zero)
        XCTAssertFalse(ex.step(.goHome, body: body, world: world, cursor: .zero))
        XCTAssertTrue(run(ex, .goHome, body, seconds: 12))
        XCTAssertEqual(body.position.x, 1360, accuracy: 4)
    }

    func testGreetStandsAndFacesCursor() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        let body = groundedBody(x: 500)
        ex.begin(.greet, body: body, world: world, cursor: CGPoint(x: 100, y: 400))
        XCTAssertFalse(run(ex, .greet, body, cursor: CGPoint(x: 100, y: 400), seconds: 1))
        XCTAssertEqual(body.position.x, 500)
        XCTAssertFalse(body.facingRight)
    }

    func testNonRoamingBehaviorEndsRoaming() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        let body = Body(position: CGPoint(x: 300, y: 500))
        body.startRoaming()
        ex.begin(.chaseMe, body: body, world: world, cursor: .zero)
        XCTAssertEqual(body.mode, .roaming)
        ex.begin(.idle, body: body, world: world, cursor: .zero)
        XCTAssertEqual(body.mode, .airborne)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "HomeTests|BehaviorExecutorTests"`
Expected: compile errors, `cannot find 'HomeTracker' in scope`, `value of type 'BehaviorExecutor' has no member 'home'`.

- [ ] **Step 3: Implement**

`Sources/CorgiCore/Home.swift`:
```swift
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

public struct HomeConfig {
    /// Home sits this far left of the main screen's right edge.
    public var insetFromRight: CGFloat = 80
    /// Within this many points of the spot (on the same floor) counts as home.
    public var radius: CGFloat = 40

    public init() {}
}

/// Where home is and how long the corgi has been away from it.
public final class HomeTracker {
    public let config: HomeConfig
    let clock: Clock
    public private(set) var spot: CGPoint?
    private var awaySince: Date?

    public init(clock: Clock, config: HomeConfig = .init()) {
        self.clock = clock
        self.config = config
    }

    /// `visibleFrames` in the same order as `World.screens`; `mainIndex` is the main screen.
    /// Falls back to the first screen when the main one is gone.
    public func setScreens(_ visibleFrames: [CGRect], mainIndex: Int) {
        guard !visibleFrames.isEmpty else {
            spot = nil
            return
        }
        let vf = visibleFrames.indices.contains(mainIndex) ? visibleFrames[mainIndex] : visibleFrames[0]
        spot = CGPoint(x: vf.maxX - config.insetFromRight, y: vf.minY)
    }

    public func isHome(_ p: CGPoint) -> Bool {
        guard let h = spot else { return false }
        return abs(p.x - h.x) <= config.radius && abs(p.y - h.y) <= 2
    }

    /// Call every tick with the corgi's feet.
    public func observe(_ p: CGPoint) {
        if isHome(p) {
            awaySince = nil
        } else if awaySince == nil {
            awaySince = clock.now
        }
    }

    public var secondsAway: TimeInterval {
        guard let since = awaySince else { return 0 }
        return max(0, clock.now.timeIntervalSince(since))
    }
}

public enum Greeting {
    public static let missedYouAfter: TimeInterval = 3600

    /// Speech bubbles shown at launch, in order.
    public static func lines(awaySeconds: TimeInterval) -> [String] {
        awaySeconds > missedYouAfter ? ["Hi!", "Missed you!"] : ["Hi!"]
    }
}
```

Replace `Sources/CorgiCore/BehaviorExecutor.swift` with:
```swift
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

public final class BehaviorExecutor {
    public var targetX: CGFloat?
    public var speedScale: CGFloat = 1
    /// Home spot for `goHome`. Set by the caller whenever screens change.
    public var home: CGPoint?
    private var rng: any RandomNumberGenerator
    private var zoomDirection: CGFloat = 1
    private var hopStarted = false
    private var hopDownDirection: CGFloat?
    private var homePlanned = false
    private var homeLeapDirection: CGFloat?

    public init(rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.rng = rng
    }

    private func random() -> CGFloat {
        CGFloat(Double(rng.next() >> 11) / Double(1 << 53))
    }

    public func begin(_ b: Behavior, body: Body, world: World, cursor: CGPoint) {
        targetX = nil
        hopStarted = false
        hopDownDirection = nil
        homePlanned = false
        homeLeapDirection = nil
        if body.mode == .roaming && b != .chaseMe && b != .ballChase { body.stopRoaming() }
        body.stop()
        let segment = body.standingOn ?? world.segment(under: body.position)
        switch b {
        case .walk:
            if let s = segment {
                let lo = s.minX + 20, hi = max(lo, s.maxX - 20)
                targetX = lo + random() * (hi - lo)
            }
        case .greet:
            body.face(right: cursor.x >= body.position.x)
        case .zoomies:
            zoomDirection = random() < 0.5 ? -1 : 1
        case .hopToWindow:
            let options = world.reachableSegments(from: body.position,
                                                  maxJumpUp: body.config.maxJumpUp,
                                                  maxJumpAcross: body.config.maxJumpAcross)
                .prefix(3)
            guard !options.isEmpty else { return }
            let pick = options[options.startIndex + Int(random() * CGFloat(options.count)) % options.count]
            if let s = segment, pick.y < s.y {
                // Going down: walk to the edge on the side where the lower segment continues, then leap.
                let sides: [(dir: CGFloat, edge: CGFloat, landX: CGFloat)] = [(-1, s.minX, s.minX - 40), (1, s.maxX, s.maxX + 40)]
                guard let side = sides
                    .filter({ pick.contains(x: $0.landX) })
                    .min(by: { abs($0.edge - body.position.x) < abs($1.edge - body.position.x) })
                else { return }
                hopDownDirection = side.dir
                targetX = side.edge
            } else {
                let x = min(max(body.position.x, pick.minX + 30), pick.maxX - 30)
                body.jump(to: CGPoint(x: x, y: pick.y))
            }
            hopStarted = true
        default:
            break
        }
    }

    public func step(_ b: Behavior, body: Body, world: World, cursor: CGPoint) -> Bool {
        if b == .hopToWindow {
            guard hopStarted else { return true }
            if let dir = hopDownDirection, body.mode == .grounded, let target = targetX {
                if abs(target - body.position.x) < 4 {
                    body.leap(direction: dir)
                    hopDownDirection = nil
                } else {
                    body.walk(direction: target - body.position.x, speed: body.config.walkSpeed * 1.5)
                }
            }
            return false
        }
        guard body.mode == .grounded else { return false }
        switch b {
        case .goHome:
            return stepHome(body: body, world: world)
        case .walk, .fetch:
            guard let target = targetX else { return b == .walk }
            let dx = target - body.position.x
            if abs(dx) < 4 {
                body.stop()
                return true
            }
            let speed = b == .walk ? body.config.walkSpeed * speedScale : body.config.runSpeed
            body.walk(direction: dx, speed: speed)
        case .zoomies:
            body.walk(direction: zoomDirection, speed: body.config.runSpeed * 1.2)
        case .chaseCursor:
            let segment = body.standingOn ?? world.segment(under: body.position)
            let dx = cursor.x - body.position.x
            if let s = segment, s.contains(x: cursor.x), abs(dx) > 30 {
                body.walk(direction: dx, speed: body.config.runSpeed)
            } else {
                body.stop()
                body.face(right: dx >= 0)
            }
        default:
            body.stop()
        }
        return false
    }

    public func handle(_ event: BodyEvent, behavior: Behavior, body: Body) -> Bool {
        switch (behavior, event) {
        case (.zoomies, .hitEdge):
            zoomDirection = -zoomDirection
            return false
        case (.walk, .hitEdge):
            return true
        case (.hopToWindow, .landed):
            return true
        case (.goHome, .landed):
            homePlanned = false
            return false
        case (.goHome, .hitEdge):
            if let dir = homeLeapDirection {
                body.leap(direction: dir)
                homeLeapDirection = nil
            }
            return false
        case (.hopToWindow, .hitEdge):
            if let dir = hopDownDirection {
                body.leap(direction: dir)
                hopDownDirection = nil
            }
            return false
        default:
            return false
        }
    }

    /// Walks (runs if far) to `home`. From another floor it leaps off the edge facing home,
    /// or jumps up if home is higher and in range, then re-plans after landing.
    private func stepHome(body: Body, world: World) -> Bool {
        guard let home else { return true }
        guard let s = body.standingOn ?? world.segment(under: body.position) else { return false }
        if s.contains(x: home.x) && abs(s.y - home.y) <= 2 {
            let dx = home.x - body.position.x
            if abs(dx) < 4 {
                body.stop()
                return true
            }
            body.walk(direction: dx, speed: abs(dx) > 300 ? body.config.runSpeed : body.config.walkSpeed)
            return false
        }
        if !homePlanned {
            homePlanned = true
            if home.y > s.y + 2 {
                guard let hs = world.segment(under: home),
                      home.y - s.y <= body.config.maxJumpUp,
                      abs(hs.clampX(body.position.x) - body.position.x) <= body.config.maxJumpAcross
                else { return true }
                body.jump(to: CGPoint(x: min(max(body.position.x, hs.minX + 30), hs.maxX - 30), y: home.y))
                return false
            }
            if home.x < s.minX {
                homeLeapDirection = -1
            } else if home.x > s.maxX {
                homeLeapDirection = 1
            } else {
                homeLeapDirection = body.position.x - s.minX <= s.maxX - body.position.x ? -1 : 1
            }
        }
        if let dir = homeLeapDirection {
            let edge = dir < 0 ? s.minX : s.maxX
            if abs(edge - body.position.x) < 4 {
                body.leap(direction: dir)
                homeLeapDirection = nil
            } else {
                body.walk(direction: edge - body.position.x, speed: body.config.runSpeed)
            }
        }
        return false
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "HomeTests|BehaviorExecutorTests"`
Expected: 21 tests PASS (6 + 15).
Run: `swift test`
Expected: 93 tests PASS (81 + 12).

- [ ] **Step 5: Commit**

```bash
git add Sources/CorgiCore/Home.swift Sources/CorgiCore/BehaviorExecutor.swift Tests/CorgiCoreTests/HomeTests.swift Tests/CorgiCoreTests/BehaviorExecutorTests.swift
git commit -m "feat: home spot and goHome steering"
```

### Task 22: Rest monitor (idle sleep, full screen), hover pet, boredom, catch pet

**Files:**
- Create: `Sources/CorgiCore/Rest.swift`
- Create: `Sources/CorgiCore/Attention.swift`
- Modify: `Sources/CorgiCore/Needs.swift`
- Test: `Tests/CorgiCoreTests/RestTests.swift` (classes `RestTests` and `AttentionTests`)

**Interfaces:**
- Consumes: `Clock`, `NeedsState`, `NeedsEngine` (Tasks 1-2).
- Produces:
  - `func isFullScreen(frontWindow: CGRect?, screenFrames: [CGRect], tolerance: CGFloat = 1) -> Bool` (compare against full screen frames, not visible frames)
  - `enum RestEvent: Equatable { case startYawn, fallAsleep, wake }`
  - `final class RestMonitor { enum Phase { awake, yawning, asleep }; var idleThreshold = 90.0; var yawnDuration = 2.0; private(set) var phase: Phase; func update(dt: TimeInterval, idleSeconds: TimeInterval, fullScreen: Bool, busy: Bool) -> RestEvent? }`. Rest is wanted when `!busy && (idleSeconds >= 90 || fullScreen)`. Awake + idle: `.startYawn`, then `.fallAsleep` after 2s. Awake + full screen: `.fallAsleep` at once. Any phase that stops wanting rest: `.wake`.
  - `final class HoverPet { var delay = 0.4; var repeatEvery = 1.5; func update(dt: TimeInterval, hovering: Bool, blocked: Bool) -> Bool }`. Blocked or not hovering resets the timer.
  - `final class BoredomTimer { init(clock: Clock); var threshold = 600.0; var minHappiness = 50.0; var minEnergy = 40.0; func noteInteraction(); var secondsSinceInteraction: TimeInterval; func isBored(_ needs: NeedsState) -> Bool }`
  - `NeedsConfig.catchAmount = 10.0`, `NeedsEngine.catchPet() -> Bool` (shares the pet rate limit).

- [ ] **Step 1: Write the failing tests**

`Tests/CorgiCoreTests/RestTests.swift`:
```swift
import XCTest
@testable import CorgiCore

final class RestTests: XCTestCase {
    let full0 = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let full1 = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    func testFullScreenDetection() {
        XCTAssertTrue(isFullScreen(frontWindow: full1, screenFrames: [full0, full1]))
        XCTAssertTrue(isFullScreen(frontWindow: CGRect(x: 0.5, y: 0, width: 1440, height: 900), screenFrames: [full0]))
        XCTAssertFalse(isFullScreen(frontWindow: CGRect(x: 0, y: 0, width: 1440, height: 875), screenFrames: [full0]))
        XCTAssertFalse(isFullScreen(frontWindow: nil, screenFrames: [full0]))
    }

    func testIdleYawnsThenSleepsAndWakesOnInput() {
        let r = RestMonitor()
        XCTAssertNil(r.update(dt: 0.1, idleSeconds: 89, fullScreen: false, busy: false))
        XCTAssertEqual(r.update(dt: 0.1, idleSeconds: 90, fullScreen: false, busy: false), .startYawn)
        XCTAssertNil(r.update(dt: 1.5, idleSeconds: 91.5, fullScreen: false, busy: false))
        XCTAssertEqual(r.update(dt: 0.6, idleSeconds: 92.1, fullScreen: false, busy: false), .fallAsleep)
        XCTAssertNil(r.update(dt: 60, idleSeconds: 152, fullScreen: false, busy: false))
        XCTAssertEqual(r.phase, .asleep)
        XCTAssertEqual(r.update(dt: 0.1, idleSeconds: 0, fullScreen: false, busy: false), .wake)
        XCTAssertEqual(r.phase, .awake)
    }

    func testFullScreenSleepsRightAwayAndWakesWhenItEnds() {
        let r = RestMonitor()
        XCTAssertEqual(r.update(dt: 0.1, idleSeconds: 0, fullScreen: true, busy: false), .fallAsleep)
        XCTAssertNil(r.update(dt: 0.1, idleSeconds: 0, fullScreen: true, busy: false))
        XCTAssertEqual(r.update(dt: 0.1, idleSeconds: 0, fullScreen: false, busy: false), .wake)
    }

    func testDraggingBlocksRestAndCancelsAYawn() {
        let r = RestMonitor()
        XCTAssertNil(r.update(dt: 0.1, idleSeconds: 200, fullScreen: false, busy: true))
        XCTAssertEqual(r.update(dt: 0.1, idleSeconds: 200, fullScreen: false, busy: false), .startYawn)
        XCTAssertEqual(r.update(dt: 0.1, idleSeconds: 200, fullScreen: false, busy: true), .wake)
        XCTAssertEqual(r.phase, .awake)
    }

    func testFullScreenDuringChaseMeWaitsUntilChaseEnds() {
        let r = RestMonitor()
        for _ in 0..<10 { XCTAssertNil(r.update(dt: 0.1, idleSeconds: 0, fullScreen: true, busy: true)) }
        XCTAssertNil(r.update(dt: 0.1, idleSeconds: 0, fullScreen: false, busy: true))
        XCTAssertNil(r.update(dt: 0.1, idleSeconds: 0, fullScreen: true, busy: true))
        XCTAssertEqual(r.update(dt: 0.1, idleSeconds: 0, fullScreen: true, busy: false), .fallAsleep)
        XCTAssertEqual(r.update(dt: 0.1, idleSeconds: 0, fullScreen: true, busy: true), .wake)
    }
}

final class AttentionTests: XCTestCase {
    func testHoverPetsAfterDelayThenRepeats() {
        let h = HoverPet()
        var pets: [Int] = []
        for i in 1...40 where h.update(dt: 0.1, hovering: true, blocked: false) { pets.append(i) }
        XCTAssertEqual(pets, [4, 19, 34])     // 0.4s, 1.9s, 3.4s
        XCTAssertFalse(h.update(dt: 0.1, hovering: false, blocked: false))
        XCTAssertFalse(h.update(dt: 0.3, hovering: true, blocked: false))
        XCTAssertTrue(h.update(dt: 0.1, hovering: true, blocked: false))
    }

    func testHoverWhileAsleepOrHeldNeverPets() {
        let h = HoverPet()
        for _ in 0..<50 { XCTAssertFalse(h.update(dt: 0.1, hovering: true, blocked: true)) }
        XCTAssertFalse(h.update(dt: 0.3, hovering: true, blocked: false))   // timer starts over
        XCTAssertTrue(h.update(dt: 0.1, hovering: true, blocked: false))
    }

    func testBoredAfterTenMinutesOnlyWhenHappyAndRested() {
        let clock = FakeClock()
        let b = BoredomTimer(clock: clock)
        var s = NeedsState.fresh(at: clock.now)
        clock.advance(599)
        XCTAssertFalse(b.isBored(s))
        clock.advance(1)
        XCTAssertTrue(b.isBored(s))
        s.happiness = 50
        XCTAssertFalse(b.isBored(s))
        s.happiness = 70
        s.energy = 40
        XCTAssertFalse(b.isBored(s))
    }

    func testInteractionResetsBoredomAndClockGoingBackIsSafe() {
        let clock = FakeClock()
        let b = BoredomTimer(clock: clock)
        let s = NeedsState.fresh(at: clock.now)
        clock.advance(700)
        b.noteInteraction()
        XCTAssertFalse(b.isBored(s))
        clock.advance(-5000)
        XCTAssertEqual(b.secondsSinceInteraction, 0)
        XCTAssertFalse(b.isBored(s))
    }

    func testCatchPetGivesTenAndSharesPetLimit() {
        let clock = FakeClock()
        var s = NeedsState.fresh(at: clock.now)
        s.happiness = 0
        let e = NeedsEngine(state: s, clock: clock)
        XCTAssertTrue(e.catchPet())
        XCTAssertEqual(e.state.happiness, 10, accuracy: 0.01)
        for _ in 0..<9 { XCTAssertTrue(e.pet()) }
        XCTAssertFalse(e.catchPet())
        XCTAssertFalse(e.pet())
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "RestTests|AttentionTests"`
Expected: compile errors, `cannot find 'isFullScreen' in scope`, `cannot find 'RestMonitor' in scope`, `cannot find 'HoverPet' in scope`.

- [ ] **Step 3: Implement**

`Sources/CorgiCore/Rest.swift`:
```swift
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// True when the frontmost window covers a whole screen (its full frame, not the visible frame).
public func isFullScreen(frontWindow: CGRect?, screenFrames: [CGRect], tolerance: CGFloat = 1) -> Bool {
    guard let w = frontWindow else { return false }
    return screenFrames.contains {
        abs($0.minX - w.minX) <= tolerance && abs($0.minY - w.minY) <= tolerance
            && abs($0.width - w.width) <= tolerance && abs($0.height - w.height) <= tolerance
    }
}

public enum RestEvent: Equatable { case startYawn, fallAsleep, wake }

/// Decides when the corgi rests because the user is away (yawn, then sleep) or a full screen
/// app is in front (sleep right away). Separate from energy-based napping.
public final class RestMonitor {
    public enum Phase: Equatable { case awake, yawning, asleep }

    public var idleThreshold: TimeInterval = 90
    public var yawnDuration: TimeInterval = 2
    public private(set) var phase: Phase = .awake
    private var yawnLeft: TimeInterval = 0

    public init() {}

    /// - Parameters:
    ///   - idleSeconds: seconds since the last keyboard or mouse event.
    ///   - fullScreen: a full screen window is in front.
    ///   - busy: the corgi is held, in Chase Me, or chasing a ball. Busy never rests and wakes a rest.
    public func update(dt: TimeInterval, idleSeconds: TimeInterval, fullScreen: Bool, busy: Bool) -> RestEvent? {
        let wantsRest = !busy && (idleSeconds >= idleThreshold || fullScreen)
        switch phase {
        case .awake:
            guard wantsRest else { return nil }
            if fullScreen {
                phase = .asleep
                return .fallAsleep
            }
            phase = .yawning
            yawnLeft = yawnDuration
            return .startYawn
        case .yawning:
            guard wantsRest else {
                phase = .awake
                return .wake
            }
            yawnLeft -= dt
            guard yawnLeft <= 0 else { return nil }
            phase = .asleep
            return .fallAsleep
        case .asleep:
            guard !wantsRest else { return nil }
            phase = .awake
            return .wake
        }
    }
}
```

`Sources/CorgiCore/Attention.swift`:
```swift
import Foundation

/// Cursor resting on the corgi pets it after `delay`, then again every `repeatEvery`.
public final class HoverPet {
    public var delay: TimeInterval = 0.4
    public var repeatEvery: TimeInterval = 1.5
    private var hovered: TimeInterval = 0
    private var nextPetAt: TimeInterval = 0

    public init() {}

    /// - Parameter blocked: dragging, held, roaming, or asleep. Blocked hover never pets and resets the timer.
    /// - Returns: true when a pet should happen now (the caller still applies the rate limit).
    public func update(dt: TimeInterval, hovering: Bool, blocked: Bool) -> Bool {
        guard hovering && !blocked else {
            hovered = 0
            nextPetAt = delay
            return false
        }
        if hovered == 0 { nextPetAt = delay }
        hovered += dt
        guard hovered >= nextPetAt else { return false }
        nextPetAt += repeatEvery
        return true
    }
}

/// Bored after `threshold` seconds with no interaction, while happy and rested enough to play.
public final class BoredomTimer {
    public var threshold: TimeInterval = 600
    public var minHappiness = 50.0
    public var minEnergy = 40.0
    let clock: Clock
    private var lastInteraction: Date

    public init(clock: Clock) {
        self.clock = clock
        lastInteraction = clock.now
    }

    /// Pets, drags, catches, menu care actions, and starting a ball chase all count.
    public func noteInteraction() {
        lastInteraction = clock.now
    }

    public var secondsSinceInteraction: TimeInterval {
        max(0, clock.now.timeIntervalSince(lastInteraction))
    }

    public func isBored(_ needs: NeedsState) -> Bool {
        secondsSinceInteraction >= threshold && needs.happiness > minHappiness && needs.energy > minEnergy
    }
}
```

In `Sources/CorgiCore/Needs.swift`, add to `NeedsConfig` after `bathAmount`:
```swift
    public var catchAmount = 10.0
```
and replace the whole `pet()` method (with its `@discardableResult`) with:
```swift
    @discardableResult
    public func pet() -> Bool { rateLimitedHappiness(config.petAmount) }

    /// Catching the corgi in Chase Me. Shares the pet rate limit.
    @discardableResult
    public func catchPet() -> Bool { rateLimitedHappiness(config.catchAmount) }

    private func rateLimitedHappiness(_ amount: Double) -> Bool {
        let now = clock.now
        petTimes.removeAll { now.timeIntervalSince($0) >= 60 || $0 > now }
        guard petTimes.count < config.petsPerMinute else { return false }
        petTimes.append(now)
        restore(.happiness, by: amount)
        return true
    }
```
Keep the `/// Returns false when the per-minute pet limit is reached.` comment above `pet()`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "RestTests|AttentionTests"`
Expected: 10 tests PASS (5 + 5).
Run: `swift test`
Expected: 103 tests PASS (93 + 10).

- [ ] **Step 5: Commit**

```bash
git add Sources/CorgiCore/Rest.swift Sources/CorgiCore/Attention.swift Sources/CorgiCore/Needs.swift Tests/CorgiCoreTests/RestTests.swift
git commit -m "feat: rest monitor, hover pet, boredom timer"
```

### Task 23: Ball path model and roam steering (Chase Me, ball chase)

**Files:**
- Create: `Sources/CorgiCore/Ball.swift`
- Modify: `Sources/CorgiCore/BehaviorExecutor.swift`
- Test: `Tests/CorgiCoreTests/BallTests.swift` (classes `BallTests` and `RoamSteeringTests`)

**Interfaces:**
- Consumes: `insetRects`, `rects(_:contain:)`, `nearestPoint` (Task 18), `Body.startRoaming`/`roam`/`stopRoaming` (Task 18), `BehaviorExecutor.home` (Task 21).
- Produces:
  - `final class Ball { init(start: CGPoint, screens: [CGRect], rng: any RandomNumberGenerator = SystemRandomNumberGenerator()); var speed: CGFloat = 180; var lifetime = 30.0; var waypointEvery: ClosedRange<Double> = 1...2; private(set) var position, waypoint: CGPoint; private(set) var age: TimeInterval; private(set) var area: [CGRect]; static func area(for: [CGRect]) -> [CGRect]; var popped: Bool; func setScreens(_ screens: [CGRect]); func step(dt: TimeInterval) }`. Speed 180 is below the corgi's run speed (240) so it can catch up.
  - `BehaviorExecutor.ballPosition: CGPoint?`, `onBallCaught: (() -> Void)?`, `private(set) carryingBall: Bool`, `dodgeRadius: CGFloat = 150`, `catchRadius: CGFloat = 30`.
  - `begin(.chaseMe)` / `begin(.ballChase)` call `body.startRoaming()`.
  - `chaseMe` step: inside 150pt of the cursor, head 300pt straight away from it (clamped to the screens); otherwise run to random waypoints inside the screens; never finishes on its own.
  - `ballChase` step: run so the mouth (30pt above the feet) reaches the ball; within 30pt call `onBallCaught` once and set `carryingBall`; roam to 60pt above `home`, `stopRoaming()`, and finish on landing. Finishes early when `ballPosition` is nil before the catch (ball popped).

- [ ] **Step 1: Write the failing tests**

`Tests/CorgiCoreTests/BallTests.swift`:
```swift
import XCTest
@testable import CorgiCore

final class BallTests: XCTestCase {
    let dt = 1.0 / 60

    func testBallStaysOnScreenAndKeepsPickingWaypoints() {
        let ball = Ball(start: CGPoint(x: 700, y: 400), screens: [screen0], rng: SeededRandom(seed: 5))
        var waypoints = Set<String>()
        var travelled: CGFloat = 0
        var last = ball.position
        for _ in 0..<Int(29 / dt) {
            ball.step(dt: dt)
            XCTAssertTrue(rects(ball.area, contain: ball.position))
            waypoints.insert("\(ball.waypoint)")
            travelled += hypot(ball.position.x - last.x, ball.position.y - last.y)
            last = ball.position
        }
        XCTAssertGreaterThanOrEqual(waypoints.count, 14)   // a new one every 1-2s
        XCTAssertGreaterThan(travelled, 1500)
        XCTAssertFalse(ball.popped)
    }

    func testBallPopsAfterThirtySeconds() {
        let ball = Ball(start: CGPoint(x: 700, y: 400), screens: [screen0], rng: SeededRandom(seed: 1))
        for _ in 0..<Int(30 / dt) + 1 { ball.step(dt: dt) }
        XCTAssertTrue(ball.popped)
    }

    func testBallComesBackWhenItsMonitorIsUnplugged() {
        let screen1 = CGRect(x: 1440, y: 0, width: 1920, height: 1000)
        let ball = Ball(start: CGPoint(x: 2500, y: 600), screens: [screen0, screen1], rng: SeededRandom(seed: 2))
        ball.step(dt: dt)
        ball.setScreens([screen0])
        XCTAssertTrue(rects(ball.area, contain: ball.position))
        XCTAssertTrue(rects(ball.area, contain: ball.waypoint))
        for _ in 0..<120 {
            ball.step(dt: dt)
            XCTAssertTrue(rects(ball.area, contain: ball.position))
        }
    }
}

final class RoamSteeringTests: XCTestCase {
    var world: World!
    let dt = 1.0 / 60

    override func setUp() {
        world = World(provider: FakeWindows(), screens: [screen0])
        world.refresh()
    }

    func tick(_ ex: BehaviorExecutor, _ b: Behavior, _ body: Body, cursor: CGPoint) -> Bool {
        if ex.step(b, body: body, world: world, cursor: cursor) { return true }
        if let e = body.step(dt: dt, world: world), ex.handle(e, behavior: b, body: body) { return true }
        return false
    }

    func testChaseMeWandersInsideTheScreens() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 4))
        let body = Body(position: CGPoint(x: 700, y: 300))
        ex.begin(.chaseMe, body: body, world: world, cursor: .zero)
        XCTAssertEqual(body.mode, .roaming)
        let area = insetRects(world.screens, side: 20, top: body.config.roamHeadroom)
        var xs = Set<Int>()
        for _ in 0..<Int(10 / dt) {
            XCTAssertFalse(tick(ex, .chaseMe, body, cursor: CGPoint(x: -500, y: -500)))
            XCTAssertTrue(rects(area, contain: body.position))
            xs.insert(Int(body.position.x / 100))
        }
        XCTAssertEqual(body.mode, .roaming)
        XCTAssertGreaterThan(xs.count, 3)
    }

    func testChaseMeDodgesANearbyCursor() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 4))
        let body = Body(position: CGPoint(x: 700, y: 400))
        ex.begin(.chaseMe, body: body, world: world, cursor: .zero)
        let cursor = CGPoint(x: 600, y: 400)
        for _ in 0..<Int(0.5 / dt) { _ = tick(ex, .chaseMe, body, cursor: cursor) }
        XCTAssertGreaterThan(body.position.x, 780)
        XCTAssertTrue(body.facingRight)
    }

    func testBallChaseCatchesCarriesHomeAndDrops() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        ex.home = CGPoint(x: 1360, y: 0)
        var catches = 0
        ex.onBallCaught = { catches += 1 }
        let ball = Ball(start: CGPoint(x: 200, y: 600), screens: [screen0], rng: SeededRandom(seed: 9))
        let body = Body(position: CGPoint(x: 1000, y: 0))
        _ = body.step(dt: dt, world: world)
        ex.begin(.ballChase, body: body, world: world, cursor: .zero)
        var done = false
        for _ in 0..<Int(30 / dt) {
            ball.step(dt: dt)
            ex.ballPosition = catches == 0 ? ball.position : nil
            if tick(ex, .ballChase, body, cursor: .zero) {
                done = true
                break
            }
        }
        XCTAssertTrue(done)
        XCTAssertEqual(catches, 1)
        XCTAssertTrue(ex.carryingBall)
        XCTAssertEqual(body.mode, .grounded)
        XCTAssertEqual(body.position.x, 1360, accuracy: 15)
    }

    func testBallChaseEndsWhenBallIsGone() {
        let ex = BehaviorExecutor(rng: SeededRandom(seed: 1))
        let body = Body(position: CGPoint(x: 700, y: 300))
        ex.begin(.ballChase, body: body, world: world, cursor: .zero)
        ex.ballPosition = nil
        XCTAssertTrue(ex.step(.ballChase, body: body, world: world, cursor: .zero))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "BallTests|RoamSteeringTests"`
Expected: compile errors, `cannot find 'Ball' in scope`, `value of type 'BehaviorExecutor' has no member 'onBallCaught'`.

- [ ] **Step 3: Implement**

`Sources/CorgiCore/Ball.swift`:
```swift
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// A ball that drifts around the visible screen area on a smooth random path and pops after `lifetime`.
public final class Ball {
    public var speed: CGFloat = 180
    public var lifetime: TimeInterval = 30
    public var waypointEvery: ClosedRange<Double> = 1...2
    public private(set) var position: CGPoint
    public private(set) var waypoint: CGPoint
    public private(set) var age: TimeInterval = 0
    public private(set) var area: [CGRect]
    private var velocity: CGVector = .zero
    private var untilNewWaypoint: TimeInterval = 0
    private var rng: any RandomNumberGenerator

    public init(start: CGPoint, screens: [CGRect], rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.rng = rng
        area = Ball.area(for: screens)
        position = nearestPoint(to: start, in: area)
        waypoint = position
    }

    /// Visible frames minus side and top margins, lifted 30pt off the floor.
    public static func area(for screens: [CGRect]) -> [CGRect] {
        insetRects(screens, side: 20, top: 40).map {
            CGRect(x: $0.minX, y: $0.minY + 30, width: $0.width, height: max(0, $0.height - 30))
        }
    }

    public var popped: Bool { age >= lifetime }

    private func random() -> CGFloat {
        CGFloat(Double(rng.next() >> 11) / Double(1 << 53))
    }

    private func pickWaypoint() {
        guard !area.isEmpty else { return }
        let r = area[Int(random() * CGFloat(area.count)) % area.count]
        waypoint = CGPoint(x: r.minX + random() * r.width, y: r.minY + random() * r.height)
        let lo = waypointEvery.lowerBound, hi = waypointEvery.upperBound
        untilNewWaypoint = lo + Double(random()) * (hi - lo)
    }

    /// Monitors changed: pull the ball and its waypoint back inside what is left.
    public func setScreens(_ screens: [CGRect]) {
        area = Ball.area(for: screens)
        position = nearestPoint(to: position, in: area)
        if !rects(area, contain: waypoint) { pickWaypoint() }
    }

    public func step(dt: TimeInterval) {
        age += dt
        untilNewWaypoint -= dt
        if untilNewWaypoint <= 0 { pickWaypoint() }
        let dx = waypoint.x - position.x, dy = waypoint.y - position.y
        let dist = max(hypot(dx, dy), 0.001)
        let desired = CGVector(dx: dx / dist * speed, dy: dy / dist * speed)
        let k = min(1, CGFloat(dt) * 3)
        velocity = CGVector(dx: velocity.dx + (desired.dx - velocity.dx) * k,
                            dy: velocity.dy + (desired.dy - velocity.dy) * k)
        let next = CGPoint(x: position.x + velocity.dx * CGFloat(dt), y: position.y + velocity.dy * CGFloat(dt))
        position = nearestPoint(to: next, in: area)
    }
}
```

Replace `Sources/CorgiCore/BehaviorExecutor.swift` with:
```swift
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

public final class BehaviorExecutor {
    public var targetX: CGFloat?
    public var speedScale: CGFloat = 1
    /// Home spot for `goHome`. Set by the caller whenever screens change.
    public var home: CGPoint?
    /// Live ball position for `ballChase`. Set by the caller every tick; nil once the ball is gone.
    public var ballPosition: CGPoint?
    /// Called once when the corgi reaches the ball.
    public var onBallCaught: (() -> Void)?
    public private(set) var carryingBall = false
    public var dodgeRadius: CGFloat = 150
    public var catchRadius: CGFloat = 30
    private enum BallPhase { case chasing, carrying, dropping }
    private var ballPhase: BallPhase = .chasing
    private var waypoint: CGPoint?
    private var rng: any RandomNumberGenerator
    private var zoomDirection: CGFloat = 1
    private var hopStarted = false
    private var hopDownDirection: CGFloat?
    private var homePlanned = false
    private var homeLeapDirection: CGFloat?

    public init(rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.rng = rng
    }

    private func random() -> CGFloat {
        CGFloat(Double(rng.next() >> 11) / Double(1 << 53))
    }

    public func begin(_ b: Behavior, body: Body, world: World, cursor: CGPoint) {
        targetX = nil
        hopStarted = false
        hopDownDirection = nil
        homePlanned = false
        homeLeapDirection = nil
        carryingBall = false
        ballPhase = .chasing
        waypoint = nil
        if body.mode == .roaming && b != .chaseMe && b != .ballChase { body.stopRoaming() }
        body.stop()
        let segment = body.standingOn ?? world.segment(under: body.position)
        switch b {
        case .walk:
            if let s = segment {
                let lo = s.minX + 20, hi = max(lo, s.maxX - 20)
                targetX = lo + random() * (hi - lo)
            }
        case .greet:
            body.face(right: cursor.x >= body.position.x)
        case .zoomies:
            zoomDirection = random() < 0.5 ? -1 : 1
        case .chaseMe, .ballChase:
            body.startRoaming()
        case .hopToWindow:
            let options = world.reachableSegments(from: body.position,
                                                  maxJumpUp: body.config.maxJumpUp,
                                                  maxJumpAcross: body.config.maxJumpAcross)
                .prefix(3)
            guard !options.isEmpty else { return }
            let pick = options[options.startIndex + Int(random() * CGFloat(options.count)) % options.count]
            if let s = segment, pick.y < s.y {
                // Going down: walk to the edge on the side where the lower segment continues, then leap.
                let sides: [(dir: CGFloat, edge: CGFloat, landX: CGFloat)] = [(-1, s.minX, s.minX - 40), (1, s.maxX, s.maxX + 40)]
                guard let side = sides
                    .filter({ pick.contains(x: $0.landX) })
                    .min(by: { abs($0.edge - body.position.x) < abs($1.edge - body.position.x) })
                else { return }
                hopDownDirection = side.dir
                targetX = side.edge
            } else {
                let x = min(max(body.position.x, pick.minX + 30), pick.maxX - 30)
                body.jump(to: CGPoint(x: x, y: pick.y))
            }
            hopStarted = true
        default:
            break
        }
    }

    public func step(_ b: Behavior, body: Body, world: World, cursor: CGPoint) -> Bool {
        if b == .chaseMe {
            stepChaseMe(body: body, world: world, cursor: cursor)
            return false
        }
        if b == .ballChase { return stepBallChase(body: body) }
        if b == .hopToWindow {
            guard hopStarted else { return true }
            if let dir = hopDownDirection, body.mode == .grounded, let target = targetX {
                if abs(target - body.position.x) < 4 {
                    body.leap(direction: dir)
                    hopDownDirection = nil
                } else {
                    body.walk(direction: target - body.position.x, speed: body.config.walkSpeed * 1.5)
                }
            }
            return false
        }
        guard body.mode == .grounded else { return false }
        switch b {
        case .goHome:
            return stepHome(body: body, world: world)
        case .walk, .fetch:
            guard let target = targetX else { return b == .walk }
            let dx = target - body.position.x
            if abs(dx) < 4 {
                body.stop()
                return true
            }
            let speed = b == .walk ? body.config.walkSpeed * speedScale : body.config.runSpeed
            body.walk(direction: dx, speed: speed)
        case .zoomies:
            body.walk(direction: zoomDirection, speed: body.config.runSpeed * 1.2)
        case .chaseCursor:
            let segment = body.standingOn ?? world.segment(under: body.position)
            let dx = cursor.x - body.position.x
            if let s = segment, s.contains(x: cursor.x), abs(dx) > 30 {
                body.walk(direction: dx, speed: body.config.runSpeed)
            } else {
                body.stop()
                body.face(right: dx >= 0)
            }
        default:
            body.stop()
        }
        return false
    }

    public func handle(_ event: BodyEvent, behavior: Behavior, body: Body) -> Bool {
        switch (behavior, event) {
        case (.zoomies, .hitEdge):
            zoomDirection = -zoomDirection
            return false
        case (.walk, .hitEdge):
            return true
        case (.hopToWindow, .landed):
            return true
        case (.chaseMe, .hitEdge):
            waypoint = nil
            return false
        case (.ballChase, .landed):
            return ballPhase == .dropping
        case (.goHome, .landed):
            homePlanned = false
            return false
        case (.goHome, .hitEdge):
            if let dir = homeLeapDirection {
                body.leap(direction: dir)
                homeLeapDirection = nil
            }
            return false
        case (.hopToWindow, .hitEdge):
            if let dir = hopDownDirection {
                body.leap(direction: dir)
                hopDownDirection = nil
            }
            return false
        default:
            return false
        }
    }

    /// Walks (runs if far) to `home`. From another floor it leaps off the edge facing home,
    /// or jumps up if home is higher and in range, then re-plans after landing.
    private func stepHome(body: Body, world: World) -> Bool {
        guard let home else { return true }
        guard let s = body.standingOn ?? world.segment(under: body.position) else { return false }
        if s.contains(x: home.x) && abs(s.y - home.y) <= 2 {
            let dx = home.x - body.position.x
            if abs(dx) < 4 {
                body.stop()
                return true
            }
            body.walk(direction: dx, speed: abs(dx) > 300 ? body.config.runSpeed : body.config.walkSpeed)
            return false
        }
        if !homePlanned {
            homePlanned = true
            if home.y > s.y + 2 {
                guard let hs = world.segment(under: home),
                      home.y - s.y <= body.config.maxJumpUp,
                      abs(hs.clampX(body.position.x) - body.position.x) <= body.config.maxJumpAcross
                else { return true }
                body.jump(to: CGPoint(x: min(max(body.position.x, hs.minX + 30), hs.maxX - 30), y: home.y))
                return false
            }
            if home.x < s.minX {
                homeLeapDirection = -1
            } else if home.x > s.maxX {
                homeLeapDirection = 1
            } else {
                homeLeapDirection = body.position.x - s.minX <= s.maxX - body.position.x ? -1 : 1
            }
        }
        if let dir = homeLeapDirection {
            let edge = dir < 0 ? s.minX : s.maxX
            if abs(edge - body.position.x) < 4 {
                body.leap(direction: dir)
                homeLeapDirection = nil
            } else {
                body.walk(direction: edge - body.position.x, speed: body.config.runSpeed)
            }
        }
        return false
    }

    private func randomPoint(in area: [CGRect]) -> CGPoint? {
        guard !area.isEmpty else { return nil }
        let r = area[Int(random() * CGFloat(area.count)) % area.count]
        return CGPoint(x: r.minX + random() * r.width, y: r.minY + random() * r.height)
    }

    /// Runs between random waypoints; inside `dodgeRadius` of the cursor it heads straight away from it.
    private func stepChaseMe(body: Body, world: World, cursor: CGPoint) {
        guard body.mode == .roaming else { return }
        let area = insetRects(world.screens, side: 20, top: body.config.roamHeadroom)
        let ax = body.position.x - cursor.x, ay = body.position.y - cursor.y
        let d = hypot(ax, ay)
        if d < dodgeRadius {
            let ux = d > 0.1 ? ax / d : (random() < 0.5 ? -1 : 1), uy = d > 0.1 ? ay / d : 0
            waypoint = nearestPoint(to: CGPoint(x: body.position.x + ux * 300, y: body.position.y + uy * 300), in: area)
        } else if waypoint.map({ hypot($0.x - body.position.x, $0.y - body.position.y) < 10 }) ?? true {
            waypoint = randomPoint(in: area)
        }
        if let w = waypoint { body.roam(toward: w, speed: body.config.runSpeed) }
    }

    /// Chase the ball (mouth 30pt above the feet), carry it above home, then drop to the floor.
    /// Returns true when the ball is gone before the catch, or after landing with it.
    private func stepBallChase(body: Body) -> Bool {
        switch ballPhase {
        case .chasing:
            guard body.mode == .roaming else { return false }
            guard let ball = ballPosition else { return true }
            let mouth = CGPoint(x: body.position.x, y: body.position.y + 30)
            if hypot(ball.x - mouth.x, ball.y - mouth.y) <= catchRadius {
                ballPhase = .carrying
                carryingBall = true
                onBallCaught?()
            } else {
                body.roam(toward: CGPoint(x: ball.x, y: ball.y - 30), speed: body.config.runSpeed)
            }
        case .carrying:
            guard body.mode == .roaming else { return false }
            let target = home.map { CGPoint(x: $0.x, y: $0.y + 60) } ?? body.position
            if hypot(target.x - body.position.x, target.y - body.position.y) < 10 {
                body.stopRoaming()
                ballPhase = .dropping
            } else {
                body.roam(toward: target, speed: body.config.runSpeed)
            }
        case .dropping:
            break
        }
        return false
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "BallTests|RoamSteeringTests"`
Expected: 7 tests PASS (3 + 4).
Run: `swift test`
Expected: 110 tests PASS (103 + 7).

- [ ] **Step 5: Commit**

```bash
git add Sources/CorgiCore/Ball.swift Sources/CorgiCore/BehaviorExecutor.swift Tests/CorgiCoreTests/BallTests.swift
git commit -m "feat: ball path and roam steering"
```

### Task 24: App wiring: home, greeting, speech bubbles, props, idle and full screen sleep, hover pet, scared drag

**Files:**
- Modify: `Sources/DesktopCorgi/Effects.swift`
- Modify: `Sources/DesktopCorgi/OverlayWindow.swift`
- Modify: `Sources/DesktopCorgi/PetController.swift`
- Modify: `Sources/DesktopCorgi/AppDelegate.swift`

**Interfaces:**
- Consumes: `HomeTracker`, `Greeting` (Task 21), `RestMonitor`, `isFullScreen`, `HoverPet` (Task 22), `BrainContext` home fields (Task 20), `Behavior.countsAsSleep`, new `AnimState`s (Task 19), `World.windows` (Task 5).
- Produces:
  - `Effects.speech(_ text: String, on node: SKNode, height: CGFloat, delay: TimeInterval = 0)` (2.5s bubble), `Effects.makeProp(_ emoji: String) -> SKLabelNode`
  - `PetController.greet(awaySeconds: TimeInterval)` replaces `greet()`. `PetController.home`, `.rest`, `.hover`.
  - Overlay panels gain `.fullScreenAuxiliary`.
  - Drag release now runs `goHome` (lands first, then walks or runs home) instead of `fall`. Held corgi puffs 💦 every 0.6s.
  - Idle activities show emoji props: 📖 read/readSleep, 🎧 music, 📺 watchTV, ⚽️ playBallHome.

- [ ] **Step 1: Effects**

Replace `Sources/DesktopCorgi/Effects.swift` with:
```swift
#if canImport(AppKit)
import AppKit
import SpriteKit

enum Effects {
    /// Emoji that floats up from above the corgi and fades out.
    static func floatEmoji(_ text: String, on node: SKNode, height: CGFloat, count: Int = 1) {
        for i in 0..<count {
            let label = SKLabelNode(text: text)
            label.fontSize = 18
            label.position = CGPoint(x: CGFloat.random(in: -18...18), y: height)
            label.alpha = 0
            node.addChild(label)
            label.run(.sequence([
                .wait(forDuration: Double(i) * 0.15),
                .fadeIn(withDuration: 0.1),
                .group([.moveBy(x: 0, y: 40, duration: 1.0), .fadeOut(withDuration: 1.0)]),
                .removeFromParent(),
            ]))
        }
    }

    /// Rounded speech bubble above the corgi for 2.5s, after `delay`.
    static func speech(_ text: String, on node: SKNode, height: CGFloat, delay: TimeInterval = 0) {
        let label = SKLabelNode(text: text)
        label.fontName = NSFont.boldSystemFont(ofSize: 13).fontName
        label.fontSize = 13
        label.fontColor = .black
        label.verticalAlignmentMode = .center
        let w = label.frame.width + 18, h: CGFloat = 24
        let bubble = SKShapeNode(rect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: 10)
        bubble.fillColor = .white
        bubble.strokeColor = NSColor(white: 0.2, alpha: 1)
        bubble.lineWidth = 1.5
        bubble.addChild(label)
        bubble.position = CGPoint(x: 0, y: height + 22)
        bubble.zPosition = 50
        bubble.alpha = 0
        node.addChild(bubble)
        bubble.run(.sequence([
            .wait(forDuration: delay),
            .fadeIn(withDuration: 0.15),
            .wait(forDuration: 2.2),
            .fadeOut(withDuration: 0.15),
            .removeFromParent(),
        ]))
    }

    /// Placeholder prop drawn next to the corgi (📖 🎧 📺 ⚽️) until the art pack has one.
    static func makeProp(_ emoji: String) -> SKLabelNode {
        let label = SKLabelNode(text: emoji)
        label.fontSize = 22
        label.verticalAlignmentMode = .baseline
        label.zPosition = 5
        return label
    }

    static func makeBall() -> SKShapeNode {
        let ball = SKShapeNode(circleOfRadius: 7)
        ball.fillColor = .systemRed
        ball.strokeColor = .white
        ball.lineWidth = 1.5
        return ball
    }
}
#endif
```

- [ ] **Step 2: Overlay stays on full screen Spaces**

In `Sources/DesktopCorgi/OverlayWindow.swift`, replace `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]` with:
```swift
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
```

- [ ] **Step 3: Controller**

Replace `Sources/DesktopCorgi/PetController.swift` with:
```swift
#if canImport(AppKit)
import AppKit
import CorgiCore
import SpriteKit

final class PetController {
    let needs: NeedsEngine
    let brain = Brain()
    let executor = BehaviorExecutor()
    let world: World
    let body: Body
    let backend: AnimationBackend
    let overlays: OverlayManager

    var animOverride: (state: AnimState, until: CFTimeInterval)?
    private var currentAnim: AnimState?
    private var timer: Timer?
    private var timerFPS = 0
    private var worldTimer: Timer?
    private var lastTick = CACurrentMediaTime()
    var onRightClick: ((NSEvent, NSView) -> Void)?
    private var pressPoint: CGPoint?
    private var dragging = false
    private enum FetchPhase { case chasing(returnX: CGFloat), returning }
    private var fetchPhase: FetchPhase?
    private var ball: SKShapeNode?
    let debug = DebugOverlay()
    private var paused = false
    private var screenLocked = false
    private var screensAsleep = false
    private var lastZzz: CFTimeInterval = 0
    private var lastSweat: CFTimeInterval = 0
    let home = HomeTracker(clock: SystemClock())
    let rest = RestMonitor()
    let hover = HoverPet()
    private var prop: SKLabelNode?
    private var propEmoji: String?
    private static let props: [Behavior: String] = [
        .read: "📖", .readSleep: "📖", .music: "🎧", .watchTV: "📺", .playBallHome: "⚽️",
    ]

    init(needs: NeedsEngine, backend: AnimationBackend) {
        self.needs = needs
        self.backend = backend
        overlays = OverlayManager(corgiNode: backend.node)
        world = World(provider: CGWindowListProvider(), screens: NSScreen.screens.map(\.visibleFrame))
        let vf = NSScreen.main?.visibleFrame ?? .zero
        body = Body(position: CGPoint(x: vf.midX, y: vf.maxY - 100))
        overlays.input = self
        updateHome()
    }

    /// Home is on the primary screen (the one with the menu bar), index 0 in `world.screens`.
    private func updateHome() {
        home.setScreens(world.screens, mainIndex: 0)
        executor.home = home.spot
    }

    var hitRect: CGRect {
        CGRect(x: body.position.x - backend.size.width / 2, y: body.position.y,
               width: backend.size.width, height: backend.size.height)
    }

    func start() {
        world.refresh()
        worldTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshWorld() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshWorld() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.screensChanged() }
        setRate(30)
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = true
            self?.updatePaused()
        }
        distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = false
            self?.updatePaused()
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = true
            self?.updatePaused()
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = false
            self?.updatePaused()
        }
    }

    /// Wave and say hi on every launch; a second bubble if away more than an hour.
    func greet(awaySeconds: TimeInterval) {
        wake()
        let lines = Greeting.lines(awaySeconds: awaySeconds)
        brain.interrupt(with: .greet, duration: lines.count > 1 ? 5.5 : 3)
        beginBehavior(.greet)
        for (i, line) in lines.enumerated() {
            Effects.speech(line, on: backend.node, height: backend.size.height, delay: Double(i) * 2.6)
        }
    }

    /// Stays paused until the screen is both unlocked and awake.
    private func updatePaused() {
        setPaused(screenLocked || screensAsleep)
    }

    func setPaused(_ paused: Bool) {
        guard paused != self.paused else { return }
        self.paused = paused
        overlays.setPaused(paused)
        if paused {
            timer?.invalidate()
            timer = nil
            timerFPS = 0
        } else {
            lastTick = CACurrentMediaTime()
            setRate(30)
        }
    }

    private func setRate(_ fps: Int) {
        guard fps != timerFPS else { return }
        timerFPS = fps
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / Double(fps), repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        overlays.setFPS(fps)
    }

    func refreshWorld() {
        if body.apply(world.refresh()) == .startedFalling { fell() }
    }

    func screensChanged() {
        world.setScreens(NSScreen.screens.map(\.visibleFrame))
        overlays.rebuild()
        overlays.setPaused(paused)
        if timerFPS > 0 { overlays.setFPS(timerFPS) }
        body.clamp(to: world.screens)
        updateHome()
    }

    /// Called when the floor disappears under the corgi.
    func fell() {
        Effects.floatEmoji("❗", on: backend.node, height: backend.size.height)
        brain.interrupt(with: .fall, duration: 5)
        beginBehavior(.fall)
    }

    func beginBehavior(_ b: Behavior) {
        if b != .fetch && fetchPhase != nil { clearFetch() }
        if needs.state.isAsleep != b.countsAsSleep { needs.setAsleep(b.countsAsSleep) }
        executor.speedScale = needs.isLow(.happiness) ? 0.6 : 1
        executor.begin(b, body: body, world: world, cursor: NSEvent.mouseLocation)
    }

    /// The executor says the current behavior is done.
    func stepFinished() {
        if brain.current == .fetch && advanceFetch() { return }
        brain.finishCurrent()
    }

    func feed() {
        wake()
        brain.interrupt(with: .eat, duration: 4)
        beginBehavior(.eat)
        needs.feed()
        Effects.floatEmoji("🍖", on: backend.node, height: backend.size.height)
    }

    func bath() {
        wake()
        brain.interrupt(with: .bath, duration: 4)
        beginBehavior(.bath)
        needs.bath()
        Effects.floatEmoji("🫧", on: backend.node, height: backend.size.height, count: 5)
    }

    func nap() {
        brain.interrupt(with: .sleep, duration: 120)
        beginBehavior(.sleep)
    }

    func playBall() {
        wake()
        clearFetch()
        guard body.mode == .grounded, let segment = body.standingOn, segment.width > 200,
              let scene = overlays.currentScene else {
            needs.play()
            Effects.floatEmoji("❤️", on: backend.node, height: backend.size.height, count: 3)
            animOverride = (.wiggle, CACurrentMediaTime() + 0.8)
            return
        }
        let start = body.position.x
        let roomRight = segment.maxX - 20 - start, roomLeft = start - (segment.minX + 20)
        let rawX = roomRight >= roomLeft ? start + CGFloat.random(in: 100...max(100, roomRight))
                                         : start - CGFloat.random(in: 100...max(100, roomLeft))
        let ballX = min(max(rawX, segment.minX + 20), segment.maxX - 20)
        let landing = overlays.toScene(CGPoint(x: ballX, y: segment.y + 7))
        let launch = overlays.toScene(CGPoint(x: start, y: segment.y + 40))
        let ball = Effects.makeBall()
        ball.position = launch
        scene.addChild(ball)
        let path = CGMutablePath()
        path.move(to: launch)
        path.addQuadCurve(to: landing, control: CGPoint(x: (launch.x + landing.x) / 2, y: launch.y + 160))
        ball.run(.follow(path, asOffset: false, orientToPath: false, duration: 0.7))
        self.ball = ball

        brain.interrupt(with: .fetch, duration: 20)
        beginBehavior(.fetch)
        executor.targetX = ballX
        fetchPhase = .chasing(returnX: start)
    }

    private func wake() {
        if brain.current.countsAsSleep { brain.finishCurrent() }
        if needs.state.isAsleep { needs.setAsleep(false) }
    }

    /// Moves the fetch along. Returns true while fetch still has work to do.
    private func advanceFetch() -> Bool {
        switch fetchPhase {
        case .chasing(let returnX):
            ball?.removeAllActions()
            ball?.removeFromParent()
            if let ball {
                // Hold the ball at the mouth on the side the corgi is about to walk toward.
                ball.position = CGPoint(x: returnX >= body.position.x ? 26 : -26, y: 30)
                backend.node.addChild(ball)
            }
            executor.targetX = returnX
            fetchPhase = .returning
            return true
        case .returning:
            clearFetch()
            needs.play()
            Effects.floatEmoji("❤️", on: backend.node, height: backend.size.height, count: 3)
            return false
        case nil:
            return false
        }
    }

    private func clearFetch() {
        ball?.removeFromParent()
        ball = nil
        fetchPhase = nil
    }

    /// Seconds since any keyboard or mouse event. Needs no permission.
    private var userIdleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    private var restBusy: Bool {
        dragging || body.mode == .held || body.mode == .roaming || brain.current == .ballChase
    }

    private func updateRest(dt: TimeInterval, now: CFTimeInterval) {
        let fullScreen = isFullScreen(frontWindow: world.windows.first?.frame,
                                      screenFrames: NSScreen.screens.map(\.frame))
        switch rest.update(dt: dt, idleSeconds: userIdleSeconds, fullScreen: fullScreen, busy: restBusy) {
        case .startYawn?:
            brain.interrupt(with: .yawn, duration: .infinity)
            beginBehavior(.yawn)
        case .fallAsleep?:
            brain.interrupt(with: .idleSleep, duration: .infinity)
            beginBehavior(.idleSleep)
        case .wake?:
            if brain.current == .yawn || brain.current == .idleSleep {
                brain.finishCurrent()
                needs.setAsleep(false)
                animOverride = (.wiggle, now + 0.8)
            }
        case nil:
            break
        }
    }

    private func updateHover(dt: TimeInterval, cursor: CGPoint) {
        let blocked = dragging || pressPoint != nil || body.mode != .grounded
            || brain.current.countsAsSleep || brain.current == .yawn
        if hover.update(dt: dt, hovering: hitRect.contains(cursor), blocked: blocked) { hoverPet() }
    }

    private func hoverPet() {
        if needs.pet() {
            Effects.floatEmoji("❤️", on: backend.node, height: backend.size.height, count: 2)
            animOverride = (.happy, CACurrentMediaTime() + 0.8)
        }
    }

    /// Emoji props for idle activities until the art pack has them.
    private func updateProp() {
        let want = body.mode == .grounded ? Self.props[brain.current] : nil
        guard want != propEmoji else { return }
        prop?.removeFromParent()
        prop = nil
        propEmoji = want
        guard let want else { return }
        let p = Effects.makeProp(want)
        let side: CGFloat = body.facingRight ? 1 : -1
        let w = backend.size.width, h = backend.size.height
        switch brain.current {
        case .music: p.position = CGPoint(x: side * w * 0.35, y: h * 0.7)
        case .watchTV: p.position = CGPoint(x: side * (w / 2 + 26), y: 0)
        case .playBallHome:
            p.position = CGPoint(x: side * (w / 2 + 6), y: 0)
            p.run(.repeatForever(.sequence([.moveBy(x: 0, y: 16, duration: 0.25), .moveBy(x: 0, y: -16, duration: 0.25)])))
        default: p.position = CGPoint(x: side * (w / 2 + 2), y: 2)
        }
        backend.node.addChild(p)
        prop = p
    }

    func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now
        needs.tick()
        updateRest(dt: dt, now: now)

        home.observe(body.position)
        let canHop = !world.reachableSegments(from: body.position, maxJumpUp: body.config.maxJumpUp,
                                              maxJumpAcross: body.config.maxJumpAcross).isEmpty
        let ctx = BrainContext(needs: needs.state, lowThreshold: needs.config.lowThreshold, canHop: canHop,
                               atHome: home.isHome(body.position), secondsAwayFromHome: home.secondsAway)
        if let next = brain.update(dt: dt, ctx) { beginBehavior(next) }

        let cursor = NSEvent.mouseLocation
        updateHover(dt: dt, cursor: cursor)
        if executor.step(brain.current, body: body, world: world, cursor: cursor) { stepFinished() }
        if let event = body.step(dt: dt, world: world) {
            if executor.handle(event, behavior: brain.current, body: body) { stepFinished() }
            if event == .landed {
                animOverride = (.land, now + 0.25)
                if brain.current == .fall { brain.finishCurrent() }
            }
            if event == .startedFalling { fell() }
        }
        body.clamp(to: world.screens)

        overlays.place(globalFeet: body.position)
        backend.setFacing(right: body.facingRight)
        updateAnimation(now)
        if brain.current.countsAsSleep && now - lastZzz > 2 {
            lastZzz = now
            Effects.floatEmoji("💤", on: backend.node, height: backend.size.height * 0.8)
        }
        if body.mode == .held && now - lastSweat > 0.6 {
            lastSweat = now
            Effects.floatEmoji("💦", on: backend.node, height: backend.size.height * 0.9)
        }
        updateProp()
        debug.update(world: world, hitRect: hitRect, behavior: brain.current, overlays: overlays)
        overlays.setClickThrough(!(body.mode == .held || hitRect.contains(cursor)))
        setRate(body.isMoving || body.mode == .held || animOverride != nil ? 30 : 10)
    }

    private func updateAnimation(_ now: CFTimeInterval) {
        if let o = animOverride, o.until <= now { animOverride = nil }
        let state = animOverride?.state
            ?? animState(for: brain.current, mode: body.mode, isMoving: body.isMoving, isRunning: body.isRunning)
        if state != currentAnim {
            currentAnim = state
            backend.play(state)
        }
    }
}

extension PetController: SceneInputHandler {
    func mouseDown(at global: CGPoint) {
        pressPoint = global
        dragging = false
    }

    func mouseDragged(to global: CGPoint) {
        guard let start = pressPoint else { return }
        if !dragging && hypot(global.x - start.x, global.y - start.y) > 4 {
            dragging = true
            body.pickUp()
            brain.interrupt(with: .dangle, duration: .infinity)
            beginBehavior(.dangle)
        }
        if dragging {
            body.moveHeld(to: CGPoint(x: global.x, y: global.y - backend.size.height * 0.8))
        }
    }

    func mouseUp(at global: CGPoint) {
        defer {
            pressPoint = nil
            dragging = false
        }
        if dragging {
            body.release()
            brain.interrupt(with: .goHome, duration: 30)
            beginBehavior(.goHome)
        } else if pressPoint != nil {
            pet()
        }
    }

    func rightMouseDown(_ event: NSEvent, in view: NSView) {
        onRightClick?(event, view)
    }

    func pet() {
        if brain.current.countsAsSleep {
            brain.finishCurrent()
            needs.setAsleep(false)
        }
        if needs.pet() {
            Effects.floatEmoji("❤️", on: backend.node, height: backend.size.height, count: 3)
            animOverride = (.wiggle, CACurrentMediaTime() + 0.8)
        }
    }
}
#endif
```

What changed against Task 19's version: home tracking (`updateHome()` in `init` and `screensChanged()`, `home.observe` and the home fields of `BrainContext` in `tick()`), `greet(awaySeconds:)` with speech bubbles instead of `greet()` with 👋, `updateRest` (yawn, idle sleep, full screen sleep, wake with a wiggle), `updateHover` and `hoverPet` (`happy` + hearts, same rate limit as clicks), `updateProp`, the 💦 puff while held, and `mouseUp` after a drag interrupting with `goHome` instead of `fall`.

- [ ] **Step 4: Greeting on every launch**

In `Sources/DesktopCorgi/AppDelegate.swift`, replace:
```swift
        if awaySeconds > 3600 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.controller.greet() }
        }
```
with:
```swift
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.controller.greet(awaySeconds: self.awaySeconds)
        }
```

- [ ] **Step 5: Run and verify (needs Mac)**

Run: `swift build && swift test && ./scripts/bundle.sh && open build/DesktopCorgi.app`
Expected:
- 110 tests pass.
- Every launch: the corgi lands, faces the cursor, waves, and a white "Hi!" bubble shows for about 2.5s. With `lastSaved` in `state.json` moved back 2 hours (subtract 7200 while the app is quit), a second "Missed you!" bubble follows.
- Within a few minutes it heads to the bottom-right of the main screen (about 80pt left of the right edge, above the Dock) and mostly hangs out there: 📖 reading (sometimes dozing with 💤), 🎧 music, 📺 TV, ⚽️ kicking, waving, turning around. Debug Overlay shows the behavior names.
- Drag it: shivers (`scared`) with 💦. Drop it on the far left: it lands, then runs home. Drop it on a window title bar: it leaps down and goes home.
- Rest the cursor on it without clicking: after about 0.4s it bounces (`happy`) with hearts, again every 1.5s, at most 10 a minute together with clicks. No hover pets while it sleeps.
- Leave the Mac alone for 90s (no keys, no mouse): it yawns, then sleeps with 💤. Move the mouse: it wiggles awake.
- Open any app in full screen (green button): the corgi is visible on the full screen Space and falls asleep at once. Leave full screen: it wakes.
- Unplug or rearrange the main monitor while it is home: home moves to the remaining screen and it walks there.
On Linux: `swift build && swift test` still pass (110 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/DesktopCorgi
git commit -m "feat: home, greeting bubbles, idle activities, rest and hover pet"
```

### Task 25: App wiring: Chase Me, ball chase (replaces ledge fetch), boredom

**Files:**
- Modify: `Sources/DesktopCorgi/OverlayManager.swift`
- Modify: `Sources/DesktopCorgi/PetMenu.swift`
- Modify: `Sources/DesktopCorgi/AppDelegate.swift`
- Modify: `Sources/DesktopCorgi/PetController.swift`

**Interfaces:**
- Consumes: `Ball`, roam steering, `carryingBall`, `onBallCaught` (Task 23), `BoredomTimer`, `NeedsEngine.catchPet` (Task 22), `animState(...carrying:)` (Task 19).
- Produces:
  - `OverlayManager.place(_ node: SKNode, global p: CGPoint)`
  - `PetMenuActions` gains `toggleChaseMe: () -> Void` and `chaseMeOn: Bool` (declared right after `play`, so the memberwise init order is feed, play, toggleChaseMe, chaseMeOn, bath, ...).
  - `PetController.chaseMe: Bool` (read only), `PetController.setChaseMe(_ on: Bool)`, `PetController.boredom`.
  - `PetController.playBall()` now starts a ball chase: a ball flies around all screens, the corgi roams after it, catches it (+25 happiness via `needs.play()`), carries it home, drops to the floor, and plays `playBallHome` for 8-15s. The ball pops (💥) after 30s if not caught; the brain's 30s `ballChase` duration ends the chase either way.
  - Boredom: `BrainContext.bored = boredom.isBored(needs.state)`. Interactions that reset it: pet, hover pet, drag, feed, bath, nap, Play Ball, Chase Me toggle, catch, and any ball spawn.

Removed (v1 ledge fetch): the `FetchPhase` enum, `fetchPhase`, the `ball: SKShapeNode?` property, `advanceFetch()`, `clearFetch()`, the old `playBall()` body (arc onto the current floor, narrow-perch hearts fallback), the `if b != .fetch && fetchPhase != nil { clearFetch() }` line in `beginBehavior`, and the `.fetch` line in `stepFinished()`. Keep `Effects.makeBall()`; the new ball uses it.

- [ ] **Step 1: Overlay placement for the ball**

In `Sources/DesktopCorgi/OverlayManager.swift`, add after `place(globalFeet:)`:
```swift
    /// Puts any node (the ball) on the overlay of the screen containing the global point `p`.
    func place(_ node: SKNode, global p: CGPoint) {
        guard let target = overlays.first(where: { $0.frame.contains(p) })
            ?? overlays.first(where: { $0.frame.minX <= p.x && p.x < $0.frame.maxX }) ?? overlays.first
        else { return }
        if node.scene !== target.scene {
            node.removeFromParent()
            target.scene.addChild(node)
        }
        node.position = CGPoint(x: p.x - target.frame.minX, y: p.y - target.frame.minY)
    }
```

- [ ] **Step 2: Menu toggle**

Replace `Sources/DesktopCorgi/PetMenu.swift` with:
```swift
#if canImport(AppKit)
import AppKit

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}

struct PetMenuActions {
    var feed: () -> Void
    var play: () -> Void
    var toggleChaseMe: () -> Void
    var chaseMeOn: Bool
    var bath: () -> Void
    var nap: () -> Void
    var stats: () -> Void
    var toggleDebug: () -> Void
    var debugOn: Bool
    var toggleLogin: () -> Void
    var loginOn: Bool
}

enum PetMenu {
    static func populate(_ menu: NSMenu, _ a: PetMenuActions) {
        menu.removeAllItems()
        menu.addItem(ClosureMenuItem("🍖 Feed", handler: a.feed))
        menu.addItem(ClosureMenuItem("🎾 Play Ball", handler: a.play))
        let chase = ClosureMenuItem("🏃 Chase Me", handler: a.toggleChaseMe)
        chase.state = a.chaseMeOn ? .on : .off
        menu.addItem(chase)
        menu.addItem(ClosureMenuItem("🫧 Bath", handler: a.bath))
        menu.addItem(ClosureMenuItem("💤 Nap", handler: a.nap))
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("📊 Stats…", handler: a.stats))
        let debug = ClosureMenuItem("Debug Overlay", handler: a.toggleDebug)
        debug.state = a.debugOn ? .on : .off
        menu.addItem(debug)
        menu.addItem(.separator())
        let login = ClosureMenuItem("Launch at Login", handler: a.toggleLogin)
        login.state = a.loginOn ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }
}
#endif
```

In `Sources/DesktopCorgi/AppDelegate.swift`, in `makeMenuActions()`, insert right after the `play:` line:
```swift
            toggleChaseMe: { [weak self] in
                guard let c = self?.controller else { return }
                c.setChaseMe(!c.chaseMe)
            },
            chaseMeOn: controller.chaseMe,
```

- [ ] **Step 3: Controller**

Replace `Sources/DesktopCorgi/PetController.swift` with:
```swift
#if canImport(AppKit)
import AppKit
import CorgiCore
import SpriteKit

final class PetController {
    let needs: NeedsEngine
    let brain = Brain()
    let executor = BehaviorExecutor()
    let world: World
    let body: Body
    let backend: AnimationBackend
    let overlays: OverlayManager

    var animOverride: (state: AnimState, until: CFTimeInterval)?
    private var currentAnim: AnimState?
    private var timer: Timer?
    private var timerFPS = 0
    private var worldTimer: Timer?
    private var lastTick = CACurrentMediaTime()
    var onRightClick: ((NSEvent, NSView) -> Void)?
    private var pressPoint: CGPoint?
    private var dragging = false
    private(set) var chaseMe = false
    let boredom = BoredomTimer(clock: SystemClock())
    private var ball: Ball?
    private var ballNode: SKShapeNode?
    let debug = DebugOverlay()
    private var paused = false
    private var screenLocked = false
    private var screensAsleep = false
    private var lastZzz: CFTimeInterval = 0
    private var lastSweat: CFTimeInterval = 0
    let home = HomeTracker(clock: SystemClock())
    let rest = RestMonitor()
    let hover = HoverPet()
    private var prop: SKLabelNode?
    private var propEmoji: String?
    private static let props: [Behavior: String] = [
        .read: "📖", .readSleep: "📖", .music: "🎧", .watchTV: "📺", .playBallHome: "⚽️",
    ]

    init(needs: NeedsEngine, backend: AnimationBackend) {
        self.needs = needs
        self.backend = backend
        overlays = OverlayManager(corgiNode: backend.node)
        world = World(provider: CGWindowListProvider(), screens: NSScreen.screens.map(\.visibleFrame))
        let vf = NSScreen.main?.visibleFrame ?? .zero
        body = Body(position: CGPoint(x: vf.midX, y: vf.maxY - 100))
        overlays.input = self
        updateHome()
        executor.onBallCaught = { [weak self] in self?.ballCaught() }
    }

    /// Home is on the primary screen (the one with the menu bar), index 0 in `world.screens`.
    private func updateHome() {
        home.setScreens(world.screens, mainIndex: 0)
        executor.home = home.spot
    }

    var hitRect: CGRect {
        CGRect(x: body.position.x - backend.size.width / 2, y: body.position.y,
               width: backend.size.width, height: backend.size.height)
    }

    func start() {
        world.refresh()
        worldTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshWorld() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshWorld() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.screensChanged() }
        setRate(30)
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = true
            self?.updatePaused()
        }
        distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = false
            self?.updatePaused()
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = true
            self?.updatePaused()
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = false
            self?.updatePaused()
        }
    }

    /// Wave and say hi on every launch; a second bubble if away more than an hour.
    func greet(awaySeconds: TimeInterval) {
        wake()
        let lines = Greeting.lines(awaySeconds: awaySeconds)
        brain.interrupt(with: .greet, duration: lines.count > 1 ? 5.5 : 3)
        beginBehavior(.greet)
        for (i, line) in lines.enumerated() {
            Effects.speech(line, on: backend.node, height: backend.size.height, delay: Double(i) * 2.6)
        }
    }

    /// Stays paused until the screen is both unlocked and awake.
    private func updatePaused() {
        setPaused(screenLocked || screensAsleep)
    }

    func setPaused(_ paused: Bool) {
        guard paused != self.paused else { return }
        self.paused = paused
        overlays.setPaused(paused)
        if paused {
            timer?.invalidate()
            timer = nil
            timerFPS = 0
        } else {
            lastTick = CACurrentMediaTime()
            setRate(30)
        }
    }

    private func setRate(_ fps: Int) {
        guard fps != timerFPS else { return }
        timerFPS = fps
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / Double(fps), repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        overlays.setFPS(fps)
    }

    func refreshWorld() {
        if body.apply(world.refresh()) == .startedFalling { fell() }
    }

    func screensChanged() {
        world.setScreens(NSScreen.screens.map(\.visibleFrame))
        overlays.rebuild()
        overlays.setPaused(paused)
        if timerFPS > 0 { overlays.setFPS(timerFPS) }
        body.clamp(to: world.screens)
        updateHome()
        ball?.setScreens(world.screens)
    }

    /// Called when the floor disappears under the corgi.
    func fell() {
        Effects.floatEmoji("❗", on: backend.node, height: backend.size.height)
        brain.interrupt(with: .fall, duration: 5)
        beginBehavior(.fall)
    }

    func beginBehavior(_ b: Behavior) {
        if b != .ballChase { endBall() }
        if chaseMe && b != .chaseMe && b != .dangle { chaseMe = false }
        if needs.state.isAsleep != b.countsAsSleep { needs.setAsleep(b.countsAsSleep) }
        executor.speedScale = needs.isLow(.happiness) ? 0.6 : 1
        executor.begin(b, body: body, world: world, cursor: NSEvent.mouseLocation)
        if b == .ballChase { spawnBall() }
    }

    /// The executor says the current behavior is done.
    func stepFinished() {
        if brain.current == .ballChase && executor.carryingBall {
            brain.interrupt(with: .playBallHome, duration: Double.random(in: 8...15))
            beginBehavior(.playBallHome)
            return
        }
        brain.finishCurrent()
    }

    func feed() {
        wake()
        boredom.noteInteraction()
        brain.interrupt(with: .eat, duration: 4)
        beginBehavior(.eat)
        needs.feed()
        Effects.floatEmoji("🍖", on: backend.node, height: backend.size.height)
    }

    func bath() {
        wake()
        boredom.noteInteraction()
        brain.interrupt(with: .bath, duration: 4)
        beginBehavior(.bath)
        needs.bath()
        Effects.floatEmoji("🫧", on: backend.node, height: backend.size.height, count: 5)
    }

    func nap() {
        boredom.noteInteraction()
        brain.interrupt(with: .sleep, duration: 120)
        beginBehavior(.sleep)
    }

    /// Throws a ball that flies around the screen. The corgi chases it, carries it home, and plays.
    func playBall() {
        wake()
        boredom.noteInteraction()
        brain.interrupt(with: .ballChase, duration: 30)
        beginBehavior(.ballChase)
    }

    /// Menu toggle. On: roam freely and dodge the cursor. Off: fall to the floor and go home.
    func setChaseMe(_ on: Bool) {
        guard on != chaseMe else { return }
        boredom.noteInteraction()
        if on {
            wake()
            brain.interrupt(with: .chaseMe, duration: .infinity)
            beginBehavior(.chaseMe)
            chaseMe = true
        } else {
            chaseMe = false
            brain.interrupt(with: .goHome, duration: 30)
            beginBehavior(.goHome)
        }
    }

    private func wake() {
        if brain.current.countsAsSleep { brain.finishCurrent() }
        if needs.state.isAsleep { needs.setAsleep(false) }
    }

    private func spawnBall() {
        endBall()
        let b = Ball(start: CGPoint(x: body.position.x, y: body.position.y + 60), screens: world.screens)
        ball = b
        let node = Effects.makeBall()
        ballNode = node
        overlays.place(node, global: b.position)
        executor.ballPosition = b.position
        boredom.noteInteraction()
    }

    /// The executor reached the ball: +25 happiness and the ball moves to the corgi's mouth.
    private func ballCaught() {
        needs.play()
        boredom.noteInteraction()
        Effects.floatEmoji("❤️", on: backend.node, height: backend.size.height, count: 3)
        ball = nil
        executor.ballPosition = nil
        if let node = ballNode {
            node.removeFromParent()
            node.position = CGPoint(x: body.facingRight ? 26 : -26, y: 30)
            backend.node.addChild(node)
        }
    }

    private func stepBall(dt: TimeInterval) {
        guard let b = ball else { return }
        b.step(dt: dt)
        if b.popped {
            if let node = ballNode, let scene = node.parent {
                let pop = SKLabelNode(text: "💥")
                pop.fontSize = 22
                pop.position = node.position
                scene.addChild(pop)
                pop.run(.sequence([.fadeOut(withDuration: 0.6), .removeFromParent()]))
            }
            endBall()
            return
        }
        executor.ballPosition = b.position
        if let node = ballNode { overlays.place(node, global: b.position) }
    }

    private func endBall() {
        ballNode?.removeFromParent()
        ballNode = nil
        ball = nil
        executor.ballPosition = nil
    }

    /// Seconds since any keyboard or mouse event. Needs no permission.
    private var userIdleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    private var restBusy: Bool {
        dragging || chaseMe || body.mode == .held || body.mode == .roaming || brain.current == .ballChase
    }

    private func updateRest(dt: TimeInterval, now: CFTimeInterval) {
        let fullScreen = isFullScreen(frontWindow: world.windows.first?.frame,
                                      screenFrames: NSScreen.screens.map(\.frame))
        switch rest.update(dt: dt, idleSeconds: userIdleSeconds, fullScreen: fullScreen, busy: restBusy) {
        case .startYawn?:
            brain.interrupt(with: .yawn, duration: .infinity)
            beginBehavior(.yawn)
        case .fallAsleep?:
            brain.interrupt(with: .idleSleep, duration: .infinity)
            beginBehavior(.idleSleep)
        case .wake?:
            if brain.current == .yawn || brain.current == .idleSleep {
                brain.finishCurrent()
                needs.setAsleep(false)
                animOverride = (.wiggle, now + 0.8)
            }
        case nil:
            break
        }
    }

    private func updateHover(dt: TimeInterval, cursor: CGPoint) {
        let blocked = dragging || pressPoint != nil || body.mode != .grounded
            || brain.current.countsAsSleep || brain.current == .yawn
        if hover.update(dt: dt, hovering: hitRect.contains(cursor), blocked: blocked) { hoverPet() }
    }

    private func hoverPet() {
        boredom.noteInteraction()
        if needs.pet() {
            Effects.floatEmoji("❤️", on: backend.node, height: backend.size.height, count: 2)
            animOverride = (.happy, CACurrentMediaTime() + 0.8)
        }
    }

    /// Emoji props for idle activities until the art pack has them.
    private func updateProp() {
        let want = body.mode == .grounded ? Self.props[brain.current] : nil
        guard want != propEmoji else { return }
        prop?.removeFromParent()
        prop = nil
        propEmoji = want
        guard let want else { return }
        let p = Effects.makeProp(want)
        let side: CGFloat = body.facingRight ? 1 : -1
        let w = backend.size.width, h = backend.size.height
        switch brain.current {
        case .music: p.position = CGPoint(x: side * w * 0.35, y: h * 0.7)
        case .watchTV: p.position = CGPoint(x: side * (w / 2 + 26), y: 0)
        case .playBallHome:
            p.position = CGPoint(x: side * (w / 2 + 6), y: 0)
            p.run(.repeatForever(.sequence([.moveBy(x: 0, y: 16, duration: 0.25), .moveBy(x: 0, y: -16, duration: 0.25)])))
        default: p.position = CGPoint(x: side * (w / 2 + 2), y: 2)
        }
        backend.node.addChild(p)
        prop = p
    }

    func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now
        needs.tick()
        updateRest(dt: dt, now: now)

        home.observe(body.position)
        let canHop = !world.reachableSegments(from: body.position, maxJumpUp: body.config.maxJumpUp,
                                              maxJumpAcross: body.config.maxJumpAcross).isEmpty
        let ctx = BrainContext(needs: needs.state, lowThreshold: needs.config.lowThreshold, canHop: canHop,
                               atHome: home.isHome(body.position), secondsAwayFromHome: home.secondsAway,
                               bored: boredom.isBored(needs.state))
        if let next = brain.update(dt: dt, ctx) { beginBehavior(next) }

        let cursor = NSEvent.mouseLocation
        updateHover(dt: dt, cursor: cursor)
        stepBall(dt: dt)
        if executor.step(brain.current, body: body, world: world, cursor: cursor) { stepFinished() }
        if let event = body.step(dt: dt, world: world) {
            if executor.handle(event, behavior: brain.current, body: body) { stepFinished() }
            if event == .landed {
                animOverride = (.land, now + 0.25)
                if brain.current == .fall { brain.finishCurrent() }
            }
            if event == .startedFalling { fell() }
        }
        body.clamp(to: world.screens)

        overlays.place(globalFeet: body.position)
        backend.setFacing(right: body.facingRight)
        updateAnimation(now)
        if brain.current.countsAsSleep && now - lastZzz > 2 {
            lastZzz = now
            Effects.floatEmoji("💤", on: backend.node, height: backend.size.height * 0.8)
        }
        if body.mode == .held && now - lastSweat > 0.6 {
            lastSweat = now
            Effects.floatEmoji("💦", on: backend.node, height: backend.size.height * 0.9)
        }
        updateProp()
        debug.update(world: world, hitRect: hitRect, behavior: brain.current, overlays: overlays)
        overlays.setClickThrough(!(body.mode == .held || hitRect.contains(cursor)))
        setRate(body.isMoving || body.mode == .held || animOverride != nil ? 30 : 10)
    }

    private func updateAnimation(_ now: CFTimeInterval) {
        if let o = animOverride, o.until <= now { animOverride = nil }
        let state = animOverride?.state
            ?? animState(for: brain.current, mode: body.mode, isMoving: body.isMoving,
                         isRunning: body.isRunning, carrying: executor.carryingBall)
        if state != currentAnim {
            currentAnim = state
            backend.play(state)
        }
    }
}

extension PetController: SceneInputHandler {
    func mouseDown(at global: CGPoint) {
        pressPoint = global
        dragging = false
    }

    func mouseDragged(to global: CGPoint) {
        guard let start = pressPoint else { return }
        if !dragging && hypot(global.x - start.x, global.y - start.y) > 4 {
            dragging = true
            boredom.noteInteraction()
            body.pickUp()
            brain.interrupt(with: .dangle, duration: .infinity)
            beginBehavior(.dangle)
        }
        if dragging {
            body.moveHeld(to: CGPoint(x: global.x, y: global.y - backend.size.height * 0.8))
        }
    }

    func mouseUp(at global: CGPoint) {
        defer {
            pressPoint = nil
            dragging = false
        }
        if dragging {
            body.release()
            if chaseMe {
                brain.interrupt(with: .chaseMe, duration: .infinity)
                beginBehavior(.chaseMe)
            } else {
                brain.interrupt(with: .goHome, duration: 30)
                beginBehavior(.goHome)
            }
        } else if pressPoint != nil {
            pet()
        }
    }

    func rightMouseDown(_ event: NSEvent, in view: NSView) {
        onRightClick?(event, view)
    }

    func pet() {
        boredom.noteInteraction()
        if chaseMe {
            if needs.catchPet() {
                Effects.floatEmoji("❤️", on: backend.node, height: backend.size.height, count: 4)
                animOverride = (.happy, CACurrentMediaTime() + 0.8)
            }
            return
        }
        if brain.current.countsAsSleep {
            brain.finishCurrent()
            needs.setAsleep(false)
        }
        if needs.pet() {
            Effects.floatEmoji("❤️", on: backend.node, height: backend.size.height, count: 3)
            animOverride = (.wiggle, CACurrentMediaTime() + 0.8)
        }
    }
}
#endif
```

What changed against Task 24's version: the fetch code listed above is gone; `chaseMe`, `boredom`, `ball: Ball?`, `ballNode`; `setChaseMe` (on: roam with `chaseMe`; off: `goHome`, which ends roaming so it falls first); `beginBehavior` ends the ball when leaving `ballChase`, turns `chaseMe` off for any behavior other than `chaseMe` and `dangle`, and spawns the ball for `ballChase` (also when the brain picks it from boredom); `stepFinished` turns a finished carry into `playBallHome`; `ballCaught`, `stepBall` (moves the node across overlays, pops at 30s), `endBall`; `restBusy` includes `chaseMe`; `bored:` in `BrainContext`; `carrying:` in `animState`; drag release during Chase Me resumes roaming; a click during Chase Me is a catch (`needs.catchPet()`, hearts, `happy`); `boredom.noteInteraction()` in every interaction; `screensChanged()` calls `ball?.setScreens(world.screens)`.

- [ ] **Step 4: Run and verify (needs Mac)**

Run: `swift build && swift test && ./scripts/bundle.sh && open build/DesktopCorgi.app`
Expected:
- 110 tests pass.
- 🐶 menu and right-click menu show "🏃 Chase Me" under Play Ball, checked while on.
- Chase Me on: the corgi floats free (no gravity) and runs between random spots on all screens, never under the menu bar. Move the cursor within about 150pt: it darts away. Click it: hearts, `happy`, happiness +10 (shared 10 per minute limit), and the chase goes on. Drag it and let go: it keeps roaming. Chase Me off: it falls to the floor below and goes home.
- Chase Me on, then put an app in full screen: no sleep. Turn Chase Me off: it falls, then sleeps. Leave full screen: it wakes.
- Play Ball: a red ball flies around the screens on a smooth path. The corgi roams after it, grabs it (hearts), flies home holding it, drops to the floor, and kicks ⚽️ for 8-15s. Dragging the corgi mid-chase removes the ball right away. To see the 30s pop, temporarily add `b.speed = 400` after `let b = Ball(...)` in `spawnBall()` (faster than the corgi), check that the ball pops with 💥 and the corgi drops and picks something else, then remove the line.
- With two monitors, unplug the one the ball is on: the ball reappears on the remaining screen.
- Leave the corgi alone (no pets, drags, menu) for 10 minutes while happiness is over 50 and energy over 40: it soon starts a ball chase on its own. Move the mouse now and then so idle sleep (90s) does not kick in first. To test faster, temporarily add `controller.boredom.threshold = 30` after `controller.start()` in `AppDelegate`, then remove it.
On Linux: `swift build && swift test` still pass (110 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DesktopCorgi
git commit -m "feat: chase me mode and ball chase replace ledge fetch"
```

### Task 26: README states list and manual checklist for v2

**Files:**
- Modify: `README.md`
- Modify: `docs/MANUAL_CHECKLIST.md`

**Interfaces:** none (docs only).

- [ ] **Step 1: README**

In `README.md`, replace the `## Playing` list with:
```markdown
- Click: pet (hearts). Click a sleeping corgi to wake it.
- Rest the cursor on it: it gets petted too (hearts every 1.5s).
- Drag: pick it up (it gets scared), drop it anywhere. It runs home after landing.
- Home is the bottom-right of the main screen. It hangs out there reading, listening to music, watching TV, and kicking a ball.
- Leave the Mac alone for 90s, or go full screen: it yawns and naps until you're back.
- Right-click it or click 🐶 in the menu bar: Feed, Play Ball, Chase Me, Bath, Nap, Stats, Debug Overlay.
- Play Ball: a ball flies around the screen, the corgi chases it, carries it home, and plays with it. It also starts a game on its own when it's been bored for 10 minutes.
- Chase Me: the corgi runs around the screen and dodges your cursor. Click it to catch it. Turn it off and it goes home.
- Needs drop over time, also while the app is closed, but never below 15.
```

Replace the `- States: ...` bullet under "Using a bought art pack" with:
```markdown
- States: idle (required), walk, run, sit, sleep, eat, beg, dangle, fall, land, wiggle, bath, fetch, wave, back, read, readSleep, music, watch, yawn, scared, happy, holdBall, kick, roam. Missing ones use idle.
- What the newer states are for: `wave` greeting and fidget, `back` turned around, `read` reading a book, `readSleep` dozing over the book, `music` listening with headphones, `watch` watching TV, `yawn` before an idle nap, `scared` while held, `happy` when hover-petted or caught, `holdBall` flying with the ball in its mouth, `kick` playing with the ball at home, `roam` free flight in Chase Me and ball chase. The built-in placeholder draws 📖 🎧 📺 ⚽️ props next to the corgi for read, music, watch, and kick; a pack's frames should include the prop.
```

- [ ] **Step 2: Manual checklist**

In `docs/MANUAL_CHECKLIST.md`:
- Under `## Input`, replace `- [ ] Drag: dangles, follows cursor, lands where dropped.` with `- [ ] Drag: scared shiver with 💦, follows cursor, lands where dropped, then runs home.` and replace `- [ ] Feed, Bath, Nap, Play Ball each do their thing. Fetch brings the ball back.` with `- [ ] Feed, Bath, Nap each do their thing.`
- Under `## Screens and Spaces`, replace `- [ ] Full screen app: corgi hidden, back when leaving full screen.` with `- [ ] Full screen app: corgi visible on the full screen Space and asleep, awake again after leaving full screen.`
- Under `## Persistence`, replace `- [ ] Away more than 1 hour: 👋 greeting.` with `- [ ] Every launch: wave + "Hi!" bubble. Away more than 1 hour: a second "Missed you!" bubble.`
- Add a new section before `## Persistence`:
```markdown
## Companion (v2)
- [ ] Home: within a few minutes the corgi settles at the bottom-right of the main screen and stays there most of the time.
- [ ] Idle activities at home: 📖 read (sometimes dozes with 💤), 🎧 music, 📺 TV, ⚽️ kick, wave, turn around.
- [ ] Hover: cursor resting on it for 0.4s gives hearts, again every 1.5s, max 10 a minute together with clicks. No hover pets while it sleeps.
- [ ] Idle sleep: no input for 90s, it yawns then sleeps. Any key or mouse move wakes it with a wiggle.
- [ ] Idle sleep never starts while you hold the corgi or while Chase Me or a ball chase is on.
- [ ] Chase Me: floats and runs between spots, dodges the cursor within about 150pt, click catches it (hearts). Off: falls and goes home.
- [ ] Full screen during Chase Me: no sleep until Chase Me is turned off.
- [ ] Play Ball: ball flies around, corgi catches it, carries it home, kicks it. Uncaught ball pops after 30s.
- [ ] Unplug the monitor the ball is on: the ball comes back on the remaining screen.
- [ ] Unplug or change the main monitor: home moves to the bottom-right of the new main screen.
- [ ] Bored for 10 minutes (happy and rested): it starts a ball chase by itself.
```

- [ ] **Step 3: Run the checklist**

Go through the new and changed checklist items with the bundled app (`./scripts/bundle.sh && open build/DesktopCorgi.app`). Fix anything that fails before committing. `swift test` still passes (110 tests).

- [ ] **Step 4: Commit**

```bash
git add README.md docs/MANUAL_CHECKLIST.md
git commit -m "docs: v2 companion states and checklist"
```
