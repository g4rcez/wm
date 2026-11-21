---
title: "Sticky windows and zen mode"
description: "Pin a window to every workspace, or hide everything but one window."
group: Features
order: 2
---
## Sticky

`window sticky` shows a floating window on every workspace of its monitor. A tiled window floats first. Use it for a chat, a
player or Picture-in-Picture.

- Run it again to end it.
- It follows the workspace that the monitor shows, also a special workspace.
- `window remember` keeps it.
- A sticky window changes its workspace name as you switch. A remembered or listed sticky window has the workspace it was on at
  that moment.

## Zen

`wm zen` shows only the focused window, centered, and hides the others.

- Hidden windows move off screen, like the windows of a hidden workspace. The layout does not change.
- Focusing another window shows that one instead.
- `wm zen` again brings everything back.
- A fullscreen window wins over it. A restart of the daemon ends it.

```lua
wm.config { zen = { width = 0.7 } }   -- the width of the window, 0.3 to 1 of the work area
wm.bind("alt-space>shift-z", "zen")
wm.bind("alt-space>shift-s", "window sticky")
```
