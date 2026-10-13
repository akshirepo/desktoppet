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
- [ ] Drag: scared shiver with 💦, follows cursor, lands where dropped, then runs home.
- [ ] Right-click and 🐶 menus both work.
- [ ] Feed, Bath, Nap each do their thing.

## Screens and Spaces
- [ ] Switching Spaces: corgi still there.
- [ ] Full screen app: corgi visible on the full screen Space and asleep, awake again after leaving full screen.
- [ ] Second monitor: corgi can be dragged there and walks on its bottom.
- [ ] Unplug the monitor the corgi is on: it reappears on the remaining screen.

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

## Persistence
- [ ] Quit and relaunch: stats roughly the same.
- [ ] Every launch: wave + "Hi!" bubble. Away more than 1 hour: a second "Missed you!" bubble.
- [ ] Put `{bad` in `state.json`, relaunch: fresh corgi, `state.corrupt.json` exists.
- [ ] Lock screen: near 0% CPU, corgi in the same spot after unlock.
