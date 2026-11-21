---
title: "Master-stack"
description: "One master area and a stack of the other windows."
group: Layouts
order: 3
---
`wm layout set master` (or `layout = "master"`, per workspace with `wm.workspace`) puts the first windows in a big master area
and the others in a stack beside it. It works like dwm, xmonad and Hyprland's master layout. A lone window fills the screen.

```lua
wm.config {
  layout = "master",
  master = { ratio = 0.55, count = 1, orientation = "left", new_window = "stack" },
}
wm.bind("alt-return", "layout master promote")
wm.bind("alt-i", "layout master count +1")
wm.bind("alt-d", "layout master count -1")
wm.bind("alt-o", "layout master orientation")
```

## Options

- `orientation`: where the master area is. One of `left`, `right`, `top`, `bottom`, `center`.
  - `center` puts the master in the middle and the stack on both sides. The first stack window goes on the right, the next on
    the left, and so on. With one stack window, it is the left layout.
- `ratio`: the share of the screen along the split, from 0.1 to 0.9.
- `count`: how many windows are masters.
  - Masters share the master area equally. So do the windows of the stack.
  - With as many masters as windows, they share the whole screen.
- `new_window`:
  - `"stack"` puts a new window at the top of the stack.
  - `"master"` makes it the master. The old master goes to the stack (dwm and xmonad).

## Commands

- `layout master promote`: swaps the focused window with the master. If it is the master, the first stack window takes its place.
- `layout master count <n|+n|-n>`
- `layout master ratio <ratio|+n|-n>`
- `layout master orientation [place|next]`

These commands change the live layout. The workspace keeps them while the config is the same. A changed config wins when it
reloads.

- `resize width` (or `height`, with the master on top or bottom) and the mouse also move the divider.
- `layout balance` sets the ratio to 0.5.
- `move`, `swap`, `focus` and `layout rotate` work as in the other layouts.
- Tile templates (`layout tile`) and the scrolling commands do not apply to this layout.
