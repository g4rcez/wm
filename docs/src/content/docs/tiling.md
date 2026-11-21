---
title: "Tiling"
description: "The binary-tree layout: a new window splits the focused one."
group: Layouts
order: 1
---
## Commands

- `layout preselect <left|right|up|down>`: the next window that opens splits the focused one on that side, once.
- `layout split ratio 0.7` gives the focused window 70% of its split. Use a number from 0.1 to 0.9, or a change like `+0.1`.
- `layout split root` makes the focused window a child of the root split. It gets half the screen.
- `layout split toggle` flips the split of the window. `layout split swap` swaps its two sides.
- `layout flip` turns every split from side by side to stacked, and back.
- `window pseudo` keeps the window at its current size, centered in its tile. Run it again to tile it normally.
- `move <dir>` already swaps a window with its neighbour. There is no separate command to move a tile up or down.

## Config

- `tiling.smart_split = true`: a new window splits the tile under the mouse pointer, on the side nearest to the pointer
  (measured along the diagonals of the tile).
  - A `layout preselect` still wins.
  - A pointer outside the tile means the usual split.
- `tiling.split_under_pointer = true`: a new window splits the tile under the pointer, not the focused tile, on the side nearest
  to the pointer.
  - With no tile under the pointer, it uses the focused tile.
  - It does not need `smart_split`.
  - A `layout preselect` still wins.
- `tiling.force_split = "first"`: new windows go on the left or top.
- `tiling.split_width_multiplier = 2`: keeps columns on an ultrawide screen before the first stacked split.

## Tile patterns

After a [tile pattern](/docs/templates) with columns (`30/40/30`), a window that opens in a column keeps stacking in it, one
above the other. Without this rule, the short cells of a stack would put the new window beside the others, as a row.
