---
title: "Scrolling"
description: "Columns on a strip that moves sideways: stacks, tabs, presets and a vertical strip."
group: Layouts
order: 2
---
## Column widths

- `layout column width <fraction|cycle>`, `layout column match` and `layout balance` set column widths.
- `balance` fits all columns on screen.
- `layout column expand` grows the focused column into the room that the other columns on screen leave free.

## Visible columns

- `visible_columns = 3` makes 2 columns grow in proportion until they fill the screen.
- The widths that you chose stay stored. They come back when the third column opens.
- A lone column follows `single_window_fit`.
- With the default `"fill"`, a lone column fills the screen until you set its width (`layout column width`, a resize, `layout balance`).
- A width that you set is kept while the column is alone.

## Vertical strip

- `orientation = "vertical"` turns the strip. Windows become rows that scroll up and down.
- `move`, `focus` and `resize` follow the screen (`focus down` goes to the next row).
- `orientation = "auto"` does this on a monitor that is taller than it is wide. Set it once and use a portrait display beside a landscape one.
- A workspace can set it in `layout_options`.
- A stack is side by side inside a row.
- Tile templates turn with the screen.
- The second strip moves to the bottom (or the top) of the screen.
- `window send strip horizontal` and `vertical` keep meaning the main strip and the second strip.
- Swipes with Option scroll along the strip, whichever way it runs.

## Moving and focusing

- The strip does not loop. Set `wrap_focus = true`, or use `focus left --wrap`, to go from the last column to the first.
- `move` and `swap` take `--wrap` too (and follow `wrap_focus`). The window at the end trades places with the one at the other end.
- `layout column move <first|last|n>` moves the column to a place in the strip. `n` counts from 1. A number that is too large means the last place.
- `focus column <first|last|n>` focuses a column (the window that had the focus last in it).
- `focus stack <first|last|n>` focuses a window of the column you are in.
- `focus next` and `focus prev` walk through all windows in layout order, also in the tiling layout. Add `--wrap` to go around.
- `window send workspace <name> --column` (and `window send monitor <monitor> --column`) sends the whole column, with
  its stack, width and tabs. It joins the layout there like `--tile`.

## Stacks and tabs

- `layout stack join` puts the window in the column on its left. `layout stack leave` takes it out.
- Both take a side:
  - `layout stack join right` puts the window at the bottom of the column on its right.
  - `layout stack leave left` puts it in a new column on its left.
- `layout stack tabs` shows the column as tabs.
- `layout stack equalize` evens out the heights.
- `layout stack height <fraction|cycle>` gives the window a share of the column.
- A tab indicator shows which window of a tabbed column is on top. It is a thin bar with one segment per tab.
  It is a separate window drawn over a few points of the column, like the focus border.
- `tab_indicator.enabled = false` turns the indicator off.

## Centering and maximizing

- `layout column center` and `layout column center-visible` scroll the strip.
- `window maximize` grows the column to the whole zone. Run it again to restore it.

## Second strip and swipes

- A second, vertical strip sits at one side of the screen.
- `window send strip vertical` and `window send strip horizontal` move a window between the two.
- `focus` crosses from one strip to the other at the edge.
- Hold Option and swipe with two fingers to move the strip. It settles on the nearest column.
