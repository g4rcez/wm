---
title: "Status bar"
description: "Show workspaces, the focused window and the mode in any bar or widget that runs a script."
group: Guides
order: 5
---
wm has no bar of its own. It gives a bar two things: the state now (`wm list --json`) and a stream of events
(`wm subscribe`). Any bar or widget that can run a script can use them. The script below prints one line each time
something changes.

## One line of text

```sh
#!/bin/sh
# [2] is the workspace that you see. 1 and 3 have windows. Then the focused window.
draw() {
  wm list --json | jq -r '
    ([.workspaces[] | select(.visible or (.windows | length) > 0)
      | if .visible then "[\(.name)]" else .name end] | join(" "))
    + "  " + ([.windows[] | select(.focused) | "\(.app_name) — \(.title)"] | first // "")'
}

draw
wm subscribe workspace_changed window_focus window_title window_open window_close \
  mode_changed displays_changed | while read -r _; do draw; done
```

```text
1 [2] 3  Terminal — 1: zsh
```

The script asks for the whole state after each event. That is simple, and it cannot drift: it never merges the events itself.
A script that must not start `wm` on each event can read the events, and the `--snapshot` line, instead:

```sh
wm subscribe --snapshot workspace_changed window_focus | jq -c '
  if .event == "snapshot" then {kind: "state", workspaces: [.state.workspaces[].name]}
  else {kind: .event, workspace: .workspace, app: .app} end'
```

## Which event to follow

| You show | Follow |
|---|---|
| The workspace that you see | `workspace_changed` (`workspace`, `previous`, `monitor`) |
| Workspaces that have windows | `window_open`, `window_close` and `window_moved` |
| The focused window | `window_focus` (`id`, `app`, `title`) and `window_title` |
| The binding mode | `mode_changed` (`mode`) |
| A special workspace | `special_changed` (`workspace`, `monitor`, `visible`) |
| The layout of a workspace | `layout_changed` (`workspace`, `layout`) |
| One bar for each monitor | `displays_changed` (`count`, `monitors`), and the `monitors` list of `wm list --json` |
| An app that asks for attention | `window_urgent` (`id`, `app`, `badge`): the badge on its Dock icon appeared or grew |
| A terminal that a program took over | `window_swallow` (`id`, `terminal`, `workspace`) and `window_unswallow` (`id`, `program`, `workspace`) |
| Config errors | `config_reloaded` |

`displays_changed` also fires once when wm starts, and one dock or undock gives one event. A bar that is drawn on each monitor
redraws on it.

## One reading, no stream

For a bar that polls (a widget that runs a command every second or on a click), use the state once:

```sh
wm list workspaces --json
wm list windows --focused --json
wm list monitors --json
```

## From Lua

The same events reach `wm.on` in your config, so a Lua handler can write a file or call a program that the bar reads. A
handler that takes more than 2 seconds is stopped.

```lua
wm.on("workspace_changed", function(e)
  wm.exec("printf '%s\\n' '" .. e.workspace .. "' > /tmp/wm-workspace")
end)
```

See [CLI](/docs/cli) for the socket protocol, if the bar is a program that wants to talk to wm directly.
