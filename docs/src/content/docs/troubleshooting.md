---
title: "Troubleshooting and limits"
description: "Fixes for common problems, and what wm cannot do."
group: Guides
order: 1
---
## Troubleshooting

Run `wm doctor` first. It checks the config, `shortcuts.toml`, the daemon and the permissions, and says what to do for each check that is not ok. `wm config check` loads the config alone and shows the line of an error.

- **Nothing happens when I press a key.** Check that wm has Accessibility permission and that `wm daemon status` says it runs. Without a config, wm has no key binds (`wm init`).
- **I rebuilt and macOS asks for permissions again.** The build was signed ad hoc. See [Signing](/docs/getting-started#signing).
- **The menu bar icon is missing.** Switch on `wm` in System Settings > Menu Bar. `wm daemon status` says `menu bar: hidden by macOS` when the icon is not on screen.
- **The switcher shows icons and not pictures, or `wm select` finds no text in a terminal.** Grant Screen Recording.
- **A window floats or stays out of the layout.** Dialogs and palettes float by design. Use `wm window float` to toggle one, or add a rule.
- **A shortcut from the Shortcuts window does nothing.** `wm doctor` says why in its `shortcuts` line: `init.lua` does not call `wm.shortcuts()`, `init.lua` binds the same keys later (it wins), or `shortcuts.toml` has an error.
- **My config has an error.** The old config stays active. The message is in the menu bar, in the output of `wm daemon reload` and in `wm logs`.
- **wm and another window manager fight.** Quit the other one. Quitting wm puts every hidden window back on screen.

## Limits

- Animations move real windows through the Accessibility API, one call per frame, so slow apps (Electron) can stutter. wm cannot blur, fade or shadow other apps' windows.
- `focus urgent` reads the Dock badge, so it works per app, only for apps that show a badge (Mail, Slack, Messages), and up to 2 seconds late. A Dock bounce without a badge cannot be seen. `urgent = { enabled = false }` stops the reading.
- A window with a minimum size larger than its tile overlaps its neighbours.
- Gestures with `mods` see a modifier and a scroll direction, not the finger count. Gestures with `fingers` use the private MultitouchSupport framework; if it cannot be loaded they stay off, and the log says so. Turn off macOS's own three- and four-finger gestures that you use in wm (System Settings > Trackpad > More Gestures), or both act on the same swipe.
- When a display goes away, its workspace keeps its windows hidden until the display comes back. Until then `wm workspace N` shows it on another monitor.
