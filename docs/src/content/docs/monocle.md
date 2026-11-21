---
title: "Monocle"
description: "One window fills the workspace; focus next and previous walk through the others."
group: Layouts
order: 4
---
`wm layout set monocle` (or `layout = "monocle"`, per workspace with `wm.workspace`) shows one window at a time. It fills the
workspace inside the gaps. The other windows wait out of sight until you focus them. It is the monocle layout of xmonad and
Hyprland.

```lua
wm.workspace("reading", { layout = "monocle" })
wm.bind("alt-j", "focus next")
wm.bind("alt-k", "focus prev")
wm.bind("alt-m", "layout set monocle")
```

- `focus next` and `focus prev` bring the next or previous window into view. `focus left|up` and `focus right|down` mean the
  same here. With `wrap_focus = true` they go around at the ends.
- A new window opens after the focused one and comes into view, as in the other layouts.
- `move left|right` (or `up|down`), `swap` and `layout rotate` change the order of the walk. At the end, `move` goes to the next
  monitor.
- Nothing else is configurable: there is no ratio, count or orientation.
- Floating windows stay where they are, above the monocle window. Fullscreen and maximize still win over it.
- With `gaps = { smart = true }`, the window fills the workspace without gaps.
- The tab indicator of the [scrolling layout](/docs/scrolling) has one segment per window and marks the one in view.
  `tab_indicator.enabled = false` turns it off. A lone window shows none.
- The menu bar letter is `O` (`M` is master-stack).
- Tile templates are not for this layout.

The windows that wait are parked in a corner of the screens, like the windows of a hidden workspace. wm cannot stack them
behind the shown window, because macOS brings every window of the active app forward at once.
