---
title: "Master-stack"
description: "One master area and a stack of the other windows."
group: Layouts
order: 3
---
`wm layout set master` (or `layout = "master"`, per workspace with `wm.workspace`) puts the first windows in a big master area and
the others in a stack beside it, like dwm, xmonad and Hyprland's master layout. A lone window fills the screen.

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

- `orientation` is where the master area is: `left`, `right`, `top`, `bottom`, or `center` (the master in the middle, the stack on
  both sides: the first stack window on the right, the next on the left, and so on; with one stack window it is the left layout).
- `ratio` is the share of the screen along the split (0.1 to 0.9). `count` is how many windows are masters; they share the master
  area equally, and so do the windows of the stack. With as many masters as windows, they share the whole screen.
- `new_window = "stack"` puts a new window at the top of the stack; `"master"` makes it the master and the old master goes to the
  stack (dwm and xmonad).
- Commands: `layout master promote` swaps the focused window with the master (when it is the master, the first stack window takes
  its place), `layout master count <n|+n|-n>`, `layout master ratio <ratio|+n|-n>`, and `layout master orientation [place|next]`.
  They change the live layout, and the workspace keeps them while the config is the same; a changed config wins when it reloads.
  `resize width` (or `height`, with the master on top or bottom) and the mouse move the divider too; `layout balance` sets the ratio to
  0.5. `move`, `swap`, `focus` and `layout rotate` work as in the other layouts.
- Tile templates (`layout tile`) and the scrolling commands do not apply to this layout.
