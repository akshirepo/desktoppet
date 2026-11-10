# DesktopPet

A little pixel-art pet that lives on your Mac. Pick a corgi or a sheep. It wanders along the bottom of your screen, hops onto windows, hangs off their edges, and has needs you look after: hunger, thirst, happiness, energy and cleanliness.

## Requirements

- macOS 14 or later
- Swift 6 toolchain: Xcode, or just the Command Line Tools (`xcode-select --install`)

## Install

```bash
git clone https://github.com/akshirepo/desktoppet.git
cd desktoppet
./scripts/bundle.sh
cp -R build/DesktopPet.app /Applications/
open /Applications/DesktopPet.app
```

The pet shows up in the bottom-right corner and its icon appears in the menu bar. There's no Dock icon.

The app isn't signed with a developer certificate. You built it yourself, so macOS runs it, but if you send the built app to someone else they'll need to right-click it and choose **Open** the first time.

To start it automatically, turn on **Launch at Login** in the menu. This only works once the app is in `/Applications`. If macOS asks, allow DesktopPet under System Settings > General > Login Items.

## Playing

- **Pet it:** click it, or rest your cursor on it. Hearts float up.
- **Pick it up:** drag it anywhere. Drop it next to a window and it holds on:
  - just above a window's top edge: sits on the edge with its legs dangling
  - just below the top edge: peeks over it, body hidden behind the window
  - under the bottom edge: hangs on with its front paws
  - next to a side edge: clings to the side

  It rides along when you move the window and lets go after a few minutes, or when the window closes.

  Drop it next to the left or right edge of a display and a brick pillar slides out from behind the edge, and it goes straight behind it. Near the floor it pokes its head and a front leg back out, one paw on the bricks. Higher up it hangs on behind a short section of wall with both paws hooked over the bricks. While it's hidden it stays quiet: no bubbles, hearts or walking around. It comes back out after 30 to 40 minutes and the pillar slides away; pick it up to end it early. Where two displays meet side by side there's no edge to hide behind, so it doesn't peek there.
- **Home:** the bottom-right corner of your desktop. It hangs out there reading, listening to music, watching TV and playing with its ball.
- **Idle:** leave the Mac alone for 90 seconds, or watch something full screen, and it falls asleep.
- **Needs:** they drop slowly, even while the app is closed. A thought bubble shows what it wants.
- **Little things to say:** speech and thought bubbles in each pet's own voice, like "Snack break?" when hungry or "My wool is fuzzy…" when the sheep wants a bath. It also says hi, thanks you after you help, and sometimes just keeps you company. The lines live in `Assets/Bubbles/messages.json` if you want to change them.
- **Daily routine:** what it does follows what just happened. Running around makes it thirsty and hungry, so after a chase it sits to catch its breath and then asks for water. While you're paying attention it stays close. Leave it alone for a while and it heads home for TV, a book or its ball, and after about 15 quiet minutes it comes over to ask you to play. It yawns before it sleeps and when it wakes up.
- **Eating and drinking:** the food and water bowls go down as it eats and drinks, from full to half to empty.
- **Smooth moves:** it doesn't jump between poses. It finishes its step before it stops, sits down and stands up, lies down to sleep, gets into the bath, picks up its book, puts on headphones and settles in front of the TV, with an animation for each move.
- **More than one display:** with external monitors connected it travels between them. It walks across where two displays meet side by side (hopping a step when one floor sits higher), leaps up or hops down between a laptop and a monitor stacked above it, and follows you across in **Chase Me**. It's drawn at the same physical size on every display.
- **Asking for help:** when a need gets low, now and then it comes over to your cursor and begs, with a bubble showing what it wants (food, a bath, play or a nap). Click it to give it that. Ignore it and it goes back to what it was doing and asks again later. Each need asks at most every 30 minutes, and never while you're away, in full screen, or busy with it. Turn it off with **Ask for Care** in the menu.

### Menu

Click the menu bar icon or right-click the pet:

- **Feed, Water, Play Ball, Chase Me, Bath, Nap**
- **Stats:** need levels and how long you've been together
- **Rename:** give the current pet a name
- **Character:** switch between the corgi and the sheep. Each pet has its own name and stats.
- **Ask for Care:** let it ask for what it needs: coming to your cursor, begging, and "I'm hungry" bubbles. Turn it off and it stops asking; its needs still show in **Stats**. On by default.
- **Sounds:** cartoony sound effects for petting, eating, baths, snoring, footsteps, hops and the ball. Off by default.
- **Launch at Login**

## Custom art

The corgi and sheep art is built into the app. To use your own, put a pack folder in `~/Library/Application Support/DesktopPet/` named `CorgiPack` or `SheepPack`. It overrides the built-in art for that character.

A pack is one folder per animation state with numbered PNG frames, plus a `manifest.json`. See `Assets/Packs/CorgiPack/manifest.json` for the format and the full list of states. Frames should face right; the app mirrors them when the pet walks left. Missing states fall back to `idle`.

A pack can also have `bridges`: one-shot transition animations between poses, like `stand>sit`, `sit>sleep`, `enter:watch` (getting into an activity from the standing or sitting pose) and `pair:walk>fetch`. Set `"reversed": true` to play a folder backwards, for example `sit>stand` from the `stand>sit` frames. Without bridges the pet switches poses directly. A state can set `"posture"` (`stand`, `sit` or `lie`) and `"scale"` (a size correction for a pose drawn bigger or smaller than the rest).

Edge peeking uses the states `peekEdge` (on the floor) and `holdEdge` (hanging on higher up) with the bridges `enter:peekEdge`, `exit:peekEdge`, `enter:holdEdge` and `exit:holdEdge`. Draw them facing right, peeking in from the **left** screen edge, with the same canvas size and anchor as `idle`. `enter:peekEdge` starts on the idle frame and ends on the first `peekEdge` frame; `enter:holdEdge` starts on the first `scared` frame (the pose it has while you carry it) and ends on the first `holdEdge` frame. The exits can be the entries reversed. A pack without these states just lands normally when dropped by an edge.

The wall it hides behind is set with `"edgeWall": {"folder": "edgeWall", "width": 64, "height": 272, "faceColumn": 16}` (canvas pixels). The folder holds `cap.png` (the top of the wall) and `tile.png` (repeated below it down to the floor), both `width` wide and drawn for a left edge: outer side on column 0, inner face on the right. `height` is how far the wall top is above the pet's feet. `faceColumn` is the column of the peek frames that sits on the wall's inner face: cut the body there, and paws drawn left of it hook over the bricks (the wall is drawn behind the pet). The app stands the wall on the display edge and mirrors everything at a right edge. Without `edgeWall`, canvas column 0 of the peek frames is the screen edge itself.

## Development

```bash
swift build          # build
swift test           # tests for the core logic (needs Xcode for XCTest on macOS)
```

- `Sources/CorgiCore`: all the logic (needs, behavior, movement, window edges) with no UI. It also builds and tests on Linux.
- `Sources/DesktopPet`: the macOS app (AppKit + SpriteKit).
- `Assets/`: the pet art, the doodle icons and the sound effects.
- `scripts/sounds/`: the scripts that synthesize the sound effects from scratch.

## License

The code is under the MIT License, see [LICENSE](LICENSE). The artwork and sounds in `Assets/` (corgi, sheep, doodle icons and sound effects) are not covered by the MIT License and all rights are reserved, see [ASSETS-LICENSE](ASSETS-LICENSE).
