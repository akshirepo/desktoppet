# First Mac build

This is a macOS desktop pet: a Tamagotchi-style corgi that lives in the menu bar, walks along the screen bottom, and hops onto window title bars. It's Swift 5.9+ with SwiftPM, AppKit, SpriteKit and SwiftUI, for macOS 14+.

## Context
- The spec is docs/superpowers/specs/2026-10-11-desktop-corgi-design.md and the plan is docs/superpowers/plans/2026-10-11-desktop-corgi.md. All 17 plan tasks are already committed.
- Sources/CorgiCore is pure logic. Its 111 XCTest tests pass on Linux.
- Sources/DesktopCorgi is the Mac app layer. It was written on Linux with no Mac SDK, so it has NEVER been compiled. Every file in it is wrapped in `#if canImport(AppKit)`. Keep that gating so CorgiCore still builds on Linux.

## Steps
1. Run `swift build` and `swift test`. Show the user the first errors, then fix every compile error in Sources/DesktopCorgi. If Swift concurrency or MainActor errors show up, prefer marking the app-layer classes @MainActor and using MainActor.assumeIsolated in Timer and notification closures, rather than turning off checks.
2. Don't change CorgiCore behavior unless a test proves a bug. All 111 tests must still pass.
3. Run `./scripts/bundle.sh` and `open build/DesktopCorgi.app`. Check that the corgi appears, falls to the bottom of the screen, and that clicks off the corgi reach the apps underneath. Read the app's logs with `log show --last 5m --predicate 'process == "DesktopCorgi"'`.
4. Walk the user through docs/MANUAL_CHECKLIST.md one section at a time. Say exactly what to do and what they should see, wait for the answer, and fix anything that fails.
5. Commit each fix separately with a short one-line message. Don't push anywhere.

## Known gaps (not bugs, leave alone unless asked)
- The corgi can't walk straight across monitors. It can hop down or be dragged across.
- It doesn't pause drawing while hidden behind a full-screen app.
