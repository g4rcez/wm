---
title: "Layouts"
description: "Scrolling, tiling, master, monocle and floating layouts, templates, special workspaces, sticky and zen."
group: Layouts
order: 1
---
## Choosing a layout

Set `layout = "<layout>"` in `wm.config`, or per workspace with `wm.workspace`. Switch the focused workspace with
`wm layout set <layout>`. Run `wm help <command>` for flags.

| Layout | What it does | Switch | Config key |
|---|---|---|---|
| Scrolling | Columns on a strip that moves sideways. | `wm layout set scrolling` | `scrolling` |
| Tiling | A new window splits the focused one. | `wm layout set tiling` | `tiling` |
| Master | A master area and a stack. | `wm layout set master` | `master` |
| Monocle | One window fills the workspace. | `wm layout set monocle` | none |
| Floating | Windows float by default. | `wm layout set floating` | none |

`layout rotate cw` and `layout rotate ccw` move every window one slot around the layout, in every layout. The slots keep their
sizes.

## Scrolling

Columns sit on a strip. A column can hold a stack of windows or tabs.

| Command | What it does |
|---|---|
| `layout column width <fraction\|cycle>` | Sets the column width. `cycle` walks `scrolling.presets`. |
| `layout column match`, `layout balance` | Set column widths. `balance` fits all columns on screen. |
| `layout column expand` | Grows the column into the free room. |
| `layout column move <first\|last\|n>` | Moves the column. `n` counts from 1; too large means last. |
| `layout column center`, `center-visible` | Scroll the strip. |
| `focus column <first\|last\|n>`, `focus stack <first\|last\|n>` | Focus a column, or a window of the current column. |
| `focus next`, `focus prev` | Walk all windows in layout order, also in tiling. |
| `layout stack join [side]`, `leave [side]` | Put the window in the column on its left, or take it out. `join right` goes to the bottom of the right column; `leave left` makes a new column on the left. |
| `layout stack tabs`, `equalize` | Show the column as tabs; even out the heights. |
| `layout stack height <fraction\|cycle>` | Gives the window a share of the column. |
| `window maximize` | Grows the column to the whole zone. Again to restore. |
| `window send workspace <name> --column` | Sends the whole column (also `window send monitor <monitor> --column`). |

| Config key | Effect |
|---|---|
| `scrolling.visible_columns = 3` | With 2 or more columns but fewer than 3, columns grow to fill the screen. 0 is off (default). |
| `scrolling.single_window_fit` | `"fill"` (default): a lone column fills the screen until you set its width. `"keep"` keeps its width. |
| `scrolling.orientation` | `"horizontal"` (default), `"vertical"` (rows scroll up and down) or `"auto"` (vertical on a monitor taller than wide). Also in a workspace's `layout_options`. |
| `wrap_focus = true` | `focus`, `move` and `swap` go around at the edge, like `--wrap`. Default false. |
| `tab_indicator.enabled = false` | Turns off the bar with one segment per tab. |

The strip does not loop unless `wrap_focus` or `--wrap` is set. `scrolling.vertical` adds a second, vertical strip at one side of the screen; `window send strip vertical|horizontal` moves a window between the strips.

## Tiling

| Command | What it does |
|---|---|
| `layout preselect <left\|right\|up\|down>` | The next window splits the focused one on that side, once. |
| `layout split ratio 0.7` | Gives the focused window 70% of its split. Use 0.1 to 0.9, or `+0.1`. |
| `layout split root` | Makes the window a child of the root split (half the screen). |
| `layout split toggle`, `layout split swap` | Flip the split; swap its two sides. |
| `layout flip` | Turns every split from side by side to stacked, and back. |
| `window pseudo` | Keeps the window at its size, centered in its tile. Again to tile it. |

`move <dir>` already swaps a window with its neighbour.

| Config key | Effect |
|---|---|
| `tiling.smart_split = true` | A new window splits the tile under the pointer, on the side nearest to the pointer. |
| `tiling.split_under_pointer = true` | A new window splits the tile under the pointer, not the focused one. Needs no `smart_split`. |
| `tiling.force_split = "first"` | New windows go on the left or top. |
| `tiling.split_width_multiplier = 2` | Keeps columns on an ultrawide screen before the first stacked split. |

## Master

A master area and a stack beside it, like dwm and xmonad. A lone window fills the screen.

| Command | What it does |
|---|---|
| `layout master promote` | Swaps the focused window with the master. |
| `layout master count <n\|+n\|-n>` | How many windows are masters. |
| `layout master ratio <ratio\|+n\|-n>` | The ratio. |
| `layout master orientation [place\|next]` | Where the master area is. |

| `master` key | Effect |
|---|---|
| `orientation` | `left` (default), `right`, `top`, `bottom` or `center` (master in the middle, stack on both sides). |
| `ratio` | Share of the screen along the split, 0.1 to 0.9. Default 0.55. |
| `count` | Number of masters. Default 1. They share the area equally. |
| `new_window` | `"stack"` (default): top of the stack. `"master"`: becomes the master. |

`resize width` (or `height`) and the mouse move the divider; `layout balance` sets the ratio to 0.5. A changed config wins when it reloads.

## Monocle

One window at a time fills the workspace inside the gaps; the others wait out of sight. Nothing is configurable. `focus next|prev` (or `left|up`, `right|down`) bring the next or previous window into view, `move`, `swap` and `layout rotate` change the order, and floating windows stay above it. With `gaps = { smart = true }` the window has no gaps. The menu bar letter is `O`.

## Floating

`wm layout set floating` floats every window of the workspace, and new windows float in the frame that tiling would give them. A rule or `window remember` keeps the place of a window. Switching to another layout leaves windows floating; only later windows tile. `workspace float-all off` tiles them all. The menu bar letter is `F`.

| Command | What it does |
|---|---|
| `window float [on\|off]` | No argument: floats the window in the middle of its screen at its size (a full-area window gets 60%). `on` and `off` never toggle, so a bind repeats safely. `off` tiles it. |
| `window center` | Floats (a tiled window first) and centers. |
| `window snap <place>` | Places: `left`, `right`, `top`, `bottom`, the four corners, `top-center`, `bottom-center`, `center`. The same place again goes to the next size: half, a third, two thirds (`center`: 60%, 80%, 40%). |
| `window move-to <x> <y>` | Top left corner at a point, in points or percent (`50% 10%`). |
| `window place <pattern> <n>` | Floats into cell n of a tile template, from 1 in reading order. |
| `window rescue` | Moves a mostly off-screen window back into the work area. |
| `move <dir> [points]` | Moves by `points` (40 by default). Stops at the monitor edge. |
| `resize <width\|height\|smart> <+n\|-n>` | Changes size by n points. `smart` changes both sides around the center. |
| `resize <left\|right\|up\|down> <+n\|-n>` | Moves one edge: `+n` outward, `-n` inward. On a tiled window it moves the divider. |
| `resize dir <left\|right\|up\|down> <n>` | Grows for right and down, shrinks for left and up. |
| `workspace float-all [off\|<pattern>]` | Floats every window of the workspace in place. `off` tiles them. With a tile template (`2+1`, `2/3`, `corner-tl`, your own) they float into its cells. Minimized and macOS fullscreen windows are left alone. |
| `window mark <name>`, `window unmark [name]` | Name a window (one window per name), or remove the name. `focus mark <name>` focuses it and `--window mark:<name>` acts on it. Marks last until the window closes. |

`window maximize` keeps a scrolling window in its place in the strip and elsewhere fills the work area inside the outer gaps. `window fullscreen` fills the work area with no gaps and no border. `window native-fullscreen` enters or leaves macOS fullscreen; wm leaves that window out of the layout. A window sent to an empty workspace arrives maximized; otherwise it joins the layout and `balance` runs (`--tile` joins without either).

## Templates and tile patterns

`layout tile <pattern>` makes the focused window and the windows after it fill one screen in a fixed pattern. With no pattern
it opens a picker. `layout tile chain` goes back to single columns.

- Scrolling: the focused window and the ones after it (or before, when too few). It is one block in the strip.
- Tiling: all tiled windows of the workspace; their number must match the pattern. A single window works too.

| Pattern | Windows | Picture |
|---|---|---|
| `2`, `3`, `4`, `6` | 2, 3, 4, 6 | side by side, three in a row, two by two, two rows of three |
| `5` | 5 | three on top, two below |
| `2+1`, `1+2` | 3 | two stacked left and one tall right, and the mirror |
| `2/3`, `3/4`, `1/4` | 2 | first window takes two thirds, three quarters, one quarter of the width |
| `2v`, `3v` | 2, 3 | one over the other, three in a column |
| `2/3v` | 2 | first window takes two thirds of the height |
| `1-over-2`, `2-over-1` | 3 | one wide window on top and two below, and the mirror |
| `1/2/1` | 3 | a quarter, a half, a quarter |
| `corner-tl`, `corner-bl` | 3 | a large window (two thirds by two thirds) in the upper or lower left corner |
| `center` | any | windows share the middle two thirds of the width (tiling only) |
| `chain` | - | single columns again; removes the margin of `center` |

`center` is a frame, not a grid: it lays the windows out in the middle two thirds. A grid applied after it, or `layout tile chain`, fills the whole width again. In the tiling layout the picker also has `g` (draw): drag a rectangle on a grid of 8 by 6 cells and the tiled windows share it. wm keeps up to 24 frames in `custom-templates.json` next to `state.json`; they work with `layout tile frame-<column>-<row>-<width>x<height>-of-8x6`.

`templates` in `tiling` and in `scrolling` replaces the picker and menu list for that layout. Without it, the layout lists the
eighteen built-in ones. `wm.templates` has them all: `two`, `three`, `four`, `five`, `six`, `stack_left`, `stack_right`,
`two_thirds`, `three_quarters`, `one_quarter`, `two_rows`, `two_thirds_tall`, `three_rows`, `one_over_two`, `two_over_one`,
`sidebars`, `corner_top_left`, `corner_bottom_left` and `centered`.

```lua
wm.config {
  scrolling = {
    templates = {
      wm.templates.two_thirds,
      { name = "70/30", key = "s", title = "Focus 70%", cells = { { 0, 0, 0.7, 1 }, { 0.7, 0, 0.3, 1 } } },
    },
  },
}
```

| Field | Meaning |
|---|---|
| `name` | What `layout tile <name>` takes. No spaces, not `chain`, unique in the list. |
| `key` | Optional. `a-z` or `0-9`, not `c`, unique. Picks it in the picker. |
| `title` | Optional. Menu bar text (default: the name). |
| `cells` | `{ x, y, width, height }` as fractions of the screen, in reading order. Two or more, straight cuts, no overlap. |
| `area` | Optional. The part of the screen the cells fill. One cell `{ 0, 0, 1, 1 }` with a smaller `area` is a frame like `center` (tiling only). |

`layout tile <name>` also takes a built-in name that your list leaves out. Shell completion lists only the built-in names.

## Special workspaces

A scratchpad: one key shows a workspace over the others, the same key hides it.

```lua
wm.bind("alt-s", "workspace special term")                     -- show or hide special:term on the focused monitor
wm.bind("alt-shift-s", "window send workspace special:term")   -- send the window there and show it
wm.workspace("special:term", { layout = "scrolling" })
wm.workspace("special:notes", { on_empty = { cmd = "open -a Notes", app = "Notes", float = true, center = true } })
wm.rule { app = "com.spotify.client", workspace = "special:music" }
```

`on_empty` starts a program the first time you show the workspace, only when it has no window. The window it opens goes to that
workspace, even if you switched away. See [Configuration](/docs/config) for rules.

With `workspaces = "native"` the special workspace shows over the desktop that the monitor shows: its windows move there when it is shown.

The workspace takes the work area with 5% free on each side (`special.size`, 0.9 by default). It hides when you run the command again, switch to a workspace, its last window goes away, or a window of the normal workspace on the same monitor gets focus. Other `special` keys: `backdrop` (a color such as `"#00000066"`, `""` is none) and `hide_on_other_monitor`.

## Balance the workspaces

`wm workspaces balance [count]` spreads the windows over the workspaces so that none has more than one window above another. With
as many workspaces as windows, or more, each workspace gets one window. A window moves only when it has to, and the window that has
the focus keeps it (its workspace is shown). Sticky, minimized, full-screen and special-workspace windows stay.

The workspaces are 1 to `count`, or 1 to the `workspaces` limit of the config when there is no `count`; with neither, the command is
an error. With `workspaces = "native"` they are the first desktops instead. `wm workspaces balance 4` with six windows on workspace 1
leaves 2, 2, 1, 1. A `count` above the limit is an error. Windows on workspaces with a name (`web`) are outside the set, so they move
into it.

## Sticky and zen

`window sticky` shows a floating window on every workspace of its monitor (a tiled window floats first). Use it for a chat, a
player or Picture-in-Picture. Run it again to end it. It follows the workspace the monitor shows, also a special one.
`window remember` keeps it. A remembered or listed sticky window has the workspace it was on at that moment.

`wm zen` shows only the focused window, centered, and moves the others off screen without changing the layout. Focusing another
window shows that one instead. `wm zen` again brings everything back. A fullscreen window wins over it. A restart of the daemon
ends it.

```lua
wm.config { zen = { width = 0.7 } }   -- the width of the window, 0.3 to 1 of the work area
wm.bind("alt-space>shift-z", "zen")
wm.bind("alt-space>shift-s", "window sticky")
```
