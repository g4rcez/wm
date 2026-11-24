---
title: "Troubleshooting and limits"
description: "Fixes for common problems, and what wm cannot do."
group: Guides
order: 1
---
## Troubleshooting

Run `wm doctor` first. It checks the config, `shortcuts.toml`, the daemon and the permissions, and says what to do for each check that is not ok. `wm config check` loads the config alone and shows the line of an error.

- **Nothing happens when I press a key.** Check that wm has Accessibility permission and that `wm daemon status` says it runs. Without a config, wm has no key binds (`wm init`).
- **The setup window asks for no permission.** macOS shows its prompt once for each app signature. When the permission is still missing a moment after you press Grant, wm opens the matching pane of System Settings > Privacy & Security and shows a small panel with the wm icon. Drag the icon into the list and switch `wm` on. The panel closes when the permission is granted. `wm doctor` shows what is still missing.
- **I rebuilt and macOS asks for permissions again.** The build was signed ad hoc. See [Signing](/docs/getting-started#signing).
- **The menu bar icon is missing.** Switch on `wm` in System Settings > Menu Bar. `wm daemon status` says `menu bar: hidden by macOS` when the icon is not on screen.
- **The switcher shows icons and not pictures, or `wm select` finds no text in a terminal.** Grant Screen Recording.
- **A window floats or stays out of the layout.** Dialogs and palettes float by design. Use `wm window float` to toggle one, or add a rule.
- **A shortcut from the Shortcuts window does nothing.** `wm doctor` says why in its `shortcuts` line: `init.lua` does not call `wm.shortcuts()`, `init.lua` binds the same keys later (it wins), or `shortcuts.toml` has an error.
- **A command such as `wm workspaces balance` says the daemon does not know it.** The daemon started before you upgraded wm and still runs the old version (`wm doctor` shows both versions). Run `wm daemon stop`, then `wm daemon start`.
- **A remap works here but not on the Mac I control (Universal Control, a software KVM).** The other Mac gets the keys that the keyboard sends, not the ones wm types, or gets them before wm can change them. Do this:
  1. Run wm with `WM_LOG_LEVEL=debug`, put the cursor on the other Mac, press the chord (`hyper-l`) and read `wm logs`. wm logs only the keys that a bind or a remap used. No line means the tool takes the keys before wm sees them: no setting of wm can change what the other Mac gets, and only a virtual keyboard driver (what Karabiner-Elements installs) can.
  2. A line means wm sees the key. Set `binds = { event_level = "hid" }`, run `wm daemon reload` and try again. wm then listens before the session tap and types its keys as if a keyboard sent them. `wm doctor` warns when macOS refuses that tap.
  The hyper key is CapsLock turned into F18 by the keyboard mapping, so a remote Mac that gets keys before wm sees F18 and `L`, not a remapped Left.
- **Binds stop working while I type a password, and a lock shows in the menu bar.** macOS Secure Event Input is on: while a password field has focus, or an app has *Secure Keyboard Entry* on (Terminal, iTerm2), macOS hides the keys from wm. wm cannot work around it, so leave the password field. If the lock stays on after that, an app still holds it: the menu and `wm doctor` name it, so turn off *Secure Keyboard Entry* there or quit it. When the lock goes away, wm resets its key state and the binds work.
- **The desktop slide still plays when I switch workspaces (`workspaces = "native"`).** macOS draws that slide, not wm. With `animations.enabled = false` (or `animations.workspaces.enabled = false`) wm sends the Dock a swipe that jumps to the end, which makes the slide short or gone on some macOS versions. If it stays, try another velocity (`WM_SPACE_INSTANT_VELOCITY=5000 wmd`, or 60000), turn on *Reduce motion* in System Settings > Accessibility > Display (a short fade), or use `workspaces = "emulated"`, where wm moves the windows itself and no slide plays.
- **A tiled window stops short of the edge (a gap at the bottom of the screen).** macOS or the app changed the window after wm placed it, for example after a display change or a wake from sleep. wm puts it back on the next refresh (a focus change, a window that opens or closes, a display change, a wake). An app that refuses the size (a minimum size, a terminal that rounds to whole lines) keeps its own size after two tries. `WM_LOG_LEVEL=debug` shows each resend in `wm logs`.
- **My config has an error.** The old config stays active. The message is in the menu bar, in the output of `wm daemon reload` and in `wm logs`.
- **`workspace N` says the workspace has no desktop (`workspaces = "native"`).** wm makes the desktop on macOS 27 and later, so either this macOS is older (add desktops in Mission Control), macOS refused (the limit is 16 desktops for each display), or the name is not a number and has no `space` in its `wm.workspace` rule. `wm doctor` lists the workspaces without a desktop.
- **Workspace 2 is not desktop 2 any more (`workspaces = "native"`).** macOS reordered the desktops. Turn off *Automatically rearrange Spaces based on most recent use* in System Settings > Desktop & Dock > Mission Control.
- **The cursor jumps to the other display for a moment when I switch workspaces (`workspaces = "native"`).** The Dock swipes the display under the cursor, so wm puts the cursor on the target display while it posts the swipe, and back.
- **wm and another window manager fight.** Quit the other one. Quitting wm puts every hidden window back on screen.

## Limits

- Animations move real windows through the Accessibility API, one call per frame, so slow apps (Electron) can stutter. wm cannot blur, fade or shadow other apps' windows.
- `focus urgent` reads the Dock badge, so it works per app, only for apps that show a badge (Mail, Slack, Messages), and up to 2 seconds late. A Dock bounce without a badge cannot be seen. `urgent = { enabled = false }` stops the reading.
- A window with a minimum size larger than its tile overlaps its neighbours.
- Gestures with `mods` see a modifier and a scroll direction, not the finger count. Gestures with `fingers` use the private MultitouchSupport framework; if it cannot be loaded they stay off, and the log says so. Turn off macOS's own three- and four-finger gestures that you use in wm (System Settings > Trackpad > More Gestures), or both act on the same swipe.
- When a display goes away, its workspace keeps its windows hidden until the display comes back. Until then `wm workspace N` shows it on another monitor.
