---
title: "Rotate, maximize and floating"
description: "Rotate a layout, maximize and move windows between workspaces, floating windows, native fullscreen and marks."
group: Layouts
order: 5
---
## Rotate

`layout rotate cw` and `layout rotate ccw` move every window one slot around the layout. The slots keep their sizes. This
works in every layout.

## Maximize and moving windows between workspaces

In the scrolling layout, `window maximize` keeps the window in its place in the strip. In the other layouts, it makes
the window fill the work area inside the outer gaps while the others stay tiled behind it. `window fullscreen` fills the
work area with no gaps and no border.

A window that you send to another workspace arrives maximized when that workspace has no other tiled window. When the
workspace has windows, the window joins the layout and `balance` runs. Add `--tile` to join the layout without either.

## Floating windows, native fullscreen and marks

- `window float` moves the window to the middle of its screen. It keeps its size, but a window that fills (about) the whole work
  area gets 60% of it, so you can see it float. Windows that open floating (rules, dialogs) keep their own place.
- `window float on` and `window float off` float or tile the window and never toggle, so a bind can be repeated safely.
  `window center` floats the window (a tiled one first) and puts it in the middle of its monitor, with the same size.
- `move <dir> [points]` and `resize <width|height> <+n|-n>` work on a floating window too: it moves by `points` (40 if you
  leave it out) or changes by n points, keeps its top left corner when it resizes, and stays inside the work area of its
  monitor. At the edge `move` stops; it does not go to the next monitor.
- `window snap <place>` floats the window (a tiled one first) into a part of the work area inside the gaps: `left`, `right`,
  `top`, `bottom`, the four corners, or `center`. The same place again goes on to the next size: half, a third, two thirds
  (`center`: 60%, 80%, 40%).
- `workspace float-all` floats every window of the workspace that the focused monitor shows, each one where it is.
  `workspace float-all off` tiles them all again. With a [tile template](/docs/templates) (`workspace float-all 2+1`,
  `2/3`, `1-over-2`, `corner-tl`, or one of your own), the windows float into its cells instead, the tiled ones in layout order
  first and then the floating ones; a window past the last cell stays where it is. All forms set the state, so a bind can be
  repeated safely. A minimized window or one in macOS fullscreen is left alone.
- `window raise-floating` brings the floating windows of the workspace to the front. `window rescue` moves a floating
  window that is mostly off screen back into the work area of its monitor (a window larger than the area is cut down).
- `window native-fullscreen` enters or leaves macOS fullscreen. A window in macOS fullscreen has a Space of its own, so
  wm leaves it out of the layout until it comes back. `list windows` shows it as `fullscreen`.
  While that Space is in front, macOS shows wm only the windows of that Space, so every other window looks gone. wm asks
  macOS where a window that it cannot see is (the private SkyLight function `CGSCopySpacesForWindows`), and keeps the window,
  with its workspace and its place in the layout, while it is on another Space. It forgets a window only when no Space has it.
  If the function is missing on a future macOS, wm forgets such windows as before.
- `window mark <name>` gives the window a name, and `window unmark [name]` takes it away (without a name, all marks of the
  window). A name belongs to one window, so marking another window with it moves the mark. `focus mark <name>` focuses the
  window, and `--window mark:<name>` acts on it. Marks last until the window closes, and wm saves them with the layout.
