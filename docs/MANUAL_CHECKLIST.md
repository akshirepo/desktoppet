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
