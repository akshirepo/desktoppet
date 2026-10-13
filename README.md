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
- Rest the cursor on it: it gets petted too (hearts every 1.5s).
- Drag: pick it up (it gets scared), drop it anywhere. It runs home after landing.
- Home is the bottom-right of the main screen. It hangs out there reading, listening to music, watching TV, and kicking a ball.
- Leave the Mac alone for 90s, or go full screen: it yawns and naps until you're back.
- Right-click it or click 🐶 in the menu bar: Feed, Play Ball, Chase Me, Bath, Nap, Stats, Debug Overlay.
- Play Ball: a ball flies around the screen, the corgi chases it, carries it home, and plays with it. It also starts a game on its own when it's been bored for 10 minutes.
- Chase Me: the corgi runs around the screen and dodges your cursor. Click it to catch it. Turn it off and it goes home.
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

- States: idle (required), walk, run, sit, sleep, eat, beg, dangle, fall, land, wiggle, bath, fetch, wave, back, read, readSleep, music, watch, yawn, scared, happy, holdBall, kick, roam. Missing ones use idle.
- What the newer states are for: `wave` greeting and fidget, `back` turned around, `read` reading a book, `readSleep` dozing over the book, `music` listening with headphones, `watch` watching TV, `yawn` before an idle nap, `scared` while held, `happy` when hover-petted or caught, `holdBall` flying with the ball in its mouth, `kick` playing with the ball at home, `roam` free flight in Chase Me and ball chase. The built-in placeholder draws 📖 🎧 📺 ⚽️ props next to the corgi for read, music, watch, and kick; a pack's frames should include the prop.
- `anchor` is where the feet are, as a fraction of the frame: `[0.5, 0.0]` is bottom center.
- `scale` shrinks or grows every frame.
- Frames must face right. Mirror them if the pack faces left: `for f in */*.png; do sips -f horizontal "$f"; done`
- Packs often come as GIFs or sprite sheets. Turn them into frames with:
  - GIF: `ffmpeg -i walk.gif walk/%04d.png`
  - Sprite sheet (for example 128x128 cells): `magick sheet.png -crop 128x128 +repage walk/%04d.png`
  (`brew install ffmpeg imagemagick`)

Restart the app after changing the pack. If the pack fails to load, the app logs why and uses the built-in placeholder corgi:
`log show --last 5m --predicate 'process == "DesktopCorgi"'`
