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
- Greeting plays on launch if away more than 1 hour.
- Coordinates: all `CorgiCore` geometry uses AppKit global coordinates (origin bottom-left of the primary screen, y up). Positions are the corgi's feet.
- Linux dev builds: `CorgiCore` must also build and test on Linux (Swift 6.4 at `~/.local/swift-6.4.0/usr/bin`). In `CorgiCore`, write `#if canImport(CoreGraphics)` / `import CoreGraphics` / `#endif` instead of a bare `import CoreGraphics`, and keep `Sources/CorgiCore/LinuxShims.swift` (created in Task 1) defining `CGVector` (Equatable, Hashable, `init(dx:dy:)`, `.zero`) inside `#if !canImport(CoreGraphics)`. Every file in `Sources/DesktopCorgi` is wrapped in `#if canImport(AppKit)` ... `#endif`; `main.swift` has an `#else` branch that prints "DesktopCorgi needs macOS". `swift test` must pass on Linux and macOS.

## Review Focus

- A window whose top edge is covered by a window in front of it: corgi must not stand on the hidden part. Test in Task 4.
- A maximized window whose top edge sits at the top of the visible screen: no perch there (corgi would overlap the menu bar). Test in Task 4.
- The system clock jumps backwards (manual time change, restored backup): elapsed time is treated as zero, stats never go up from decay. Test in Task 1.
- A window moves or closes while the corgi is being held or is mid-jump: no ride-along, no forced drop while held. Test in Task 6.
- A monitor is unplugged while the corgi is on it: corgi is clamped back onto a remaining screen. Test in Task 6.

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
