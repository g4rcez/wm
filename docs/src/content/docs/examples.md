---
title: "Examples"
description: "Configuration recipes: modes, prefix keys, layouts per workspace, rules, scripts, events and gestures."
group: Guides
order: 1
---
A complete configuration in use, with binds, a prefix key, binding modes, window rules and layouts, is in the author's dotfiles:
[`config/wm/init.lua`](https://github.com/g4rcez/dotfiles/blob/master/config/wm/init.lua). It is a good place to see how the pieces below fit together.

## A resize mode with a key panel

```lua
wm.mode("resize", {
  h = { "resize dir left 50", description = "Divider left" },
  l = { "resize dir right 50", description = "Divider right" },
  j = { "resize dir down 50", description = "Divider down" },
  k = { "resize dir up 50", description = "Divider up" },
  esc = { "mode main", description = "Exit" },
})
wm.bind("alt-shift-r", "mode resize")
```

`resize dir <left|right|up|down> <n>` moves the nearest divider on that axis toward the key, so the same key grows a window on one side of the divider and shrinks the one on the other. It passes to the next split when one is at its limit, and fails when the axis has no divider. In a scrolling layout the key moves a column's trailing edge (right and down grow it); on a floating window right and down grow it, left and up shrink it.

While the mode is active, a panel lists its keys with the text from `description`. See [The key panel](/docs/key-panel#the-key-panel).

`wm.mode(name, binds, options)` takes options as its third argument:

| Option | What it does |
|---|---|
| `once = true` | The mode ends after the first bind of it has run, and the mode before it is back. A bind that goes to another mode itself keeps that mode. |
| `swallow = true` | A key that the mode does not bind is not typed into the app. Without it, such keys go on to the app (a hyper chord with no bind is always swallowed). |

`wm mode back` (or `wm.dispatch("mode back")`) goes back to the mode before the current one. wm keeps the last 8 modes, and
`mode main` forgets them. `back` is not a name for a mode.

```lua
wm.mode("focus", { h = "focus left", l = "focus right", j = "focus down", k = "focus up" }, { once = true, swallow = true })
wm.bind("alt-f", "mode focus")   -- alt-f, then one of h j k l, and the mode is over
```

## One prefix key, then a letter

```lua
local PREFIX = "alt-space>"
wm.bind(PREFIX .. "h", "focus left")
wm.bind(PREFIX .. "l", "focus right")
wm.bind(PREFIX .. "f", "window fullscreen")
wm.bind(PREFIX .. "tab", "switcher")
```

After `alt-space`, wm waits for the next key (or Escape) and shows the keys that can follow.

## A different layout per workspace and per monitor

```lua
wm.workspace("1", { layout = "scrolling" })
wm.workspace("2", { layout = "tiling" })
wm.workspace("web", { monitor = 2, default = true, gaps = { inner = 0, outer = 0 }, border = false })
wm.workspace("code", { layout = "scrolling", monitor = "LG", layout_options = { default_width = 0.7 } })
```

## Window rules

```lua
wm.rule { app = "com.apple.systempreferences", float = true }
wm.rule { app = "net.kovidgoyal.kitty", float = true, size = { 0.62, 0.68 }, center = true }
wm.rule { title = "^Picture in Picture$", float = true }
wm.rule { app = "com.spotify.client", workspace = "9" }
wm.rule { app = "com.apple.Notes", monitor = 2, width = 0.4, focus = false }
```

## Scripts from the shell

```sh
wm list windows                                   # a table of every window
wm list windows --focused --json                  # JSON for scripts
wm pick                                           # click a window: its id, app, title and a wm.rule for it
wm --window app:com.apple.Notes window close      # act on a window by app, title or pid
wm batch 'workspace 2; layout set tiling'         # several commands, stops at the first error
wm set gaps.inner 4                               # change a config value until the next reload
wm notify 'build done' --seconds=3                # a message on screen
```

## React to events

```lua
wm.on("workspace_changed", function(e) wm.log("now on workspace " .. e.workspace) end)
wm.on("window_open", { app = "com.apple.finder" }, function(e)
  wm.dispatch("window float", { window = e.id })
end)
```

## Swipe gestures

```lua
wm.gesture { mods = "alt", direction = "left",  command = "workspace prev", description = "Previous workspace" }
wm.gesture { mods = "alt", direction = "right", command = "workspace next" }
```
