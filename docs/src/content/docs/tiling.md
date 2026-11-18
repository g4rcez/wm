---
title: "Tiling"
description: "The binary-tree layout: a new window splits the focused one."
group: Layouts
order: 1
---
- `layout preselect <left|right|up|down>`: the next window that opens splits the focused one on that side, once.
- `layout split ratio 0.7` gives the focused window 70% of its split. A number from 0.1 to 0.9, or a change like `+0.1`.
- `layout split root` makes the focused window a child of the root split. It gets half the screen.
- `layout split toggle` flips the split of the window. `layout split swap` swaps its two sides.
- `layout flip` turns every split from side by side to stacked, and back.
- `window pseudo` keeps the window at the size it has now, centered in its tile. Run it again to tile it normally.
- `tiling.smart_split = true` makes a new window split the tile under the mouse pointer on the side that the pointer is
  nearest to (measured along the diagonals of the tile). A `layout preselect` still wins, and a pointer outside the
  tile means the usual split. Moving a window with `move <dir>` already swaps it with its neighbour, so there is no
  separate command to move a tile up or down.
- `tiling.split_under_pointer = true` makes a new window split the tile that the mouse pointer is over, and not the focused
  tile, on the side that the pointer is nearest to. With no tile under the pointer it uses the focused tile, as usual.
  It does not need `smart_split`. A `layout preselect` still wins.
- `tiling.force_split = "first"` puts new windows on the left or top. `tiling.split_width_multiplier = 2` keeps columns
  on an ultrawide screen before the first stacked split.
