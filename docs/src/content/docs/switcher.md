---
title: "Switcher and overview"
description: "A switcher with a picture of each window, and an overview of the workspaces."
group: Features
order: 1
---
```lua
wm.bind("alt-tab", "switcher")
wm.bind("alt-o", "overview")
```

Hold Alt and press Tab to open a miniature of the focused workspace with a picture of each window.

- Tab and Shift+Tab move the selection.
- The arrow keys move it across the miniature.
- Letting go of Alt focuses the window. Return focuses too.
- Escape cancels.
- The header names the selected window and its workspace.
- The pictures fill their tiles. What does not fit is cropped.
- `switcher = { thumbnails = false }` turns the pictures off.
- The look (blur, corners, colors, light or dark) is the same as every other overlay: see [Appearance](/docs/appearance).
  The dim layer behind the overview is `appearance.background`.

`switcher --all` lists the windows of every workspace as a row of tiles, most recent first (the scope of a Cmd-Tab
switcher). Choosing a tile shows the workspace of that window.

In the switcher and in the overview, Cmd+W closes the selected window. The panel stays open without it.

`overview` darkens the screen (as the overview of Niri does) and shows every workspace as a small copy of its screen, one under
the other in one column.

- The workspace that you are on is in the middle. The ones before and after it show above and below. The column scrolls.
- There is one copy for each workspace that holds windows or that a monitor shows, and an empty one at the end for a new workspace.
- A copy shows its workspace in the layout that it has. A scrolling workspace is the whole strip of columns, with a dashed outline around the part that is on screen. A tiling workspace is the tiles of the screen.
- Every window is a card with its picture, the icon of its app and its title.
- A floating window has a dashed edge. The selected card has a ring.
- The name of the workspace is above its copy, with a dot when the focused monitor shows it.
- A search field is at the top.
- The overview fades in and out in 0.12 seconds. Nothing zooms or moves while it does.

`overview` opens or closes it. `overview open` and `overview close` do only one of the two. The swipes with 4 fingers up and
down use them (see [Gestures](/docs/gestures)).

```lua
wm.config { overview = {
  zoom = 0.5,                  -- a workspace is its screen times this: 0.2 to 0.75
  gap = 48,                    -- points between two workspaces
} }
```

- **Search:** type, and the cards that do not match (their title, app, workspace name or marks) are dimmed.
  - The selection goes to the most recent match. The number in the field shows how many there are.
  - Backspace deletes a letter.
  - Escape always closes the overview, also when nothing matches.
- **Keys:**
  - The arrow keys and Tab move the selection. Up and down also go to the workspace above and below.
  - Ctrl with `h` `j` `k` `l` (vim) or `a` `s` `w` `d` (WASD) moves like the left, down, up and right arrows. Plain letters go into the search.
  - Return focuses the window and shows its workspace. Cmd+W closes it.
  - The column scrolls to put the workspace of the selection in the middle.
- **Mouse:**
  - Move the pointer onto a card to select it. A red button appears at its corner that closes the window.
  - Click a card to focus it.
  - A click on the dark backdrop closes the overview. The click goes on to what is under it (so you can start a screenshot).
  - The screenshot shortcuts of macOS (Cmd+Shift+3, 4, 5, 6) work while the overview or the switcher is open. They go to macOS and the panel stays.
  - The mouse wheel or the trackpad scrolls the column.
- **Move a window:** **drag a card onto another workspace to move the window there.**
  - The last one, an empty screen, is a new workspace with the first unused number.
  - The focus and the shown workspace stay as they are.

The pictures come from Screen Recording.

- A window that wm parked off screen (another workspace) is captured with a private macOS call (SkyLight).
- wm also keeps the last picture of every window that was on screen.
- If both fail, for example an app that draws nothing while it is parked, the card shows the icon of the app.
