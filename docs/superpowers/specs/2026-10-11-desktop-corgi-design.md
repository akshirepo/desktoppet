# Desktop Corgi: Design Spec

Date: 2026-10-11
Status: Draft for review

## Goal

A Tamagotchi-style cartoon corgi that lives on my Mac screen. It walks along the bottom of the screen, hops onto the top edges of open windows, and has needs I look after. It should feel alive and cute, never guilt-trippy, and stay out of the way when I'm working.

### Success criteria

- Corgi walks, sleeps, begs, and perches on windows without me doing anything.
- I can pet it, drag it, feed/play/bathe it, and it sometimes chases my cursor.
- Needs persist across restarts and drop gently while the app is closed (never below the floor).
- Clicks anywhere except the corgi go through to the app underneath.
- Low idle CPU (target under 2% while sleeping/idle on Apple Silicon).

## Decisions

| Topic | Decision |
|---|---|
| Platform | macOS only (target macOS 14+) |
| Stack | Swift, SpriteKit for the pet, SwiftUI for menu/stats |
| Art | Smooth cartoon, from a bought/downloaded asset pack |
| Animation format | PNG frame sequences in v1; Animator is pluggable so Rive can be added later |
| Movement | Walks on screen bottom + hops onto window top edges |
| Time away | Needs decay while closed, clamped at a floor of 15 |
| App presence | Menu bar only (no Dock icon), launch at login in v1 |

## Architecture

Each unit has one job and talks to others through small interfaces.

### OverlayWindow
- One borderless, transparent `NSPanel` per screen, level above normal windows, `canJoinAllSpaces`, `ignoresMouseEvents` toggled per frame based on whether the cursor is over the corgi's hit box.
- Hides when the frontmost app is full screen.
- Hosts an `SKView` with a transparent background.

### World
- Builds the walkable "floor" segments: each screen's visible bottom (above the Dock) plus the top edge of each visible on-screen window.
- Source: `CGWindowListCopyWindowInfo(.optionOnScreenOnly)`, layer 0 windows only. Window bounds need no Accessibility or Screen Recording permission.
- Refreshes every 0.5s and on `NSWorkspace.didActivateApplicationNotification`.
- Tracks which window id the corgi stands on. If that window moves, the corgi moves with it. If it disappears or minimizes, the corgi falls.
- Interface: `segments() -> [FloorSegment]`, `segment(under point) -> FloorSegment?`, `reachableSegments(from:) -> [FloorSegment]`.
- Window source is behind a `WindowListProvider` protocol so tests can feed fake window lists.

### Needs
- Four stats, 0 to 100: hunger, happiness, energy, cleanliness.
- Decay per hour (config file, `needs.json` defaults):

| Need | Rate/hr | Restored by |
|---|---|---|
| Hunger | -8 | Feed +40 |
| Happiness | -5 | Pet +5 (max 10 pets/min), Play ball +25 |
| Energy | -6 awake, +20 asleep | Nap or auto-sleep |
| Cleanliness | -3 | Bath +60 |

- Low threshold is 30. Floor is 15 for offline catch-up, so a long absence leaves it sad and hungry but never "dead".
- On launch: compute elapsed time since `lastSaved`, apply decay, clamp to the floor.
- Persisted as JSON in `~/Library/Application Support/DesktopCorgi/state.json`. Saved every 60s and on quit. Corrupt file: back it up as `state.corrupt.json`, start fresh at 70 for all stats, log a warning.
- Also tracks `careXP` (total care actions) to derive a level shown in the stats popover.
- Uses an injectable `Clock` so tests control time.

### Brain
- Every 3 to 8 seconds (or when a behavior ends), scores every behavior and picks one by weighted random.
- Weights come from needs: low energy boosts `sleep`, low hunger boosts `beg`, high happiness + energy boost `zoomies`, `chaseCursor`, `hopToWindow`.
- User actions (feed, play, bath, nap, drag) interrupt and override the current behavior.
- Greeting behavior plays on launch if away more than 1 hour.
- Random source injected (seeded in tests).

Behaviors: `idle`, `walk`, `sit`, `sleep`, `zoomies`, `chaseCursor` (gives up after ~5s), `hopToWindow`, `beg`, `eat`, `fetch`, `bath`, `dangle`, `fall`, `greet`.

### Body
- Simple custom physics (not SpriteKit physics bodies): position, velocity, gravity, ground snapping to the current floor segment.
- Jump arcs computed to land on a target segment. Only segments within a max jump height/distance count as reachable.
- Dangle: while dragging, the corgi hangs from the cursor with a small swing. On release it falls and lands.
- Keeps the corgi within visible screen bounds and can cross between monitors where edges touch.

### Animator
- Protocol `AnimationBackend` with `play(state:, loop:)`, `setFacing(left/right)`, `currentFrameSize`.
- v1: `FrameSequenceBackend` reads an asset pack folder:

```
CorgiPack/
  manifest.json
  idle/0001.png ...
  walk/0001.png ...
```

- `manifest.json` maps each state to `{ folder, fps, loop, anchor: [x, y] }`. Anchor is the feet point.
- Missing state falls back to `idle` and logs once.
- Required states: idle, walk, run, sit, sleep, eat, beg, dangle, fall, land, wiggle, bath, fetch. Mood overlays (droopy ears, dirt specks, flies) are separate sprite layers if the pack has them, otherwise skipped.
- Later: `RiveBackend` behind the same protocol.

### Input
- Left click on corgi: pet. Plays wiggle, floats hearts, happiness +5 (rate limited).
- Click and drag: pick up (`dangle`), release to drop.
- Right click on corgi, or the menu bar icon: menu with Feed, Play ball, Bath, Nap, Stats, Debug overlay, Quit.
- Play ball: a ball sprite gets thrown from the corgi's position, corgi runs to fetch it and brings it back.
- Stats: SwiftUI popover with four bars, level, and time together.

## Edge cases

- Multiple monitors: one overlay per screen, corgi can walk across touching edges.
- Spaces: overlay joins all Spaces.
- Full screen apps: corgi hides until full screen ends.
- Perched window closes/minimizes: corgi falls with a surprised animation.
- Dropped off-screen: clamped back into the nearest visible area.
- Screen locked or display asleep: rendering paused, needs still tracked by wall clock.
- Battery: 30fps while moving, 10fps while idle/sleeping, paused when hidden.

## Testing

- Unit tests (XCTest):
  - Needs: decay math, floor clamp, offline catch-up, rate limits, save/load round trip, corrupt file recovery.
  - Brain: weighting given needs, deterministic picks with a seeded random, interrupts.
  - World: floor segments and reachability from fake window lists, ride-along when a window moves, fall when it disappears.
  - Animator: manifest parsing and fallback to idle.
- Manual checklist for physics feel, click-through, multi-monitor, full screen, and Spaces.
- Debug overlay (menu toggle) draws floor segments, corgi hit box, and current behavior name.

## Build note

Development has to happen on the Mac (Xcode). The Linux cloud desktop can't build or run a macOS app.

## Out of scope for v1

Sounds, multiple pets, syncing between machines, Rive backend, custom art creation.
