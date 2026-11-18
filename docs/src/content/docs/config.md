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
  layout = "tiling",                   -- scrolling | tiling | master
  gaps = { inner = 8, outer = 8, smart = false },  -- outer can also be { top=, right=, bottom=, left= }; smart: no gaps around a lone tiled window
  animations = { enabled = true, rate = 14 },  -- rate: spring stiffness; a long move ends in about 10 / rate seconds
  border = { enabled = true, width = 2, radius = 10, active = "#89b4fa", inactive = "#00000000" },
  focus_follows_mouse = false,         -- or { enabled = true, only_fully_visible = true }: only windows that are fully on screen
  mouse_follows_focus = false,
  start_at_login = true,               -- only when running as wm.app
  mouse = { move_modifier = "alt", resize_modifier = "alt" },   -- both off by default; see Mouse
  wrap_focus = false,
  workspace_back_and_forth = false,    -- `workspace N` while N is shown goes back to the previous workspace
  tiling    = { split_ratio = 0.5, preserve_split = true,
                split_under_pointer = false,      -- a new window splits the tile under the mouse, not the focused one
                smart_split = false,              -- a new window opens on the side of the tile that the mouse is nearest to
                force_split = "second",           -- where a new window goes in its split: "second" (right, bottom) or "first"
                split_width_multiplier = 1 },     -- 2 or more keeps columns on an ultrawide screen before the first stacked split
  binds     = { long_press_timeout = 0.4,         -- seconds a key is held for a `long_press` bind
                disable_system_cmd_tab = false,   -- true: turn off the Cmd+Tab of macOS while wm runs
                capslock = "hyper" },             -- CapsLock is the hyper modifier (a tap alone is Esc)
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
  prefix    = { menubar = true,   -- key sequences: show "..." in the menu bar icon
                label = { enabled = true, show_keys = true,
                          position = "bottom-center",   -- top-left | top-center | top-right | center | bottom-left | bottom-center | bottom-right
                          offset = { x = 0, y = 0 }, font_size = 11,
                          font = "",                    -- a font name such as "SF Pro Rounded" or "Menlo"; "" is the system font
                          background = "#1e1e2ecc", foreground = "#d6dff5", accent = "#89b4fa" } },
  url       = { allow = {} },          -- extra commands that wm:// URLs may run
}
```
