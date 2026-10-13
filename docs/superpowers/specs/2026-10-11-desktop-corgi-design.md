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
- Stays visible on full screen Spaces (`.fullScreenAuxiliary`); the corgi sleeps there (see v2).
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
- Greeting plays on every launch: wave + "Hi!" bubble, plus "Missed you!" if away more than 1 hour (see v2).
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

## v2: Companion features

Added 2026-10-13, based on a reference reel of another desktop corgi. Only the behaviors are copied. The art stays original.

### Home spot
- Home is the bottom-right of the main screen's visible frame (above the Dock): `x = visibleFrame.maxX - 80`, on the ground segment.
- New behavior `goHome`: walks (or runs if far) to home. If home is on another segment, it hops or leaps toward it, the same way `hopToWindow` does.
- Brain: `goHome` weight grows with time away from home (0 at home, +1 per minute away, capped at 8). Wander behaviors (`walk`, `zoomies`, `hopToWindow`) get half weight while at home so it mostly hangs out there.
- After a drag ends (landed), the corgi always runs home.

### Speech bubbles and greeting
- `Effects.speech(text)` shows a rounded bubble above the corgi for 2.5s.
- On every launch: `greet` = wave animation + "Hi!". If away more than 1 hour, a second bubble says "Missed you!".

### Idle activities and fidgets
- New autonomous behaviors, weighted higher at home: `read`, `music`, `watchTV`, `wave`, `turnAround`, `playBallHome`.
- Durations: read 20-60s, music 20-60s, watchTV 30-90s, wave 2s, turnAround 3-5s, playBallHome 8-15s.
- `read` turns into `readSleep` (dozing over the book) after 15s with 30% chance, or right away if energy is low. It counts as sleeping for energy.
- Placeholder props until the art pack has them: 📖 (read), 🎧 (music), 📺 (watchTV), ⚽️ (playBallHome) drawn next to the corgi.

### Idle sleep (user inactivity)
- The app reads seconds since the last keyboard or mouse event (`CGEventSource.secondsSinceLastEventType`, no permission needed).
- At 90s idle the corgi plays `yawn` (2s), then `sleep` until there is any input. On input it wakes (short `wiggle`) and the brain picks again.
- This is separate from energy-based napping. Idle sleep also counts as asleep for energy.

### Full screen
- Full screen = the frontmost window's frame equals a screen's full frame. While full screen is active the corgi sleeps where it is. It wakes when full screen ends.

### Hover pet
- Cursor resting on the corgi's hit box for 0.4s (not dragging) pets it: `happy` animation + hearts. Continued hover repeats every 1.5s. Same 10 pets/minute limit as clicks.

### Scared drag
- While held, the animation is `scared` with 💦. After release and landing, `goHome`.

### Chase Me mode
- Menu toggle "Chase Me". While on, the body is in `.roaming` mode: no gravity, no floors, moves freely within the screens' visible frames at run speed toward random waypoints.
- If the cursor gets within 150pt, it picks a waypoint away from the cursor (dodge).
- Clicking it while roaming "catches" it: hearts + happiness +10 (counts as a pet for the rate limit).
- Turning the mode off: it falls to the nearest floor and goes home.

### Ball chase (replaces v1 ledge fetch)
- A ball flies around the visible screen area on a smooth random path (new waypoint every 1-2s).
- The corgi roams after it. Within 30pt it catches the ball, carries it home (roaming), drops to the floor, then does `playBallHome`. Happiness +25 on catch.
- Triggered by the Play Ball menu item, or by boredom: no user interaction with the corgi for 10 minutes while happiness > 50 and energy > 40 (boredom adds weight to `ballChase`).
- Gives up after 30s (the ball "pops").

### New animation states
`wave`, `back`, `read`, `readSleep`, `music`, `watch`, `yawn`, `scared`, `happy`, `holdBall`, `kick`, `roam`. Missing ones fall back to `idle` as before. The README lists them for anyone making or commissioning art.

## Edge cases

- Multiple monitors: one overlay per screen, corgi can walk across touching edges.
- Spaces: overlay joins all Spaces.
- Full screen apps: corgi stays visible and sleeps until full screen ends.
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

## v3: Cuter corgi and extras

### Look
- Original "chibi bean" corgi, drawn in code in `PlaceholderBackend` (no copied art). Reference mockup: card "A. Chibi bean" in `~/corgi-preview/styles.html`.
- Huge round head, tiny loaf body, stubby paws, big glossy eyes with two white highlights, pink blush ovals, small pink tongue, cream muzzle and chest blaze, orange fur (about #f2a541), pink inner ears.
- Small constant life: blink every 3-6s (random), an ear twitch now and then, tail wag (faster when happiness > 70), gentle breathing bob, squash on landing, head tilt while the cursor hovers.
- Every `AnimState` gets its own pose and expression in this style (sleep is curled up with closed curved eyes, scared has wobbly eyes and a sweat drop, happy has sparkly eyes, and so on).
- Drawn props replace v2 emoji where the pose draws them (book, headphones, TV, ball). Emoji stay only where nothing is drawn.
- Stays inside roughly the current hit box (about 96x80pt) with feet at the node origin.

### Name
- Default name "Corgi". On the first launch of v3 (`askedForName == false`) a rename prompt shows (text field, OK and Later). `askedForName` becomes true either way.
- "Rename…" menu item any time.
- Name input is trimmed, capped at 20 characters, and an empty result keeps the old name.
- The name shows on a small collar tag (first 6 characters, then "…" if longer) and in the Stats title as "<Name> · Level N".

### Hats
- Hats submenu with radio items: None, Bow, Party Hat, Beanie, Flower Crown, Santa Hat.
- Drawn in code and placed on the head in every pose (follows head offset, rotation, and facing). The choice is saved.

### Sounds
- "Sounds" menu toggle, off by default, saved.
- Only built-in macOS system sounds (`NSSound(named:)`) at volume 0.3: "Pop" on pet, "Tink" on ball catch, "Purr" when it falls asleep (at most once per sleep), "Bottle" on eat. No downloaded audio.

### Mood bubbles
- When a need is below the low threshold (30), a thought bubble shows "💭" plus an emoji for the lowest need: hunger 🍖, cleanliness 🛁, energy 💤, happiness 🎾.
- The first bubble shows 10s after a need goes low, then about once every 60s.
- No bubbles while asleep, held, or roaming. Being blocked also resets the timer.

### Data
- `PetProfile` in CorgiCore (name, hat, soundsOn, askedForName), saved as `profile.json` next to `state.json` by `ProfileStore`.
- Missing file gives defaults. A corrupt file is moved to `profile.corrupt.json` and defaults are used. An unknown hat value decodes to none.
- Mood bubble timing is a pure CorgiCore unit (`MoodBubbles`) fed elapsed time, the needs state, and a blocked flag. It returns the need to show, if any.
- All of the above is unit tested.
