---
title: "First five minutes"
description: "A small init.lua to start from: gaps, a border, vim-style focus keys and workspace keys."
group: Start
order: 3
---
The setup window of the first run can write a starter config for you (see [First run](/docs/install#first-run)).

## Start from a template

In a terminal, run `wm init [omarchy|osx|windows|i3|hyprland|niri]` to start from the keys of another system.

- Without a name, it writes the [Omarchy](https://omarchy.org/manual/hotkeys/) keys. The setup window uses the same default.
- It asks for the main modifier: `alt`, `cmd`, `ctrl` or `hyper`. `--mod=alt` skips the question.
- It writes the binds to `~/.config/wm/shortcuts.toml`, and `~/.config/wm/init.lua` with the settings, the modes and the line `wm.shortcuts()` (see [shortcuts.toml](/docs/config#shortcutstoml)). The Shortcuts window edits the binds.
- `--lua` writes everything to `init.lua`, as Lua, and no `shortcuts.toml`.
- If one of the files exists, `wm init` prints the template and leaves the files alone. `--force` replaces them.

The Omarchy template uses `cmd` as its main modifier, in the place of Super. `alt` and `ctrl` also work. `hyper` does not:
Omarchy also has binds with Super+Alt and Super+Ctrl, and those use `cmd` when the main modifier is that key.

It keeps the keys that have a meaning on macOS:

- `mod-space` opens the palette.
- `mod-w` or `mod-q` closes a window.
- `mod-N` and `mod-shift-N` move between workspaces and send windows.
- `mod-arrows` focus and `mod-shift-arrows` swap.
- `mod-l` cycles the layouts (tiling, scrolling, floating).
- `mod-s` and `mod-backtick` show the scratchpad and the Quake console (special workspaces).
- `mod-return` opens a terminal.

The panels, menus and Linux apps of Omarchy that macOS has no key for are left out.

## Write it by hand

Or create `~/.config/wm/init.lua` by hand. This is a small config to start from:

```lua
wm.config {
  layout = "tiling",
  gaps = { inner = 8, outer = 8 },
  border = { enabled = true, width = 2, active = "#89b4fa" },
}

-- Focus and move with vim keys
wm.bind("alt-h", "focus left --wrap")
wm.bind("alt-j", "focus down --wrap")
wm.bind("alt-k", "focus up --wrap")
wm.bind("alt-l", "focus right --wrap")
wm.bind("alt-shift-h", "swap left")
wm.bind("alt-shift-l", "swap right")

-- alt-N shows workspace N, alt-shift-N sends the window there
for n = 1, 9 do
  wm.bind("alt-" .. n, "workspace " .. n)
  wm.bind("alt-shift-" .. n, "window send workspace " .. n)
end

wm.bind("alt-f", "window fullscreen")
wm.bind("alt-space", "window float")
wm.bind("alt-s", "layout set scrolling")
wm.bind("alt-t", "layout set tiling")
wm.bind("alt-shift-c", "daemon reload")
```

## Reload

Save the file. wm reloads it on its own. `wm daemon reload` does the same by hand.

- Each reload shows a macOS notification: `Config reloaded: init.lua`, or `wm: config error` with the message.
- The first notification asks you to allow notifications for wm. If you say no, wm still reloads. The answer is in the menu bar
  and in `wm logs`.
- A new notification replaces the last one, so saving often does not fill Notification Center.
- The load when wm starts shows none.
- If the new file has an error, the old config stays active. The error shows in the notification, in the menu bar and in the
  output of `wm daemon reload`.

The config path is `~/.config/wm/init.lua`, or `$XDG_CONFIG_HOME/wm/init.lua`, or the file named by `$WM_CONFIG`.

Open a few windows and try the keys. Then run `wm help` to see every command.
