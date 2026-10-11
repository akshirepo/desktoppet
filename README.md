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
