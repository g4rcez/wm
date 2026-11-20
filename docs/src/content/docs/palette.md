---
title: "Command palette"
description: "One panel to find windows, apps, browser tabs, wm commands and menu items."
group: Features
order: 5
---
`wm.bind("alt-p", "palette")` opens one text field above a list. Without a prefix it lists the running apps, each
followed by its windows; typing finds windows (by title, app, workspace and mark), apps and tabs. Every row has an icon: the
app icon, or a small window drawn for the wm command. `>` finds wm commands:
Tab puts a command in the field, and after the command name the list shows what can follow (workspaces, modes, marks,
the values that the command takes). `/` finds the menu items of the app that was in front, with its icon. A fuzzy match is enough:
`ffx` finds Firefox. Up and down move (in the lists of apps and windows Tab and Shift-Tab move too; in the `>` list Tab
completes), Return runs the row, and Escape closes. `palette commands` starts in the
commands list. If a command is not in the list, type it in full after `>` and press Return.

With `switcher.thumbnails` on and the Screen Recording permission given (the same as the window switcher), the lists of apps and
windows show a preview on the right: the picture of the selected window, or of the most recent window of the selected app.
A window of another workspace has a picture too: wm captures windows that it parked off screen.

**Tabs.** Typing also finds tabs. `palette tabs` lists all of them, and an app that has no tabs shows its windows there,
because a window is its tab. The apps go by how recently you used them, so the app that you used last is at the top; an
app with tabs (a browser, Rex) shows its tabs and not its windows. Return selects the tab and focuses its window, on
the workspace where the window is. The sources:

- **Chromium browsers** that run: Chrome, Brave, Edge, Helium, Arc, Vivaldi, Chromium and yab. A row is the title and the
  address of a tab, so `gith` finds a tab by its URL. wm asks the browser through Apple events (see Permissions).
- **Safari:** the title and the address of every tab. wm asks Safari through Apple events too. Safari gives its tabs no
  identifier, so wm names a tab by its place in the window: if you move or close tabs between the list and Return, the
  selection can land on the tab that took the place.
- **Rex:** the tabs of every session, with the name of the session. The app goes to the tab when its Remote Control
  setting is on; without it wm can only make the tab the active one of the session.
- **tmux:** every window of the default server, with its session, program and directory. wm switches the client that shows
  that session (else the first client) to the window, and focuses the terminal of the client.

wm reads the tabs when the palette opens, and shows the ones of the last time until the new ones are there. It starts no
browser and no server to do so. Limits: Firefox is not read. A tmux window needs an attached client. For tmux
inside Rex, wm focuses the most recent Rex window, not the Rex tab that holds the client. When two windows of a browser show
a tab with the same title, wm can focus the other window; the tab is selected all the same.

Drag the panel by its background (the header or the preview) to move it. wm keeps the spot as a fraction of the
screen, and opens the palette there on the screen that has the mouse. `palette reset` forgets the spot, so the palette is
centered, a little above the middle, again: run it from the `>` list or bind it. Cmd-0 does the same while the palette is
open.

**Cmd+Tab.** `palette --cmdtab` works like the app switcher of macOS, with the thumbnails of the palette:

```lua
wm.bind("cmd-tab", "palette --cmdtab")
wm.bind("cmd-shift-tab", "palette --cmdtab --reverse")
```

It lists the running apps (the most recent first), selects the previous one, and moves with Tab and Shift+Tab (or the arrow
keys) while you hold Cmd. Letting go of Cmd, or Return, switches to the app, and Escape cancels. Any other key closes the
palette and goes on to the app. wm swallows Tab and the arrow keys while this palette is open, so the macOS switcher does not
open on top of it. (The normal palette passes every key to its text field.)

The panel takes the keyboard without making wm the active app, so the menu items belong to the app you came from.
While the palette is open no key bind runs. Remaps still do: `wm.remap("hyper-j", "down")` moves the selection.
