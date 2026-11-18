---
title: "First five minutes"
description: "A small init.lua to start from: gaps, a border, vim-style focus keys and workspace keys."
group: Start
order: 3
---
The setup window of the first run can write a starter config for you (see [First run](/docs/install#first-run)).
To start from the keys of another system in a terminal, run `wm init <osx|windows|i3|hyprland|niri>`. It asks for the main modifier
(`alt`, `cmd`, `ctrl` or `hyper`; `--mod=alt` skips the question) and writes `~/.config/wm/init.lua`. When that file exists,
`wm init` prints the template and leaves the file alone; `--force` replaces it.

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

Save the file. wm reloads it on its own, and `wm daemon reload` does the same by hand. Each reload shows a notification of
macOS: `Config reloaded: init.lua`, or `wm: config error` with the message. The first one asks you to allow notifications for
wm; if you say no, wm still reloads and the answer is in the menu bar and in `wm logs`. A new notification replaces the last
one, so saving often does not fill Notification Center. The load when wm starts shows none. If the new file has an error, the
old config stays active and the error shows in the notification, in the menu bar and in the output of `wm daemon reload`.

The config path is `~/.config/wm/init.lua`, or `$XDG_CONFIG_HOME/wm/init.lua`, or the file named by `$WM_CONFIG`.

Open a few windows and try the keys. Then run `wm help` to see every command.
