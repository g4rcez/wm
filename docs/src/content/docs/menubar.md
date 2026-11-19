---
title: "Menu bar icon"
description: "The workspaces that have windows, in the menu bar, and how to change the text with the config or with Lua."
group: Features
order: 11
---
While the daemon runs, the menu bar shows the workspaces that have windows, lowest first. The workspace in focus is written as
`<mode>:<name>`:

```
T:1 2 5      workspace 1 is in focus (tiling); workspaces 2 and 5 have windows
1 S:2 5      workspace 2 is in focus (scrolling)
F:9          the focused window floats, on workspace 9
```

- **Mode:** `T` is the tiling layout, `S` scrolling and `M` master. `F` replaces it while the focused window floats.
- **Order:** workspaces that are numbers come first, from the lowest (`2` before `10`), then the other names in ASCII order
  (`Mail` before `web`). The workspace in focus is always in the list, even when it is empty.
- **What counts as a window:** every window that belongs to the workspace, minimized ones too. A sticky window belongs to no
  workspace, and a special workspace is not listed.
- **Background:** the workspace in focus is drawn on a filled rounded background, with its text cut out of it, so that it stands
  out from the others. The icon is one picture that macOS tints for a light or a dark menu bar, and the text has the regular
  weight. A key sequence that is waiting shows `...`, and a binding mode other than `main` shows its name in an outlined square, as
  before.

## Change it in the config

```lua
wm.config {
  menubar = {
    workspaces = "occupied",    -- "occupied": every workspace with windows, and the one in focus. "current": only the one in focus
    current    = "{mode}:{name}",
    other      = "{name}",
    separator  = " ",
  },
}
```

`current` is the text of the workspace in focus and `other` the text of every other workspace in the list. They can use:

| Word       | Value                                                                                   |
| ---------- | --------------------------------------------------------------------------------------- |
| `{mode}`   | `T`, `S` or `M` for the layout, and `F` for the workspace in focus while its focused window floats |
| `{name}`   | the name of the workspace, cut at 6 characters                                          |
| `{count}`  | how many windows it has                                                                 |
| `{layout}` | `tiling`, `scrolling` or `master`                                                       |

Any other word in braces is a config error. For example, `current = "[{name}:{count}]"` and `separator = " | "` give `1 | [2:3] | 5`.

## Change it with Lua

`wm menubar set <text>` puts a text in the icon, as it is, in place of the workspaces. `wm menubar reset` goes back to the
automatic text. A handler can build the text from the state of wm:

```lua
local function refresh()
  local parts = {}
  for _, workspace in ipairs(wm.query("workspaces")) do
    if #workspace.windows > 0 then parts[#parts + 1] = workspace.name .. "(" .. #workspace.windows .. ")" end
  end
  wm.dispatch("menubar set " .. table.concat(parts, " "))
end

for _, event in ipairs { "window_focus", "window_open", "window_close", "workspace_changed" } do
  wm.on(event, refresh)
end
```

The text stays until `menubar reset`; a reload of the config does not clear it, so a handler that you remove from the config needs a
`wm menubar reset`. `wm help subscribe` lists the events that `wm.on` takes.
