---
title: "Config reference"
description: "Every key of wm.config with its default and what it does."
group: Configure
order: 1
---
All keys are optional. Two `wm.config` calls merge. An unknown key is an error.

For a whole file, see the [author's configuration](https://github.com/g4rcez/dotfiles/blob/master/config/wm/init.lua).

```lua
wm.config {
  layout = "tiling",                   -- scrolling | tiling | master | monocle
  gaps = { inner = 8, outer = 8, smart = false },  -- outer can also be { top=, right=, bottom=, left= }; smart: no gaps around a lone tiled window
  animations = { enabled = true, fps = 120, rate = 16 },  -- fps: frames per second, 30-240, the display caps it (60 Hz screen: 60); rate: spring stiffness, higher is faster
  border = { enabled = true, width = 2, radius = 10, active = "#89b4fa", inactive = "#00000000" },  -- active: one color, or { "#89b4fa", "#cba6f7" } for a gradient (angle = 45, degrees as in CSS)
  focus_follows_mouse = false,         -- or { enabled = true, only_fully_visible = true }: only windows that are fully on screen
  mouse_follows_focus = false,
  start_at_login = true,               -- only when running as wm.app
  mouse = { move_modifier = "alt", resize_modifier = "alt" },   -- both off by default; see Mouse
  wrap_focus = false,                  -- focus, focus next|prev, move and swap go around at the edge, as if you gave --wrap
  workspace_back_and_forth = false,    -- `workspace N` while N is shown goes back to the previous workspace
  tiling    = { split_ratio = 0.5, preserve_split = true,
                split_under_pointer = false,      -- a new window splits the tile under the mouse, not the focused one
                smart_split = false,              -- a new window opens on the side of the tile that the mouse is nearest to
                force_split = "second",           -- where a new window goes in its split: "second" (right, bottom) or "first"
                split_width_multiplier = 1 },     -- 2 or more keeps columns on an ultrawide screen before the first stacked split
  binds     = { long_press_timeout = 0.4,         -- seconds a key is held for a `long_press` bind
                disable_system_cmd_tab = false,   -- true: turn off the Cmd+Tab of macOS while wm runs
                capslock = "hyper" },             -- CapsLock is the hyper modifier (a tap alone is Esc)
  swallow   = { enabled = false, terminals = { "com.mitchellh.ghostty" }, exceptions = {} },   -- a program started in a terminal takes its place; see Window swallowing
  scrolling = { presets = { 0.33, 0.5, 0.66, 1.0 }, default_width = 0.5, center = "on-overflow",
                always_center_single_column = false,      -- a lone column sits in the middle (even with center = "never")
                default_column_display = "normal",        -- "tabbed": every new column is a tab stack
                orientation = "horizontal",               -- "vertical": rows scroll up and down; "auto": vertical on a portrait monitor
                single_window_fit = "fill",               -- a lone column: "fill" the screen (default), or "keep" its width
                visible_columns = 0,                      -- 3: with 2 columns they grow to fill the screen (0 is off)
                preset_heights = { 0.33, 0.5, 0.66 },     -- `layout stack height cycle` walks this list
                sliver_width = 8, sliver_height = 0.9,
                vertical = { side = "right", width = 0.25, row_height = 0.5 } },  -- vertical strip zone (left | right)
  tab_indicator = { enabled = true, position = "left", size = 6, spacing = 3, radius = 3,
                    active = "#89b4fa", inactive = "#9999a599" },   -- the tabs of a tabbed column (left | right | top | bottom)
  switcher  = { thumbnails = true, delay = 0.12, background = "#0000008c", selected = "#89b4fa", max_scale = 0.85 },
  menubar   = { workspaces = "occupied", current = "{mode}:{name}", other = "{name}", separator = " " },  -- the menu bar icon: see Menu bar icon
  prefix    = { menubar = true,   -- key sequences: show "..." in the menu bar icon
                label = { enabled = true, show_keys = true,
                          position = "bottom-center",   -- top-left | top-center | top-right | center | bottom-left | bottom-center | bottom-right
                          offset = { x = 0, y = 0 }, font_size = 11,
                          font = "",                    -- a font name such as "SF Pro Rounded" or "Menlo"; "" is the system font
                          background = "#1e1e2ecc", foreground = "#d6dff5", accent = "#89b4fa" } },
  url       = { allow = {} },          -- extra commands that wm:// URLs may run
}
```

## shortcuts.toml

`shortcuts.toml` sits next to `init.lua` and holds binds as data, so the **Shortcuts…** window of the menu bar menu can add,
edit and delete them. The starter configs of `wm init` have the line `wm.shortcuts()` near the top, which binds every entry of
the file. You choose the mode: use only `init.lua` (delete that line), only the window (keep `init.lua` small), or both.

```toml
[[shortcut]]
keys = "alt-h"                 # a chord, or a sequence: "ctrl-p>h"
action = "focus left"          # a wm command; use `remap = "left"` to type a key instead
description = "Focus left"

[[shortcut]]
keys = "alt-r"
mode = "resize"                # default: main
action = "mode main"
long_press = 0.8               # also: release, repeating, universal, hidden
```

Each `[[shortcut]]` is one `wm.bind` (or `wm.remap`) call, with the same options. The file takes strings, booleans and
numbers, nothing more. An error stops the config load and names the line (`shortcuts.toml line 3: ...`). The window rewrites the
file, so it drops the comments.

In the window, the form for a shortcut asks for the keys, the action and a description. The rarely used options (when it runs,
the mode, every mode, hidden) are behind **More options**. For the keys you can type them (`alt-h`, `ctrl-p>h`) or press
**Record** and press them: the daemon reads the keys, so a key that a bind uses (`alt-h`) is recorded and does not run. A
recording ends with Esc, with the **Stop** button, or when no key comes for a moment after the first one, so a sequence
needs its next key in time (or type it). Recording needs Accessibility (the key tap); a few macOS system shortcuts never
reach wm, so type those. With **Type key**, Record fills the key that the shortcut types.

The action field suggests the wm commands as you type: `foc` offers `focus`, and `layout set ` offers `scrolling`, `tiling`, `master` and `floating`
(the same words as the shell completion). Tab or Return takes the suggestion. The list has the fixed words only: it does not know
the names of your modes or workspaces.

When `init.lua` and the file bind the same keys, the later bind wins. With `wm.shortcuts()` at the top, `init.lua` wins. Move
the line to the end to let the file win. `wm doctor` lists every such pair as a conflict, and warns when `shortcuts.toml` exists
and `init.lua` never calls `wm.shortcuts()`. An `init.lua` from before this feature does not have the line: add it yourself.
