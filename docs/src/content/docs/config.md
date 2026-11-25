---
title: "Configuration"
description: "The config files, key binds, window rules, gestures, appearance and examples."
group: Configure
order: 1
---
wm reads `init.lua` and `shortcuts.toml` from `~/.config/wm/`. The Lua functions are in the [Lua API](/docs/lua-api). For a whole file, see the [author's configuration](https://github.com/g4rcez/dotfiles/blob/master/config/wm/init.lua).

## Files and loading

- `wm init <name>` writes a starter config (`--lua` writes the keys to `init.lua` as Lua; `--mod=alt` sets the main modifier; `--force` runs it again). See [Getting started](/docs/getting-started).
- `wm daemon reload` loads the config again, and so does saving a file. A mistake shows in the menu bar, in the command output and in `wm logs`.
- `wm config check` checks the config without applying it. `wm set gaps.inner 4` changes a value until the next reload.
- All `wm.config` keys are optional. Two `wm.config` calls merge. An unknown key is an error.

### wm.config keys

| Key | Default | Meaning |
|---|---|---|
| `layout` | `"tiling"` | `scrolling`, `tiling`, `master` or `monocle`. |
| `gaps` | `{ inner = 8, outer = 8, smart = false }` | `outer` can be `{ top=, right=, bottom=, left= }`. `smart`: no gaps around a lone tiled window. |
| `animations` | `{ enabled = true, fps = 120, rate = 16 }` | Every animation of wm, with a master switch. `fps`: 30 to 240, capped by the display. `rate`: spring stiffness. Sub-tables `windows`, `workspaces`, `special`, `overlays` (see Animations below). |
| `border` | `{ enabled = true, width = 2, radius = 10, active = "#89b4fa", inactive = "#00000000" }` | `active` can be `{ "#89b4fa", "#cba6f7" }` for a gradient (`angle = 45`). |
| `dim` | `{ enabled = false, amount = 0.25, color = "#000000" }` | Darkens the windows without the focus. See [Features](/docs/features#dim). |
| `pip` | `{ corner = "bottom-right", size = 0.25, fps = 30, hide_when_visible = true }` | The live pictures of `window pip`. See [Features](/docs/features#picture-in-picture). |
| `focus_follows_mouse` | `false` | Or `{ enabled = true, only_fully_visible = true }`. |
| `workspaces` | none | The mode, the limit, or both. `"emulated"` (the mode, default) hides the windows of other workspaces at a screen corner; `"native"` makes each workspace a macOS desktop (see [Native workspaces](#native-workspaces)). A number is the most workspaces there can be: `workspace 7` with `workspaces = 6` is an error, and `wm workspaces balance` spreads the windows over that many. A table has both: `{ mode = "native", max = 6 }`. Names that are not numbers are free. |
| `mouse_follows_focus` | `false` | Moves the cursor to the center of a window that a command focuses. Switching workspaces never moves it. |
| `start_at_login` | `true` | Only when running as wm.app. |
| `mouse` | `{ move_modifier = "alt", resize_modifier = "alt" }` | Both are off by default. |
| `wrap_focus` | `false` | `focus`, `move` and `swap` wrap at the edge, as with `--wrap`. |
| `workspace_back_and_forth` | `false` | `workspace N` while N is shown goes back to the previous one. |
| `tiling` | `{ split_ratio = 0.5, preserve_split = true, split_under_pointer = false, smart_split = false, force_split = "second", split_width_multiplier = 1 }` | `split_under_pointer`: a new window splits the tile under the mouse. `smart_split`: it opens on the side nearest to the mouse. `force_split`: `"second"` (right, bottom) or `"first"`. `split_width_multiplier` 2 or more keeps columns on an ultrawide screen. |
| `binds` | `{ long_press_timeout = 0.4, disable_system_cmd_tab = false, capslock = "hyper", event_level = "session" }` | See Key binds. |
| `commands` | `{ mode = "normal", timeout = 800 }` | Sequences, see Key binds. Same as `wm.commands`. |
| `keyboards` | every keyboard on | See Key binds. |
| `urgent` | `{ enabled = true, interval = 2 }` | Reads Dock badges every `interval` seconds, for `focus urgent` and `window_urgent`. |
| `swallow` | `{ enabled = false, terminals = { "com.mitchellh.ghostty" }, exceptions = {} }` | See [Features](/docs/features). |
| `scrolling` | see below | |
| `tab_indicator` | `{ enabled = true, position = "left", size = 6, spacing = 3, radius = 3, active = "#89b4fa", inactive = "#9999a599" }` | Tabs of a tabbed column. `position`: left, right, top or bottom. |
| `switcher` | `{ thumbnails = true, delay = 0.12, max_scale = 0.85 }` | |
| `menubar` | `{ workspaces = "occupied", current = "{mode}:{name}", other = "{name}", separator = " ", modes = { tiling = "T" } }` | Menu bar icon. See [Features](/docs/features). |
| `prefix` | `{ menubar = true, label = { ... } }` | `menubar`: show "..." in the icon while a sequence waits. `label`: the key panel (below). |
| `trackpad` | see Gestures | |
| `appearance` | `{ style = "native", theme = "system", density = "comfortable" }` | See Appearance. |
| `url` | `{ allow = {} }` | Extra commands that `wm://` URLs may run. See [CLI](/docs/cli). |

`scrolling` keys: `presets = { 0.33, 0.5, 0.66, 1.0 }`, `default_width = 0.5`, `center = "on-overflow"`, `always_center_single_column = false` (a lone column is centered), `default_column_display = "normal"` (`"tabbed"`: every new column is a tab stack), `orientation = "horizontal"` (`"vertical"`: rows scroll up and down; `"auto"`: vertical on a portrait monitor), `single_window_fit = "fill"` (or `"keep"` the width), `visible_columns = 0` (3: with 2 columns, they grow to fill the screen), `preset_heights = { 0.33, 0.5, 0.66 }` (`layout stack height cycle` walks it), `sliver_width = 8`, `sliver_height = 0.9`, `vertical = { side = "right", width = 0.25, row_height = 0.5 }` (`side`: left or right).

`prefix.label` (the key panel): `enabled = true`, `show_keys = true`, `position = "bottom-center"` (also `top-left`, `top-center`, `top-right`, `center`, `bottom-left`, `bottom-right`), `offset = { x = 0, y = 0 }`, `font_size = 11`, `font = ""` (the system font).

### Animations

All the animations of wm are in `animations`. `animations.enabled = false` is the master switch: it turns off every animation, the fades of the overlays too. Each kind has its own `enabled`.

| Animation | Key | What it does |
|---|---|---|
| Window moves | `animations.windows` (`enabled`, `rate`) | A window that opens, closes, resizes or moves in the layout glides to its place. |
| Workspace switch | `animations.workspaces` (`enabled`, `rate`, `style`) | The windows that a workspace switch shows slide in. Off by default (`style = "none"`). |
| Special workspace | `animations.special` (`enabled`, `rate`, `style`) | The same for a special workspace toggle. |
| Overlays | `animations.overlays` (`enabled`, `duration`) | The fades of the window switcher, the overview and the cheatsheet panel. `duration` is in seconds, 0 to 2 (default 0.12). `appearance.animation` is the same setting and is used when `duration` is not set. |

```lua
wm.config { animations = {
  enabled    = true,                                -- the master switch
  fps        = 120,
  rate       = 16,                                  -- spring stiffness for all the moves
  windows    = { enabled = true, rate = 20 },       -- a window that opens, closes or resizes
  workspaces = { style = "slide", rate = 14 },      -- windows shown by a workspace switch
  special    = { style = "slidevert" },             -- windows shown by a special workspace toggle
  overlays   = { enabled = true, duration = 0.12 }, -- the fades of the switcher, the overview and the cheatsheet
} }
```

`style` is `"none"` (the default: windows jump), `"slide"` (new windows come in from the right, or the left for an earlier workspace) or `"slidevert"` (from the bottom). wm moves real windows, so it cannot fade them.

`wm animations` lists the kinds and whether each one runs. `wm animations off` and `wm animations on` switch all of them; `wm animations off overlays` switches one kind (`windows`, `workspaces`, `special` or `overlays`). The change lasts until the next reload, as with `wm set`.

### shortcuts.toml

`shortcuts.toml` holds binds as data. The **Shortcuts…** window of the menu bar menu can add, edit and delete them (it rewrites the file and drops the comments). `wm.shortcuts()` in `init.lua` binds every entry; the starter configs have it near the top.

```toml
[[shortcut]]
keys = "alt-h"                 # a chord, or a sequence: "ctrl-p>h"
action = "focus left"          # a wm command; use `remap = "left"` to type a key instead
description = "Focus left"
```

- Each `[[shortcut]]` is one `wm.bind` (or `wm.remap`) call, with the same options (`mode`, `long_press`, `release`, `repeating`, `universal`, `hidden`). The file takes strings, booleans and numbers only.
- An error stops the config load and names the line (`shortcuts.toml line 3: ...`).
- In the window, type the keys or press **Record** (needs Accessibility).
- When `init.lua` and the file bind the same keys, the later bind wins. With `wm.shortcuts()` at the top, `init.lua` wins. `wm doctor` lists such conflicts.

## Key binds

A chord is modifiers and a key joined by `-` or `+`: `alt-h`, `cmd+ctrl-2`.

- Modifiers: `alt` (or `opt`), `cmd`, `ctrl`, `shift` and `hyper`.
- Key: a letter, a digit, or one of `esc`, `space`, `tab`, `enter`, `backspace`, `left`, `right`, `up`, `down`, `minus`, `equal`, `comma`, `period`, `slash`, `backslash`, `semicolon`, `quote`, `backtick`, `leftsquarebracket`, `rightsquarebracket`, `f1` to `f20`, `home`, `end`, `pageup` and `pagedown`.
- The last key can also be the symbol: `"cmd-shift-["` is `"cmd-shift-leftsquarebracket"`. `+` is always a separator, so type `shift-equal`.
- `wm.bind("cmd-h", "")` swallows a key. `wm list binds` (and `--json`) shows every bind.

### Bind options

`wm.bind(chord, action, options)` takes a table as its third argument. Inside `wm.mode`, an action can be a table too: `h = { "resize width +50", description = "Wider" }`.

| Option | What it does |
|---|---|
| `description` | Text for `wm list binds` and the key panel. |
| `repeating = false` | Run once per press. Without it, a held key repeats the action. |
| `repeating = true` | A second bind of the same chord: it runs for each repeat while the key is held, and the plain bind runs only when the key goes down. |
| `release = true` | Run when the key comes up. |
| `long_press = true` | Run when the key is held for `binds.long_press_timeout` seconds. A short press runs the normal bind. |
| `long_press = 0.8` | The same, with a wait of its own: 0.1 to 3 seconds. |
| `universal = true` | The bind works in every mode (`submap_universal` is the same). The mode name `*` is reserved. |
| `hidden = true` | Leave the key out of the key panel and the cheatsheet. |

`release`, `long_press` and `repeating = true` need a single chord, and `release` and `long_press` cannot be combined with each other or with `repeating`.

If the macOS app switcher opens on top of yours, set `binds = { disable_system_cmd_tab = true }`. wm turns off the macOS Cmd+Tab while it runs. If wm is killed with `kill -9`, Cmd+Tab stays off until you log out.

### Modes

```lua
wm.mode("resize", {
  h = { "resize dir left 50", description = "Divider left" },
  l = { "resize dir right 50", description = "Divider right" },
  esc = { "mode main", description = "Exit" },
}, { timeout = 1000 })
wm.bind("alt-shift-r", "mode resize")
```

| Mode option | What it does |
|---|---|
| `once = true` | The mode ends after the first bind of it has run, and the mode before it is back. |
| `timeout = 800` | The mode ends after 800 ms (100 to 10000) without a command. The wait for the first command has no timeout. |
| `swallow = true` | A key that the mode does not bind is not typed into the app. |

`wm mode back` goes to the mode before the current one (wm keeps the last 8). `mode main` forgets them. `resize dir <left|right|up|down> <n>` moves the nearest divider on that axis, and fails when there is none.

### Sequences

A bind can be a sequence of chords separated by `>`: `"ctrl-p>h"`, `"alt-space > t > n"`.

```lua
wm.bind("alt-space>h", "focus left")
wm.bind("alt-space>tab", "switcher")
```

- wm takes the first chord from every app. A sequence waits for the next key or Escape, with no timeout. A key that continues no sequence cancels it and is swallowed.
- In one mode, a chord cannot be a bind and also the start of a sequence, and a sequence cannot start a longer one (`a>b` and `a>b>c`). Both are config errors.
- The macOS screenshot shortcuts (Cmd+Shift+3, 4, 5, 6) go to macOS.

A sequence ends after one command. `wm.commands = { mode = "persistent", timeout = 800 }` (`mode`: `"normal"` or `"persistent"`; `timeout`: 100 to 10000 ms) keeps the keys after the prefix active until `timeout` ms pass without a command, or Escape. The first wait has no timeout. A key that is not a command of the prefix ends the sequence and goes on to the app. `layers = { ["hyper-w"] = { mode = "persistent", timeout = 500 } }` sets `mode` and `timeout` per first chord.

### Key panel

While a mode other than `main` is active, or a prefix waits, a panel lists the keys you can press, with their `description` or else their command. Binds with `hidden = true` are left out. A key that starts a longer sequence shows `…`. `prefix.label.show_keys = false` leaves only the mode chip. The hints, scroll and select modes use the same panel.

### Hyper key and remaps

With `binds = { capslock = "hyper" }` (the default), CapsLock is the `hyper` modifier. Hold it with a key to make a chord such as `hyper-k`. A tap alone types Esc. A hyper chord that nothing binds is swallowed.

```lua
wm.remap("hyper-k", "up")                    -- types Up; the key repeats
wm.bind("hyper-w>1", "workspace 1")          -- Caps+w, then 1
wm.bind("hyper-s>p", "key press play")       -- a media key
wm.bind("hyper-v", "mode vim")               -- a layer that stays on: a mode
wm.mode("vim", { h = { remap = "left" }, l = { remap = "right" }, esc = "mode main" })
```

- `wm.remap(chord, key [, options])` types `key` when `chord` is pressed. It takes one chord and works everywhere. Extra modifiers go with it: after `wm.remap("hyper-h", "left")`, `hyper-shift-h` types `shift-left`.
- `wm.press(key)` and `wm key press <key>` type a key for the system: a chord or a media key (`volume_up`, `volume_down`, `mute`, `play`, `next`, `previous`, `brightness_up`, `brightness_down`). `wm key send` types into one app.
- `binds = { event_level = "hid" }` makes wm listen with a HID event tap (before the session tap) and type its keys as if a keyboard sent them. Use it when a remap works here but not on a Mac that you control from this one (Universal Control, a software KVM). It is not a promise: if the tool forwards the keyboard before any event tap sees it, only a virtual keyboard driver such as Karabiner's can change what the other Mac gets. See [Troubleshooting](/docs/troubleshooting).
- Secure Keyboard Entry (password fields, some terminals) blocks every key tap, so hyper chords do nothing there.
- `keyboards` turns a keyboard on or off for wm, by name or `vendor:product` (the id wins), and decides where CapsLock becomes hyper. `wm query keyboards` lists them:

```lua
wm.config { keyboards = { default = true, ["1209:2201"] = true, ["Some USB Receiver"] = false } }
```

### Replace Karabiner-Elements

Quit Karabiner-Elements first and stop it from starting at login, because it takes the keyboard before wm sees it. Put the binds in `~/.config/wm/hyper.lua`, add `require("hyper")` at the end of `init.lua`, and run `wm daemon reload`.

- CapsLock to hyper (Esc when alone): `binds = { capslock = "hyper" }`. Hyper + key types another key: `wm.remap`. Open an app: `function() wm.exec("open -a Spotify") end`. A sublayer (hyper + `w`, then a key): `wm.bind("hyper-w>1", "workspace 1")`.
- Key names differ: `return_or_enter` is `enter`, `spacebar` is `space`, `escape` is `esc`, `hyphen` is `minus`, `left_arrow` is `left`.
- wm has no per-app or per-device rules, no left and right modifier distinction, no `fn` key, no simultaneous keys and no mouse remaps.
- If wm crashes, CapsLock stays mapped to F18 until wm starts again; to put it back: `hidutil property --set '{"UserKeyMapping":[]}'`.

## Hotkeys and gestures

### Starter templates

`wm init <name>` writes the keys of one system to `shortcuts.toml`: `omarchy` (default, `mod` is `cmd`), `osx` (`ctrl`), `windows`, `i3`, `hyprland` and `niri` (`alt`). Only `niri` starts with the scrolling layout; the others tile. All use `mod-N` (N is 1 to 9) to go to workspace N and `mod-shift-N` to send the window there. Run `wm list binds` to see every key.

### Trackpad gestures

`wm.gesture { mods, direction, command }` runs a command when you swipe with two fingers while you hold modifiers.

- `mods` is one or more of `alt`, `shift`, `ctrl` and `cmd` (`"alt+shift"`). `direction` is `left`, `right`, `up` or `down`.
- The command is a string or a Lua function. It runs once per swipe, after the scroll has gone `threshold` points (10 to 2000, default 100).

Swipes with 3 or 4 fingers work without a config. `trackpad.fingers` is 4 (default) or 3.

Built-in swipes: fingers left `workspace next`, right `workspace prev`, up `overview open`, down `overview close`.

```lua
wm.config { trackpad = { fingers = 4, scroll_fingers = 4, speed = 1 } }   -- enabled = false turns all of this off
wm.gesture { fingers = 4, direction = "up", command = "overview" }
```

- On a scrolling workspace, a sideways swipe scrolls the strip. `scroll_fingers` is the finger count that does it (default: the same as `fingers`; 0 is never). `speed` (0.1 to 10) sets how far it moves. A `wm.gesture` for the same fingers and direction replaces a built-in swipe.

### Title bar gestures

Two fingers on the title bar of a window, as in Swish. They are off by default.

```lua
wm.config { trackpad = { title_bar = true, title_bar_height = 40, pinch = true } }
```

| Gesture | Floating window | Tiled window |
|---|---|---|
| swipe left / right (`window swipe left`) | snaps to the left / right half | moves left / right in the layout |
| swipe up | fills the screen, or goes back | maximizes, or goes back |
| swipe down | minimizes | minimizes |
| pinch in (`window close`) | closes | closes |
| pinch out (`window fullscreen`) | fills the screen, or goes back | same |

- `title_bar_height` (10 to 200, default 40) is how many points from the top of the window count as its title bar. `pinch = false` turns the pinch off and keeps the swipes. A pinch needs exactly two fingers and does not work with a Magic Mouse.
- `wm.gesture { zone = "title_bar", direction = "pinch-in", command = "window minimize" }` replaces the built-in gesture. It takes no `mods` and no `fingers`. `direction` can also be `pinch-out`.

## Rules

### Window rules

`wm.rule { ... }` needs at least one of `app`, `title`, `role`, `subrole` or `identifier`. A window must match all the fields. Rules apply in order, and later values win.

| Field | Meaning |
|---|---|
| `app` | Bundle id or app name. Exact match, case does not matter. |
| `title` | A regular expression, matched anywhere in the title. |
| `role`, `subrole` | The Accessibility role and subrole, for example `subrole = "AXDialog"`. Exact match, case does not matter. |
| `identifier` | A regular expression, matched anywhere in the `AXIdentifier`. |
| `float` | Open the window floating. |
| `workspace`, `layout` | Where it opens, and the layout of that workspace if it is empty. |
| `size`, `center` | For floating windows: `{ width, height }` as fractions of the screen (or points above 1), and centering. |
| `maximize` | Open maximized. |
| `width` | Column width in the scrolling layout, as a fraction of the screen. |
| `monitor` | Open on the workspace that this monitor shows: a role, its number (1 is the leftmost) or part of its name. `workspace` wins when both are set. |
| `focus = false` | Open without taking the focus. |
| `run` | A command or a list of commands to run after the other actions. |
| `stop = false` | Let later rules add to this one. By default the first match is the last. |
| `border` | The focus border color of the window: `"#f38ba8"`, or `{ "#f38ba8", "#fab387" }`. Needs `border.enabled`. |
| `dim` | `false` keeps the window bright (a video player); `true` dims it even when `dim.enabled` is off. |
| `dynamic = true` | Check the rule again when the title of the window changes. |
| `name` | A label for `wm logs` and `wm.floating.disable`. It matches nothing. |

`wm pick` prints a `wm.rule` for a window you click.

```lua
wm.rule { app = "com.apple.Notes", subrole = "AXDialog", float = true }
wm.rule { app = "org.mozilla.firefox", title = "^Picture-in-Picture$", float = true, dynamic = true }
```

- With `dynamic = true`, a window that starts to match gets `float`, `size`, `center`, `workspace`, `monitor`, `border` and `dim`; `run`, `layout`, `width`, `maximize` and `focus` apply only when it opens. A window that changes more than 4 times in a second is left alone for that second.
- `wm.exec(cmd, options)` and `wm exec` give the window that a command opens the same actions as a rule, once (`timeout` in seconds, 15 by default). See the [Lua API](/docs/lua-api) and [CLI](/docs/cli).

wm adds default rules after yours: browser popups and picture-in-picture, Finder, Preview, Calculator, Activity Monitor, Archive Utility, QuickTime Player, System Settings and the Raycast settings start floating and centered. `wm.floating.disable("finder", "preview")` tiles those again (names such as `finder`, `preview`, `calculator`, `system-settings`), `wm.floating.enabled = false` removes them all, and a rule of yours wins.

### Native workspaces

`wm.config { workspaces = "native" }` gives every workspace a macOS desktop (a Space) and keeps SIP on. `workspace 2` swipes to desktop 2, `window send workspace 3` moves the window to desktop 3, and a window that you drag to another desktop in Mission Control changes workspace. The method is the one of [Dinky](https://github.com/mikker/Dinky): a synthetic Dock swipe to switch, and the bridged window move of SkyLight to send. Both are private macOS interfaces and can change with a macOS update.

- **Numbering.** The desktops are numbered 1, 2, 3... across the displays, from the leftmost display, each in the order of Mission Control. Workspace `"N"` is desktop N. `wm.workspace("web", { space = 2 })` makes desktop 2 the workspace `web` (and `"2"` then names nothing).
- **wm makes the desktop when you ask for it.** `wm workspace 5` with three desktops makes desktops 4 and 5 and switches to 5. The new desktops go at the end of the last display, so no workspace changes desktop. This needs macOS 27 or later; before it, add desktops in Mission Control (Control-Up, then +) and `wm workspace 7` with six desktops fails and says so. A name that is not a number needs a desktop number: `wm.workspace("web", { space = 5 })`. wm never removes a desktop. The `workspaces` limit (`workspaces = 6`) stops it from making more than that.
- **Settings of macOS.** Turn off *Automatically rearrange Spaces based on most recent use* (System Settings > Desktop & Dock > Mission Control), or the numbers drift. Turn on *Displays have separate Spaces*. `wm doctor` checks both.
- **What changes.** `animations.workspaces.style` has no effect, as macOS draws the slide of the switch. `animations.enabled = false` or `animations.workspaces.enabled = false` asks the Dock for a switch with no slide instead: wm sends a swipe that jumps to the end at a very high velocity. It depends on the macOS version, so the slide may stay (or be shorter); `WM_SPACE_INSTANT_VELOCITY` (default 20000) changes the velocity, to try another value. The only sure way to have no slide is `workspaces = "emulated"`. `workspace move monitor` is not available, as a desktop stays on its display. `next` and `prev` walk the desktops of the focused display, and `empty` is the first desktop with no window.
- **What stays.** Special workspaces, zen and sticky windows work over the desktop that is shown. A desktop that is no workspace (a full-screen app) is shown as `space:<id>`.
- **Cursor.** The swipe goes to the display under the cursor. When the cursor is on another display, wm puts it on the target display for about 60 ms and back.
- **Going back.** Setting `workspaces = "emulated"` and reloading brings every window to the desktop that its monitor shows.

### Workspace rules

`wm.workspace(name, options)` needs at least one option.

| Option | Meaning |
|---|---|
| `layout` | `scrolling`, `tiling`, `master`, `monocle` or `floating`. |
| `monitor` | Bind the workspace to a monitor (a role, a number or part of its name). |
| `default` | With `monitor`: the monitor starts with this workspace. |
| `gaps`, `border`, `dim` | Settings for this workspace only. `border = false` turns the border off; `dim` turns dimming on or off. |
| `on_empty` | A command that runs when the workspace is shown with no window: `"ghostty"`, or `{ cmd = "open -a Notes", app = "Notes", float = true }`. |
| `space` | With `workspaces = "native"`: the number of the desktop that this workspace is (1 is the first desktop of the leftmost display). Ignored with emulated workspaces. |
| `persistent` | The workspace exists with no window: the menu bar lists it, and `workspace next` and `workspace prev` stop there. |
| `wallpaper` | A picture (an absolute path, or `~/...`) that the monitor shows while it shows this workspace. |
| `layout_options` | Layout options for this workspace only, for example `{ split_ratio = 0.6 }`. Master options start with `master_`: `master_ratio`, `master_count`, `master_orientation`, `master_new_window`. |

`wallpaper` changes the desktop of the current Space only and can flash.

## Appearance

`appearance` sets one look for every overlay wm draws: the command palette, cheatsheet, switcher, overview, template picker and key label. By default they look like macOS: system blur, light and dark mode that follows the system, and your accent and selection colors.

```lua
wm.config { appearance = {
  style = "native",         -- "native" (the default) or "hud"
  theme = "system",         -- "system" | "light" | "dark"
  density = "comfortable",  -- "compact" | "comfortable" | "spacious"
} }
```

![The native style in light mode](/appearance/appearance-native-light.png)

![The native style in dark mode](/appearance/appearance-native-dark.png)

![The hud style](/appearance/appearance-hud.png)

The pictures are illustrations drawn from the values of each look, not screenshots, so the real blur and fonts differ a little.

Every key is optional. A key that is absent comes from the preset of `style`.

| Key | What it does |
|---|---|
| `style` | `"native"`: system materials (`popover`), 12 point corners, system text and accent colors. `"hud"`: a dark blur, 20 point corners and a blue accent, in light mode too. |
| `density` | `"compact"`, `"comfortable"` or `"spacious"`. Sizes grow or shrink together (0.85, 1 and 1.2 times). |
| `theme` | `"system"` follows macOS. `"light"` or `"dark"` forces one. |
| `material` | The blur: `"popover"`, `"menu"`, `"hud"`, `"sidebar"`, `"sheet"`, `"window"` or `"none"` (flat color, no blur). The overview ignores it. |
| `accent` | The selected tile, the active tab, the chip of the mode. Default: the macOS accent color. |
| `background` | A color drawn over the blur. In the overview it is the dim layer, never more opaque than 85%. Default: none. |
| `foreground`, `secondary` | The text, and quieter text. Default: the macOS label colors. |
| `selection` | The highlight of the selected row of the palette. Default: the macOS selection color. |
| `border`, `border_width` | The line around the overlays (0 to 6 points). Default: the macOS separator color, 1 point. |
| `radius` | Corner radius in points, 0 to 48. The key label becomes a capsule when it is bigger than the label is tall. |
| `shadow` | The shadow of the windows. |
| `font`, `mono_font` | A font name such as `"SF Pro Rounded"`, and the font of hints and key caps. Default: the system fonts. |
| `font_size` | The body size in points, 8 to 40 (default 13). |
| `animation` | Seconds of the fades, 0 to 2. `0` turns them off. Default 0.12. The same as `animations.overlays.duration`, which wins when both are set, and `animations.enabled = false` turns the fades off as well. |

A reload applies the new look the next time an overlay opens.

### Themes to copy

Each one is the whole look. Paste one into your config, then change what you like. They all pass `wm config check`.

#### Catppuccin Mocha

Solid dark with one accent. Every overlay uses the same colors, corners and fonts.

![The Catppuccin Mocha theme](/appearance/appearance-catppuccin.png)

```lua
wm.config { appearance = {
  theme = "dark", material = "none", radius = 14,
  accent = "#cba6f7", background = "#1e1e2e", foreground = "#cdd6f4", secondary = "#a6adc8",
  selection = "#45475a", border = "#313244",
} }
```

#### Paper

Always light, flat and square, whatever macOS uses.

![The Paper theme](/appearance/appearance-paper.png)

```lua
wm.config { appearance = {
  theme = "light", material = "none", radius = 4,
  accent = "#d20f39", background = "#fafafa", foreground = "#222222", secondary = "#6c6f85",
  selection = "#e6e9ef", border = "#d0d4dc",
} }
```

#### Spotlight

The native blur and colors, rounder corners, a rounded font, no fades.

![The Spotlight theme](/appearance/appearance-spotlight.png)

```lua
wm.config { appearance = {
  radius = 16, font = "SF Pro Rounded", animation = 0,
} }
```

#### Tokyo Night

Deep navy with a soft blue accent.

![The Tokyo Night theme](/appearance/appearance-tokyonight.png)

```lua
wm.config { appearance = {
  theme = "dark", material = "none", radius = 14,
  accent = "#7aa2f7", background = "#1a1b26", foreground = "#c0caf5", secondary = "#7982a9",
  selection = "#283457", border = "#292e42",
} }
```

#### Rosé Pine

Dark plum with a dusty rose accent.

![The Rosé Pine theme](/appearance/appearance-rosepine.png)

```lua
wm.config { appearance = {
  theme = "dark", material = "none", radius = 14,
  accent = "#ebbcba", background = "#191724", foreground = "#e0def4", secondary = "#908caa",
  selection = "#403d52", border = "#26233a",
} }
```

#### Nord

Cool slate with an icy teal accent and tighter corners.

![The Nord theme](/appearance/appearance-nord.png)

```lua
wm.config { appearance = {
  theme = "dark", material = "none", radius = 10,
  accent = "#88c0d0", background = "#2e3440", foreground = "#eceff4", secondary = "#9aa5b8",
  selection = "#434c5e", border = "#3b4252",
} }
```

#### Gruvbox Dark

Warm charcoal with a golden accent.

![The Gruvbox Dark theme](/appearance/appearance-gruvbox.png)

```lua
wm.config { appearance = {
  theme = "dark", material = "none", radius = 8,
  accent = "#fabd2f", background = "#282828", foreground = "#ebdbb2", secondary = "#a89984",
  selection = "#504945", border = "#3c3836",
} }
```

## Display profiles

A display profile runs a function when the connected monitors are the ones you named, for example when you dock or undock.

```lua
wm.profile("desk", {
  monitors = { "dell", "main" },
  apply = function(monitors) wm.dispatch("layout set scrolling") end,
})
wm.profile("laptop", { monitors = { "main" }, apply = function() wm.dispatch("layout set tiling") end })
```

- The number of connected monitors is the number of selectors, and each names a different monitor. A selector is a role (`main`, `secondary`, `tertiary`), a number (1 is the leftmost) or part of the name, in any case.
- The first profile that fits wins, so put the most specific first.
- `apply` gets the list of `wm.query("monitors")`. `wm.rule`, `wm.workspace`, `wm.config` and `wm.profile` work only while the config loads, so use `wm.dispatch` and `wm.query` inside it.
- A profile runs when the displays change (wm waits half a second) and when the config loads, and not again while it is still the one that fits. `wm subscribe displays_changed` shows the event.

## Examples

A mode that ends after one key:

```lua
wm.mode("focus", { h = "focus left", l = "focus right", j = "focus down", k = "focus up" }, { once = true, swallow = true })
wm.bind("alt-f", "mode focus")   -- alt-f, then one of h j k l
```

A different layout per workspace, and rules for apps:

```lua
wm.workspace("1", { layout = "scrolling" })
wm.rule { app = "net.kovidgoyal.kitty", float = true, size = { 0.62, 0.68 }, center = true }
wm.rule { app = "com.apple.Notes", monitor = 2, width = 0.4, focus = false }
```

React to events:

```lua
wm.on("window_open", { app = "com.apple.finder" }, function(e)
  wm.dispatch("window float", { window = e.id })
end)
```
