---
title: "Tile templates"
description: "Ready-made tile arrangements, and how to write your own."
group: Layouts
order: 4
---
`layout tile <pattern>` makes the focused window and the windows after it fill one screen in a fixed pattern.
`layout tile chain` goes back to single columns. `layout tile` with no pattern opens a picker.

| Pattern | Windows | Picture |
|---|---|---|
| `2` | 2 | side by side |
| `3` | 3 | three in a row |
| `2+1` | 3 | two stacked on the left, one tall on the right |
| `1+2` | 3 | one tall on the left, two stacked on the right |
| `4` | 4 | two across, two down |
| `5` | 5 | three on top, two below that stretch to the full width |
| `6` | 6 | two rows of three |
| `2/3` | 2 | the first window takes two thirds of the width, the second one third |
| `3/4` | 2 | the first window takes three quarters on the left, the second one quarter |
| `1/4` | 2 | the mirror of `3/4`: one quarter on the left, three quarters on the right |
| `2v` | 2 | one over the other |
| `2/3v` | 2 | the first window takes two thirds of the height, the second one third |
| `3v` | 3 | three in a column |
| `1-over-2` | 3 | one wide window on top, two side by side below |
| `2-over-1` | 3 | two side by side on top, one wide window below |
| `1/2/1` | 3 | a quarter, a half, a quarter |
| `corner-tl` | 3 | a large window (two thirds by two thirds) in the upper left corner, the others around it |
| `corner-bl` | 3 | a large window (two thirds by two thirds) in the lower left corner, the others around it |
| `center` | any | the windows share the middle two thirds of the width, with a sixth of margin on each side (tiling layout only) |
| `chain` | - | back to single columns, and removes the margin of `center` |

In the scrolling layout the group is the focused window and the windows after it (or before it, when too few come after).
It is one block in the strip, so scrolling moves it as one screen. In the tiling layout the pattern applies to all tiled
windows of the workspace, and their number has to match. The picker has a one-character key on each picture: a number for
the grids, `l` and `r` for `2+1` and `1+2`, `t`, `q` and `w` for `2/3`, `3/4` and `1/4`, `v`, `h`, `y`, `n`, `j`, `m`, `u` and `o` for the new ones above in table order, `z` for `center`, and `c` for the chain.

`center` is a frame, not a grid: it does not arrange the windows. It keeps the windows as they are and lays them out in the
middle two thirds, for one window or many, so a lone window is a centered window and not a maximized one. A grid applied after
`center` fills the whole width again, and so does `layout tile chain`.

## Draw a frame

In the tiling layout the picker has one more picture, `g` (draw). It opens a grid of 8 by 6 cells. Drag a rectangle with the
mouse and let go: the tiled windows of the workspace share that part of the screen, as with `center`. `Esc` goes back to the
pictures. A rectangle that covers the whole grid is ignored (maximize the window instead).

wm saves the frames in `custom-templates.json`, next to `state.json` (`~/.local/state/wm/`), up to 24 of them; a new one past
that drops the oldest. They appear after the other templates in the picker and work with `layout tile <name>`. The name is
`frame-<column>-<row>-<width>x<height>-of-8x6`, for example `frame-2-1-4x3-of-8x6`. Delete the file to remove them all.
Scrolling layout does not use frames.

## Your own templates

`templates` in `tiling` and in `scrolling` replaces the list that the picker and the menu bar show for that layout. Each
layout has its own list. Without `templates`, the layout lists the eighteen built-in ones. `wm.templates` has every built-in
template, so a list can mix them with your own:

```lua
wm.config {
  tiling = { templates = { wm.templates.two, wm.templates.four, wm.templates.stack_left } },
  scrolling = {
    templates = {
      wm.templates.two_thirds,
      { name = "70/30", key = "s", title = "Focus 70%", cells = { { 0, 0, 0.7, 1 }, { 0.7, 0, 0.3, 1 } } },
    },
  },
}
```

`wm.templates` has `two`, `three`, `four`, `five`, `six`, `stack_left`, `stack_right`, `two_thirds`, `three_quarters`,
`one_quarter`, `two_rows`, `two_thirds_tall`, `three_rows`, `one_over_two`, `two_over_one`, `sidebars`, `corner_top_left`, `corner_bottom_left` and `centered` (the `center` frame).

- `name` is what `layout tile <name>` takes. It has no spaces, it is not `chain`, and it is unique in the list.
- `key` is optional: one of `a-z` or `0-9`, not `c`, unique in the list. It picks the template in the picker.
- `title` is optional: the text in the menu bar menu (the default is the name).
- `cells` is a list of `{ x, y, width, height }` as fractions of the screen, in reading order. The windows take the cells in
  that order. There are two or more cells. They fill the screen with straight cuts and do not overlap.
- `area` is optional: `{ x, y, width, height }` as fractions of the screen, the part that the cells fill. Without it they
  fill the whole screen. One cell `{ 0, 0, 1, 1 }` with a smaller `area` is a frame like `center` (tiling layout only), for example
  `{ name = "wide", cells = { { 0, 0, 1, 1 } }, area = { 0.1, 0, 0.8, 1 } }`.
- The chain stays last in the picker and the menu.
- `layout tile <name>` also takes a built-in name that your list leaves out, so old binds keep working.
- The shell completion for `wm layout tile` lists only the built-in names.
