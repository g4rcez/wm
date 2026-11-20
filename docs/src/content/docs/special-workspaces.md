---
title: "Special workspaces"
description: "Scratchpads: one key shows a workspace over the others, the same key hides it."
group: Features
order: 9
---
```lua
wm.bind("alt-s", "workspace special term")                     -- show or hide special:term on the focused monitor
wm.bind("alt-shift-s", "window send workspace special:term")   -- send the window there and show it
wm.workspace("special:term", { layout = "scrolling" })
wm.rule { app = "com.spotify.client", workspace = "special:music" }
```

With `on_empty`, a special workspace starts its program the first time you show it, which makes a scratchpad out of one key:

```lua
wm.workspace("special:term", { layout = "scrolling", on_empty = "/Applications/Ghostty.app/Contents/MacOS/ghostty" })
wm.workspace("special:notes", { on_empty = { cmd = "open -a Notes", app = "Notes", float = true, center = true } })
```

The command runs only when the workspace has no window. The window that it opens goes to that workspace, so the scratchpad shows
what you started even when you switched away before it opened. See [Window and workspace rules](/docs/rules).

A special workspace takes the work area with 5% free on each side (`special.size`, 0.9 by default). It hides when you run
the command again, when you switch to a workspace, when its last window goes away, and when a window of the normal
workspace on the same monitor gets the focus. While it is shown, the windows of the normal workspace are parked. macOS
brings every window of the active app forward, so wm cannot keep the special windows above them.

```lua
wm.config { special = {
  size = 0.8,                       -- a fraction of the work area, 0.5 to 1
  backdrop = "#00000066",           -- a dim layer on the monitor, behind the windows; "" (the default) is none
  hide_on_other_monitor = true,     -- a normal window that gets the focus on another monitor hides it too
} }
```
