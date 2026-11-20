---
title: "Monocle"
description: "One window fills the workspace; focus next and previous walk through the others."
group: Layouts
order: 4
---
`wm layout set monocle` (or `layout = "monocle"`, per workspace with `wm.workspace`) shows one window at a time. It fills the
workspace inside the gaps, and the other windows of the workspace wait out of sight until you focus them. It is the monocle layout
of xmonad and Hyprland.

```lua
wm.workspace("reading", { layout = "monocle" })
wm.bind("alt-j", "focus next")
wm.bind("alt-k", "focus prev")
wm.bind("alt-m", "layout set monocle")
```

- `focus next` and `focus prev` (and `focus left|up` and `focus right|down`, which mean the same here) bring the previous or the next
  window into view. With `wrap_focus = true` they go around at the ends.
- A new window opens after the focused one and comes into view, as it does in the other layouts.
- `move left|right` (or `up|down`), `swap` and `layout rotate` change the order of the walk; at the end, `move` goes to the next
  monitor. Nothing else of the layout is configurable: there is no ratio, count or orientation.
- Floating windows stay where they are, above the monocle window. Fullscreen and maximize still win over it.
- With `gaps = { smart = true }` the window fills the workspace without gaps, because only one window is shown.
- The menu bar letter is `O` (`M` is master-stack).
- Tile templates are not for this layout.

The windows that wait are parked in a corner of the screens, like the windows of a hidden workspace. wm cannot stack them behind
the shown window, because macOS brings every window of the active app forward at once.
