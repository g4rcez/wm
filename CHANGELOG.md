# Changelog

What changed for users in each release. `scripts/release.sh` publishes the section of a version as its release notes, and
refuses to release while `Unreleased` is empty.

## Unreleased

### Changed

- **Trackpad swipes that macOS uses are off in wm.** wm reads the trackpad next to macOS and cannot hide a swipe from it, so a
  3 or 4 finger swipe that macOS also uses (Mission Control, App Exposé, switching Spaces) does nothing in wm now, instead of
  both acting on it. On a Mac with the default settings that is every built-in swipe. Turn the macOS gesture off in System
  Settings > Trackpad > More Gestures to use it in wm. `wm doctor` and `wm list binds` show which swipes are off.
- **`wm://` URLs run only the commands that move the view, the focus and the layout.** Any other command, `window close` and
  `focus app --launch` need `url = { allow = { ... } }` in the config.
- **`layout balance` in the scrolling layout** also gives the windows of a stack the same height and puts the vertical zone
  back to its configured width.
- **Window titles stay out of the log** unless `WM_LOG_LEVEL=debug` is set on purpose; the log says how long a title is.
- **`wm config check` runs no program and changes no file**: `os.execute`, `io.popen`, file writes and native modules are
  off while a config is only checked.
- Tiling a sticky window ends sticky. Minimizing a window ends its fullscreen.
- A Lua C module loads only from the config folder unless the config sets `package.cpath`.

### Added

- `WM_DEBUG=1` makes `wm daemon status` show how long wm's own work and the relayouts took during the last animation.
- **A space opens while a window is dragged.** Drag a tiled window by its title bar (or with `mouse.move_modifier`): its
  neighbours move aside live and a placeholder shows the slot. Near a side of another window it goes beside it, on its middle
  the two swap, at a screen edge it takes that side. Tiling, scrolling and master. `mouse = { move_preview = false }` turns it
  off.
- **A dragged window shrinks to a picture** with `mouse.move_modifier`, and springs into its slot on the drop
  (`mouse.drag_picture`).
- **Floating windows:** a drop beside another floating window lines it up; Cmd on the middle of one makes a group of tabs
  (`wm window group next|prev`, `wm window ungroup`); with the move modifier, screen edges and corners snap it.

### Fixed

- Hiding an app (Cmd-H) no longer moves its windows to the workspace on screen when it shows again.
- An app that restarts (an update, a crash, a quit and an open within 5 minutes) gets its windows back on their workspaces,
  instead of on the workspace on screen.
- wm crashed when a window of a tile block in the scrolling layout was sent to the other strip.
- wm could stop following windows until a restart when an app quit while wm read its windows.
- `nan` or `inf` as a size, ratio or step was accepted and left a window stuck off screen, broke `--json` output and state
  saving. Numbers are checked now; a split or master ratio is 0.1 to 0.9, a width or height fraction 0 to 1.
- `layout set floating` from monocle (or with columns scrolled away) floated hidden windows in a corner of the screen.
- `layout set tiling` on a tiling workspace reset its splits. `window pseudo` sizes stayed after a switch to another layout.
- `workspace ''`, `workspace 0` (with a `workspaces` limit) and `workspaces balance` with a huge count are refused.
- `window send workspace` to the window's own workspace rebalanced it; `window unmark <name>` removed another window's mark.
- `wm daemon reload` from an older copy of `wm` replaced a newer daemon with the old version; it refuses now, and `wm doctor`
  says which copy is old.
- The state folder and files are readable by your user only.
- `focus <dir>` no longer stops on the empty cell of an app that a restore still waits for.
- A swap by the mouse or jump mode ends maximize and fullscreen on the workspace, as `wm swap` does.
- A terminal swallowed by the program it started stays swallowed across `wm daemon reload`.
- With focus-follows-mouse, the window in front gets the focus where windows overlap (a floating window over a tile).
- The floating windows of a hidden workspace move along when it shows on another monitor, and a workspace switch that moves
  them is no step of `layout undo`.
