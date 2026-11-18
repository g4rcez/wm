---
title: "Troubleshooting and limits"
description: "Fixes for common problems, and what wm cannot do."
group: Guides
order: 3
---
## Troubleshooting

Run `wm doctor` first. It checks the config, the daemon, the Accessibility and Screen Recording permissions and the login item,
and says what to do for each one that is not ok. `wm config check` loads the config alone, and shows the line of an error.

- **Nothing happens when I press a key.** Check that wm has Accessibility permission and that `wm daemon status` says it
  runs. Without a config, wm has no key binds.
- **My config has `workspaces = "native"` and no key works.** wm no longer has native macOS desktops, so that value is an
  error and the config does not load. Delete the line, or set `workspaces = "emulated"`.
- **I rebuilt and macOS asks for permissions again.** The build was signed ad hoc. See [Signing](/docs/install#signing).
- **The menu bar icon is missing.** Switch on `wm` in System Settings > Menu Bar. `wm daemon status` says
  `menu bar: hidden by macOS` when the icon is not on screen.
- **The switcher shows icons and not pictures.** Grant Screen Recording, or set `switcher = { thumbnails = false }`.
- **A window hides behind others, or stays out of the layout.** Some windows (dialogs, palettes) float by design. Use
  `wm window float` to toggle one, or add a rule.
- **My config has an error.** The old config stays active. The message is in the menu bar, in the output of
  `wm daemon reload` and in `wm logs`.
- **wm and another window manager fight.** Quit the other one. Quitting wm puts every hidden window back on screen.

## Limits

- Animations move real windows through the Accessibility API, one call per frame. Slow apps (Electron) can stutter, and a
  window with an AX call still running skips frames.
- wm cannot blur, fade or shadow other apps' windows.
- The border and the tab indicator are separate overlay windows above normal windows.
- A window with a minimum size larger than its tile overlaps its neighbours.
- Gestures with `mods` see only a modifier and a scroll direction, not the finger count. Gestures with `fingers` read the
  trackpad through the private MultitouchSupport framework. A macOS update can change it. When it cannot be loaded, the
  gestures stay off, and wm says so in the log (in a notification when the config has `trackpad = { enabled = true }`).
  macOS keeps its own gestures with three and with four fingers (Mission Control, Spaces, Exposé): turn the ones that you
  use in wm off in System Settings > Trackpad > More Gestures, or both act on the same swipe.
- When a display goes away (lid closed, display asleep, unplugged), its workspace keeps its windows, and they stay hidden.
  The display shows that workspace again when it comes back. Until then, `wm workspace N` shows it on another monitor.
