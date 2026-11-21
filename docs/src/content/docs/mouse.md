---
title: "Mouse"
description: "Drag edges to resize tiles, swap tiles, and move or resize any window with a modifier key."
group: Features
order: 8
---
- Drag an edge or corner of a tiled window. When you let go, wm moves the dividers you moved, and the neighbours follow.
- Drag a tiled window by its title bar and drop it on another tile of the same workspace. The two windows swap places. A drop
  anywhere else sends the window back to its tile.
- `wm swap <dir>` does the swap from the keyboard.

## Modifier drag

Set `mouse = { move_modifier = "alt", resize_modifier = "alt" }`. Hold the modifier and drag **anywhere** in a window. You need
no title bar.

- Left button: moves the window.
- Right button: resizes the window from the corner nearest to the pointer.
- A floating window follows the pointer.
- A tiled window that you move swaps places with the tile you drop it on. Anywhere else, it goes back.
- Resizing a tiled window moves the dividers, like the edge drag above.
- wm swallows these clicks, so the app never sees them.
- Both are off until you set them, because Option-click means something in Finder and in many editors.
- The modifiers are chord text: `alt`, `alt+shift`, `ctrl+alt`, and so on.
