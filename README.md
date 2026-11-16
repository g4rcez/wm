# wm

wm is a tiling window manager for macOS. It is written in Swift, runs with SIP on, and you configure it in Lua.

It has two layouts. **Scrolling** puts windows in columns on a strip that moves sideways, as niri and PaperWM do.
**Tiling** splits the screen in a tree, as Hyprland's dwindle layout does. You choose the layout per workspace and
change it while wm runs.

What you get:

- Emulated workspaces (like AeroSpace) or the native macOS desktops. The config picks one.
- Several monitors, gaps, animated moves and resizes, a focus border, and window rules.
- Binding modes with a which-key panel that lists the keys you can press.
- One command set with three entry points: the `wm` CLI, Lua (`wm.dispatch`) and `wm://` URLs.
- Layouts that survive a restart of the daemon.

wm has no default key bindings. Until you bind keys in `init.lua`, it only reacts to the `wm` command.

## Install

### Requirements

- macOS 14 or later.
- The Swift 6.2 toolchain (Xcode or the command line tools).
- Quit any other window manager first (AeroSpace, yabai, Amethyst). Two of them fight over the same windows.

I have not published a binary. You build wm from source.

### Build

```sh
git clone <repository-url> wm        # [confirm: repository URL]
cd wm
./build-app.sh                       # builds .build/wm.app (daemon and CLI), signs it, and starts it
```

`./build-app.sh debug` makes a debug build. `NO_START=1 ./build-app.sh` builds without starting the daemon. If wm is
already running, the script stops it before it replaces the bundle.

### Permissions

macOS asks for **Accessibility** the first time wm starts. Grant it in System Settings > Privacy & Security >
Accessibility. wm cannot move windows without it.

**Screen Recording** is optional. wm uses it for the window pictures in the Alt+Tab switcher and in the overview. Without
it those tiles show the app icon and the title.

The menu bar icon needs one more switch: System Settings > Menu Bar > "Allow in the Menu Bar" > `wm`.

### Signing

macOS keeps the Accessibility and Screen Recording grants of an app by its signature. An ad-hoc signature changes with
every build, so you would grant the permissions again after each rebuild. `build-app.sh` avoids that:

1. It signs with `CODESIGN_IDENTITY` (a certificate name or SHA-1 hash) when you set it.
2. Otherwise it uses the first "Apple Development" certificate in your keychain.
3. Otherwise it signs ad hoc and prints a warning.

Nothing about the certificate is written into the repository. The first build with a certificate makes macOS ask whether
`codesign` may use the key: choose **Always Allow**. Switching from ad hoc to a certificate changes the signature once, so
grant the permissions one more time. After that, rebuilds keep them. `codesign -dr - .build/wm.app` shows
`identifier "local.wm" and ... certificate leaf ...` and no `cdhash` when the signature is stable.

### Put `wm` on your PATH

The CLI lives inside the bundle. Link it somewhere on your PATH:

```sh
mkdir -p ~/.local/bin
ln -s "$PWD/.build/wm.app/Contents/MacOS/wm" ~/.local/bin/wm
```

`wm daemon start` finds the app that its own `wm` belongs to, also through this symlink. If it cannot, it tries
`/Applications/wm.app` and then `~/Applications/wm.app`.

### Editor autocomplete

Run `wm lsp --write` once to get completion for `init.lua` in your editor. See [Editor support](#editor-support).

### Shell completion

`wm completion zsh` and `wm completion bash` print a small script that asks `wm` for the candidates each time you press
Tab, so it never goes out of date. It completes the commands, their arguments and their options. While the daemon runs
it also completes window ids (with the app and title), `--window` selectors (`app:<name>`), workspace names, special
workspaces and modes. Without the daemon the fixed words still complete. Load it when the shell starts:

```sh
eval "$(wm completion zsh)"   # in ~/.zshrc, after compinit
eval "$(wm completion bash)"  # in ~/.bashrc
```

### Start at login

Copy `wm.app` to `/Applications` and set `start_at_login = true` in the config. The app has to stay in a fixed place for
this to work.

### Run it

```sh
wm daemon start    # starts wm.app in the background and returns when the daemon answers
wm daemon status   # whether it runs, the workspace, the mode, the window count
wm daemon stop     # quits wm; hidden windows come back on screen
wmd --background   # from a terminal: a detached daemon that survives closing the terminal
```

While the daemon runs, a rounded square with the workspace name is in the menu bar. Its menu has reload, the tile
pictures, and quit.

## First five minutes

Create `~/.config/wm/init.lua`. This is a small config to start from:

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

Save the file. wm reloads it on its own, and `wm daemon reload` does the same by hand. If the new file has an error, the
old config stays active and the error shows in the menu bar and in the output of `wm daemon reload`.

The config path is `~/.config/wm/init.lua`, or `$XDG_CONFIG_HOME/wm/init.lua`, or the file named by `$WM_CONFIG`.

Open a few windows and try the keys. Then run `wm help` to see every command.

## How wm thinks

**Layouts.** Each workspace has one layout. `scrolling` is a strip of columns. A new window opens beside the focused one
and never resizes the others. A column can hold a stack of windows or show them as tabs. A scrolling workspace can also
have a second, vertical strip at one side. `tiling` is a binary tree. A new window splits the focused one, and wm
picks side by side or stacked from the shape of the cell.

**Workspaces.** In the default `emulated` mode, wm hides the windows of other workspaces by parking them at a screen
corner. You can have as many workspaces as you want, with any name. In `native` mode, each macOS desktop is a
workspace. `window send workspace` does not work there, because macOS (with SIP on) lets no app move a window between
desktops.

**Monitors.** A workspace is shown on one monitor at a time. Showing a workspace that another monitor has swaps the two.

**Special workspaces.** A special workspace is a scratchpad. One key shows it on the focused monitor and the same key
hides it. It works like Hyprland's.

**Modes.** A mode is a separate set of key binds, for example a resize mode where `h` and `l` change the width. You enter
a mode with `mode <name>` and leave it with `mode main`.

**Rules.** A rule matches new windows by app or title and decides where they go and how they look.

## Examples

### A resize mode with a key panel

```lua
wm.mode("resize", {
  h = { "resize width +50", description = "Wider" },
  l = { "resize width -50", description = "Narrower" },
  j = { "resize height +50", description = "Taller" },
  k = { "resize height -50", description = "Shorter" },
  esc = { "mode main", description = "Exit" },
})
wm.bind("alt-shift-r", "mode resize")
```

While the mode is active, a panel lists its keys with the text from `description`. See [The key panel](#the-key-panel).

### One prefix key, then a letter

```lua
local PREFIX = "alt-space>"
wm.bind(PREFIX .. "h", "focus left")
wm.bind(PREFIX .. "l", "focus right")
wm.bind(PREFIX .. "f", "window fullscreen")
wm.bind(PREFIX .. "tab", "switcher")
```

After `alt-space`, wm waits 1.5 seconds for the next key and shows the keys that can follow.

### A different layout per workspace and per monitor

```lua
wm.workspace("1", { layout = "scrolling" })
wm.workspace("2", { layout = "tiling" })
wm.workspace("web", { monitor = 2, default = true, gaps = { inner = 0, outer = 0 }, border = false })
wm.workspace("code", { layout = "scrolling", monitor = "LG", layout_options = { default_width = 0.7 } })
```

### Window rules

```lua
wm.rule { app = "com.apple.systempreferences", float = true }
wm.rule { app = "net.kovidgoyal.kitty", float = true, size = { 0.62, 0.68 }, center = true }
wm.rule { title = "^Picture in Picture$", float = true }
wm.rule { app = "com.spotify.client", workspace = "9" }
wm.rule { app = "com.apple.Notes", monitor = 2, width = 0.4, focus = false }
```

### Scripts from the shell

```sh
wm list windows                                   # a table of every window
wm list windows --focused --json                  # JSON for scripts
wm --window app:com.apple.Notes window close      # act on a window by app, title or pid
wm batch 'workspace 2; layout set tiling'         # several commands, stops at the first error
wm set gaps.inner 4                               # change a config value until the next reload
wm notify 'build done' --seconds=3                # a message on screen
```

### React to events

```lua
wm.on("workspace_changed", function(e) wm.log("now on workspace " .. e.workspace) end)
wm.on("window_open", { app = "com.apple.finder" }, function(e)
  wm.dispatch("window float", { window = e.id })
end)
```

### Swipe gestures

```lua
wm.gesture { mods = "alt", direction = "left",  command = "workspace prev", description = "Previous workspace" }
wm.gesture { mods = "alt", direction = "right", command = "workspace next" }
```

## Config reference

All keys are optional. Two `wm.config` calls merge. An unknown key is an error.

```lua
wm.config {
  layout = "tiling",                   -- scrolling | tiling
  workspaces = "emulated",             -- emulated | native
  gaps = { inner = 8, outer = 8 },     -- outer can also be { top=, right=, bottom=, left= }
  animations = { enabled = true, rate = 14 },  -- rate: spring stiffness; a long move ends in about 10 / rate seconds
  border = { enabled = true, width = 2, radius = 10, active = "#89b4fa", inactive = "#00000000" },
  focus_follows_mouse = false,
  mouse_follows_focus = false,
  start_at_login = true,               -- only when running as wm.app
  wrap_focus = false,
  tiling    = { split_ratio = 0.5, preserve_split = true,
                force_split = "second",           -- where a new window goes in its split: "second" (right, bottom) or "first"
                split_width_multiplier = 1 },     -- 2 or more keeps columns on an ultrawide screen before the first stacked split
  binds     = { long_press_timeout = 0.4 },       -- seconds a key is held for a `long_press` bind
  scrolling = { presets = { 0.33, 0.5, 0.66, 1.0 }, default_width = 0.5, center = "on-overflow",
                always_center_single_column = false,      -- a lone column sits in the middle (even with center = "never")
                default_column_display = "normal",        -- "tabbed": every new column is a tab stack
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

### Chords and sequences

A chord is modifiers and a key joined by `-` or `+`: `alt-h`, `cmd+ctrl-2`. The modifiers are `alt` (or `opt`), `cmd`,
`ctrl` and `shift`. The key is a letter, a digit, or one of `esc`, `space`, `tab`, `enter`, `backspace`,
`left`, `right`, `up`, `down`, `minus`, `equal`, `comma`, `period`, `slash`, `backslash`, `semicolon`, `quote`,
`backtick`, `leftsquarebracket`, `rightsquarebracket`, `f1` to `f20`, `home`, `end`, `pageup` and `pagedown`.

A bind can also be a sequence of chords separated by `>`: `"ctrl-p>h"`, `"alt-space > t > n"`. wm takes the first chord of
a sequence from every app, so choose one your apps do not need. A key that continues no sequence cancels it and is
swallowed, as in tmux, so a typo never reaches the app you are typing in. A sequence waits until the next key or Escape:
it has no timeout. (`prefix.timeout` of old configs is still accepted and ignored.)

In one mode, a chord cannot be a bind by itself and also the start of a sequence, and a sequence cannot be the start of a
longer one (`a>b` and `a>b>c`). Both are config errors. `wm.bind("cmd-h", "")` with an empty string swallows a key.

### The key panel

While a mode other than `main` is active, or while a prefix waits for its next key, a panel shows what you can press.
It has a chip with the mode name and one chip per key, with the key's `description` or else its command:

```
( resize )  ( H ) Wider   ( J ) Taller   ( K ) Shorter   ( L ) Narrower   ( esc ) Exit
```

- The order is fixed: letters and digits, then chords with modifiers, then other keys, then `esc`.
- A bind with `hidden = true` is left out, and so is a bind that only swallows a key. Universal binds show in every mode.
- After a prefix chord, the first chip is the prefix and the keys are the ones that can follow. A key that starts a longer
  sequence shows `…`.
- The layout follows the position. In the middle (`top-center`, `center`, `bottom-center`) the keys form a grid in a row,
  with the mode chip on the left. At a side (`top-left`, `top-right`, `bottom-left`, `bottom-right`, and the older `left` and
  `right`) the panel is a list with one key per line. A long list gets more columns instead of growing taller than 70% of
  the screen.
- `show_keys = false` leaves only the mode chip. `wm notify` uses the same pill, with text only, even when
  `enabled = false`.

### Bind options

`wm.bind(chord, action, options)` takes a table as its third argument. Inside `wm.mode`, an action can be a table too:
`h = { "resize width +50", description = "Wider" }`.

| Option | What it does |
|---|---|
| `description` | Text for `wm list binds` and the key panel. |
| `repeating = false` | Run once per press. Without it, a held key repeats the action. |
| `release = true` | Run when the key comes up. A chord can have a press bind and a release bind. |
| `long_press = true` | Run when the key is held for `binds.long_press_timeout` seconds. A short press runs the normal bind of the same chord. |
| `universal = true` | The bind works in every mode. |
| `hidden = true` | Leave the key out of the key panel. |

`release` and `long_press` need a single chord and cannot be combined. The mode name `*` is reserved for universal binds.
`wm list binds` (and `--json`) shows every bind with its mode, keys, trigger and command.

### Gestures

`wm.gesture { mods, direction, command }` runs a command when you swipe with two fingers while you hold modifiers.
`mods` is one or more of `alt`, `shift`, `ctrl` and `cmd` (`"alt+shift"`). `direction` is `left`, `right`, `up` or
`down`. With natural scrolling, which is the macOS default, it is the direction of your fingers. The command can be a
string or a Lua function. It runs once per swipe, when the scroll has gone `threshold` points (10 to 2000, default 100).

macOS does not say how many fingers scroll, so a gesture is a modifier and a direction. A swipe on an axis that no gesture
uses goes on to the built-in Option + scroll, which moves the scrolling strip.

### Window rules

| Field | Meaning |
|---|---|
| `app` | Bundle id or app name. Exact match, case does not matter. |
| `title` | A regular expression, matched anywhere in the title. |
| `float` | Open the window floating. |
| `workspace`, `layout` | Where it opens, and the layout of that workspace if it is empty. |
| `size`, `center` | For floating windows: `{ width, height }` as fractions of the screen (or points above 1), and centering. |
| `maximize` | Open maximized. |
| `width` | Column width in the scrolling layout, as a fraction of the screen. |
| `monitor` | Open on the workspace that this monitor shows: its number (1 is the leftmost) or part of its name. `workspace` wins when both are set. |
| `focus = false` | Open without taking the focus. The window that had it gets it back. |
| `run` | A command or a list of commands to run after the other actions. |
| `stop = false` | Let later rules add to this one. By default the first match is the last. |

A rule needs `app` or `title`. Rules apply in order, and later values win.

### Workspace rules

`wm.workspace(name, options)` needs at least one option.

| Option | Meaning |
|---|---|
| `layout` | `scrolling` or `tiling`. |
| `monitor` | Bind the workspace to a monitor (a number or part of its name). Showing it shows it there. |
| `default` | With `monitor`: the monitor starts with this workspace. |
| `gaps`, `border` | Settings for this workspace only. |
| `layout_options` | Tiling and scrolling options for this workspace only, for example `{ split_ratio = 0.6 }`. |

## Layouts in detail

### Tiling

- `layout preselect <left|right|up|down>`: the next window that opens splits the focused one on that side, once.
- `layout split ratio 0.7` gives the focused window 70% of its split. A number from 0.1 to 0.9, or a change like `+0.1`.
- `layout split root` makes the focused window a child of the root split. It gets half the screen.
- `layout split toggle` flips the split of the window. `layout split swap` swaps its two sides.
- `layout flip` turns every split from side by side to stacked, and back.
- `window pseudo` keeps the window at the size it has now, centered in its tile. Run it again to tile it normally.
- `tiling.force_split = "first"` puts new windows on the left or top. `tiling.split_width_multiplier = 2` keeps columns
  on an ultrawide screen before the first stacked split.

### Scrolling

- `layout column width <fraction|cycle>`, `layout column match` and `layout balance` set column widths.
  `balance` fits all columns on screen.
- `layout stack join` puts the window in the column on its left. `layout stack leave` takes it out.
  `layout stack tabs` shows the column as tabs. `layout stack equalize` evens out the heights.
  `layout stack height <fraction|cycle>` gives the window a share of the column.
- A tab indicator, a thin bar with one segment per tab, shows which window of a tabbed column is on top. It is a separate
  window drawn over a few points of the column, like the focus border. `tab_indicator.enabled = false` turns it off.
- `layout column center` and `layout column center-visible` scroll the strip.
- `window maximize` grows the column to the whole zone. Run it again to restore it.
- A second, vertical strip sits at one side of the screen. `window send strip vertical` and `window send strip horizontal`
  move a window between the two, and `focus` crosses from one to the other at the edge.
- Hold Option and swipe with two fingers to move the strip. It settles on the nearest column.

### Tile templates

`layout tile <pattern>` makes the focused window and the windows after it fill one screen in a fixed pattern.
`layout tile chain` goes back to single columns. `layout tile` with no pattern opens a picker.

| Pattern | Windows | Picture |
|---|---|---|
| `2` | 2 | side by side |
| `3` | 3 | three in a row |
| `2+1` | 3 | two stacked on the left, one tall on the right |
| `1+2` | 3 | one tall on the left, two stacked on the right |
| `4` | 4 | two across, two down |
| `5` | 5 | three on top, two below that stretch to the full width |
| `6` | 6 | two rows of three |
| `2/3` | 2 | the first window takes two thirds of the width, the second one third |
| `3/4` | 2 | the first window takes three quarters on the left, the second one quarter |
| `1/4` | 2 | the mirror of `3/4`: one quarter on the left, three quarters on the right |
| `chain` | - | back to single columns |

In the scrolling layout the group is the focused window and the windows after it (or before it, when too few come after).
It is one block in the strip, so scrolling moves it as one screen. In the tiling layout the pattern applies to all tiled
windows of the workspace, and their number has to match. The picker has a one-character key on each picture: a number for
the grids, `l` and `r` for `2+1` and `1+2`, `t`, `q` and `w` for `2/3`, `3/4` and `1/4`, and `c` for the chain.

#### Your own templates

`templates` in `tiling` and in `scrolling` replaces the list that the picker and the menu bar show for that layout. Each
layout has its own list. Without `templates`, the layout lists the ten built-in ones. `wm.templates` has every built-in
template, so a list can mix them with your own:

```lua
wm.config {
  tiling = { templates = { wm.templates.two, wm.templates.four, wm.templates.stack_left } },
  scrolling = {
    templates = {
      wm.templates.two_thirds,
      { name = "70/30", key = "s", title = "Focus 70%", cells = { { 0, 0, 0.7, 1 }, { 0.7, 0, 0.3, 1 } } },
    },
  },
}
```

`wm.templates` has `two`, `three`, `four`, `five`, `six`, `stack_left`, `stack_right`, `two_thirds`, `three_quarters` and
`one_quarter`.

- `name` is what `layout tile <name>` takes. It has no spaces, it is not `chain`, and it is unique in the list.
- `key` is optional: one of `a-z` or `0-9`, not `c`, unique in the list. It picks the template in the picker.
- `title` is optional: the text in the menu bar menu (the default is the name).
- `cells` is a list of `{ x, y, width, height }` as fractions of the screen, in reading order. The windows take the cells in
  that order. There are two or more cells. They fill the screen with straight cuts and do not overlap.
- The chain stays last in the picker and the menu.
- `layout tile <name>` also takes a built-in name that your list leaves out, so old binds keep working.
- The shell completion for `wm layout tile` lists only the built-in names.

### Rotate

`layout rotate cw` and `layout rotate ccw` move every window one slot around the layout. The slots keep their sizes. This
works in every layout.

### Maximize and moving windows between workspaces

In the scrolling layout, `window maximize` keeps the window in its place in the strip. In the other layouts, it makes
the window fill the work area inside the outer gaps while the others stay tiled behind it. `window fullscreen` fills the
work area with no gaps and no border.

A window that you send to another workspace arrives maximized when that workspace has no other tiled window. When the
workspace has windows, the window joins the layout and `balance` runs. Add `--tile` to join the layout without either.

## Switcher and overview

```lua
wm.bind("alt-tab", "switcher")
wm.bind("alt-o", "overview")
```

Hold Alt and press Tab to open a miniature of the focused workspace with a picture of each window. Tab and Shift+Tab move
the selection, the arrow keys move it across the miniature, and letting go of Alt focuses the window. Return focuses
too, and Escape cancels. `switcher = { thumbnails = false }` turns the pictures off.

`overview` shows every workspace that holds windows, one row each. Every window has a key label in its corner: type it to
focus that window (with more than 22 windows the labels have two letters). `h` `j` `k` `l` or the arrow keys move the
selection instead, and Return or a click focuses the window. You can **drag a window onto another row to move it there**.
The last row, an empty screen named `+ new workspace N`, creates a workspace from the first unused number. The focus and
the shown workspace stay as they are.

## Mouse

- Drag an edge or corner of a tiled window. When you let go, wm moves the dividers you moved, and the neighbours follow.
- Drag a tiled window by its title bar and drop it on another tile of the same workspace. The two windows swap places. A
  drop anywhere else sends the window back to its tile.
- `wm swap <dir>` does the swap from the keyboard.

## Command line

`wm help` lists every command and `wm help <command>` has details and examples. The same words work in `wm.bind`, in
Lua (`wm.dispatch`) and in `wm://` URLs.

```
FOCUS AND MOVE   focus <dir> | focus back | focus window <id> | focus monitor <dir|next|prev> | focus layer
                 move <dir> | swap <dir> | resize <width|height|smart> <+n|-n>
WINDOWS          window close | float | fullscreen | maximize | pseudo
                 window send workspace <name> | monitor <x> | row <x> | strip <horizontal|vertical>
WORKSPACES       workspace <name|back|next|prev|empty> | workspace special [name] | workspace row <up|down|N>
LAYOUT           layout set <scrolling|tiling> | balance | rotate | flip | tile | preselect <dir>
                 layout split <toggle|swap|root|ratio> | column <width|match|center|center-visible>
                 layout stack <join|leave|tabs|equalize|height>
INTERFACE        switcher | overview | mode <name> | pointer <window|monitor>
                 exec [options] <command> | batch <commands> | set <key> <value> | notify <text> | key send <chord>
INSPECT          list [windows|workspaces|monitors|binds] | subscribe
DAEMON           daemon start | stop | status | reload | version
EDITOR           lsp [--write] [--force]
SHELL            completion <zsh|bash>
```

Options for every command: `--window <w>` acts on that window, `--json` prints JSON (`list`, `daemon status`),
`-v` or `--verbose` prints the state after the command, and `-h` or `--help` shows help.

### Output

A command that works prints nothing. Errors go to stderr with a non-zero exit code, in up to three lines: what went wrong,
the `usage:` line, and a `hint:`. Exit code 2 means the command was used wrongly, and 1 means it could not run. Colors
appear only on a terminal, and never when `NO_COLOR` is set.

```
$ wm layout stak
wm: error: unknown layout command 'stak'
usage: wm layout set <scrolling|tiling>
       wm layout balance
       ...

$ wm list windows
   ID    APP         TITLE                     WORKSPACE  STATE
*  204   Terminal    1: zsh                    2          maximized
   7653  Notes                                 2          floating
```

`wm daemon status` exits with 1 when wm does not run, so a script can test it. `wm subscribe` prints one JSON event per
line until you stop it.

### Choosing a window

`--window` takes a window id or a selector:

| Selector | The window |
|---|---|
| `focused` | the focused one |
| `app:<name>` | of that app: bundle id or app name, exact, case does not matter |
| `title:<regex>` | whose title matches the regular expression |
| `pid:<n>` | of that process |

With several matches, the focused window wins if it is one. Then the most recently used one on the focused workspace
wins, then the lowest id. No match is an error. The flag goes before or after the command. In Lua, use
`wm.dispatch("window close", { window = "app:Notes" })`. In a URL, use `?window=app:Notes`.

### Scripting

- `wm batch 'workspace 2; layout set tiling'` runs commands in order and stops at the first error.
- `wm set gaps.inner 4` changes one config value until the next reload. Lists are comma-separated:
  `wm set scrolling.presets 0.3,0.5,1`. `workspaces` and `url` only change in the config file.
- `wm key send cmd-shift-r --window app:OBS` types a key into an app that is in the background. Bind a chord of yours to
  it and you have a global hotkey for that app.
- `wm exec --float --center --size 0.5,0.5 -- /path/to/program` makes a rule for the window that the program opens. The
  options are `--float`, `--tile`, `--center`, `--maximize`, `--no-focus`, `--workspace`, `--monitor`, `--width`, `--size`
  and `--layout`. wm finds the window by process, so give the program itself and not `open -a`. The options apply to
  the first window that opens within 15 seconds.
- `wm workspace next|prev|empty` moves through the workspaces in use (wrapping around) or to the lowest free number.

## Lua API

`wm.config`, `wm.bind`, `wm.mode`, `wm.gesture`, `wm.rule`, `wm.workspace`, `wm.on`, `wm.dispatch`, `wm.query`,
`wm.exec`, `wm.log` and `wm.version`.

- `wm.dispatch(command [, { window = id or selector }])` runs a command. It returns stdout, or `nil, stderr` when the
  command failed.
- `wm.query(kind)` returns a Lua table. The kinds are `windows`, `focused`, `workspaces` and `monitors`.
- Events: `window_open`, `window_close`, `window_focus`, `workspace_changed`, `special_changed`, `monitor_changed`,
  `layout_changed`, `mode_changed` and `config_reloaded`. `wm.on(event, [filter,] handler)` takes an optional table of
  fields that must match.

### Editor support

`init.lua` gets completion, hover help and warnings in any editor that runs
[lua-language-server](https://luals.github.io/) (LuaLS): VS Code with the Lua extension, Neovim with `lua_ls`, Helix, Zed
and others. The server reads the type stubs in `types/wm.lua`. They describe the whole API: config keys with defaults and
ranges, enum values, command strings, bind options, rule fields, event fields and the tables that `wm.query` returns.
wm never loads this file. It exists for the editor.

`build-app.sh` puts the stubs inside the app, so you do not need this repository to use them. One command sets
everything up:

```sh
wm lsp            # shows the folder of the stubs and the .luarc.json that LuaLS needs
wm lsp --write    # saves it next to your config, as ~/.config/wm/.luarc.json
```

`--write` stops if a `.luarc.json` is already there. Use `--force` to replace it, or add the printed folder to the
`workspace.library` list of your file by hand. This is what the file looks like:

```json
{
  "diagnostics.neededFileStatus": { "missing-fields": "Any", "undefined-field": "Any" },
  "runtime.version": "Lua 5.4",
  "workspace.library": ["/Applications/wm.app/Contents/Resources/types"]
}
```

Open `init.lua` and the editor does the rest. LuaLS finds the file because it sits in the folder of `init.lua`. If you
move `wm.app`, run `wm lsp --write --force` again, because the path of the stubs changes. If you work on wm itself, you
can point `workspace.library` at the `types` folder of the repository instead.

Some examples of what you get: completion for `wm.config { ... }` keys and values (`layout = "` offers `scrolling` and
`tiling`), the command strings of `wm.bind`, the fields of `wm.rule`, the event names of `wm.on` with the fields of each
event, and a warning for a wrong value (`layout = "grid"`) or a wrong event name. LuaLS does not warn about an unknown key
inside a table (`gaps = { outr = 1 }`). wm still rejects it when the config loads.

A test keeps the stubs in step with the API: it fails when a `wm` function or a top-level config key has no stub.

## URL scheme

`wm://<command>/<arg>...` or `wm://<command>?args=<url-encoded arguments>`:

```sh
open "wm://workspace/2"
open "wm://focus?args=left"
open "wm://window/send/workspace/3?args=--stay"
```

Any app or web page can open a `wm://` URL. For that reason `exec`, `daemon` and `subscribe` are blocked for URLs. Allow one
on purpose with `url = { allow = { "exec" } }`.

## Special workspaces

```lua
wm.bind("alt-s", "workspace special term")                     -- show or hide special:term on the focused monitor
wm.bind("alt-shift-s", "window send workspace special:term")   -- send the window there and show it
wm.workspace("special:term", { layout = "scrolling" })
wm.rule { app = "com.spotify.client", workspace = "special:music" }
```

A special workspace takes the work area with 5% free on each side. It hides when you run the command again, when you
switch to a workspace, when its last window goes away, and when a window of the normal workspace gets the focus.
While it is shown, the windows of the normal workspace are parked. macOS brings every window of the active app forward,
so wm cannot keep the special windows above them. Special workspaces need `workspaces = "emulated"`.

## Native desktops

With `workspaces = "native"`, each macOS desktop (per display) is a workspace with its own layout. `workspace N` presses
Control-N, so enable "Switch to Desktop N" in System Settings > Keyboard > Keyboard Shortcuts > Mission Control. Switching
desktops by other means (Mission Control, the trackpad) works without it, and wm follows.

A desktop can also hold virtual rows: extra workspaces inside one desktop. `workspace row <up|down|N>` shows a row and
`window send row <up|down|N>` sends the focused window to one. The other rows are parked like a hidden emulated workspace.

## Saved state

wm saves its layouts to `$XDG_STATE_HOME/wm/state.json`, or `~/.local/state/wm/state.json`, half a second after a change
and when it quits. After a restart of the daemon (a rebuild, a crash, `wm daemon stop` and `start`), the windows that are
still open go back to their workspace, layout, column sizes, stacks, tile blocks, split tree, scroll position, floating
frame and monitor. wm matches windows by window id and bundle id, so an app that you closed or relaunched meanwhile
counts as new. A restored window runs no rules and fires no `window_open`.

A layout that you change in the config while wm is stopped wins over the saved one. A state saved in the other
`workspaces` mode is ignored. Delete the file to start fresh.

## Troubleshooting

- **Nothing happens when I press a key.** Check that wm has Accessibility permission and that `wm daemon status` says it
  runs. Without a config, wm has no key binds.
- **I rebuilt and macOS asks for permissions again.** The build was signed ad hoc. See [Signing](#signing).
- **The menu bar icon is missing.** Switch on `wm` in System Settings > Menu Bar. `wm daemon status` says
  `menu bar: hidden by macOS` when the icon is not on screen.
- **The switcher shows icons and not pictures.** Grant Screen Recording, or set `switcher = { thumbnails = false }`.
- **A window hides behind others, or stays out of the layout.** Some windows (dialogs, palettes) float by design. Use
  `wm window float` to toggle one, or add a rule.
- **My config has an error.** The old config stays active. The message is in the menu bar and in the output of
  `wm daemon reload`.
- **wm and another window manager fight.** Quit the other one. Quitting wm puts every hidden window back on screen.

## Limits

- Animations move real windows through the Accessibility API, one call per frame. Slow apps (Electron) can stutter, and a
  window with an AX call still running skips frames.
- wm cannot blur, fade or shadow other apps' windows, and with SIP on it cannot move windows between native desktops.
- The border and the tab indicator are separate overlay windows above normal windows.
- A window with a minimum size larger than its tile overlaps its neighbours.
- Gestures see only a modifier and a scroll direction, not the finger count.
- When a display is unplugged, its windows move to the workspace of a remaining monitor.

## Development

```sh
timeout 300 swift test      # unit tests: layout engines, geometry, Lua host, IPC, command parsing
./build-app.sh debug        # a debug build of the app bundle
```

| Target | Role |
|---|---|
| `CLua` | Vendored Lua 5.4.7 |
| `Common` | IPC (length-prefixed JSON over a unix socket), command table, help, URL parsing and shell completion |
| `Core` | Pure layout engines, animator, gaps, navigation, overview key labels. No AppKit. |
| `Scripting` | Lua host, chords, binds, gestures, config validation |
| `Platform` | Accessibility threads, displays, event tap, overlays, SkyLight reader |
| `App` | `wmd`: window manager state, commands, config, menu bar, URL handler |
| `Cli` | `wm` |

The engines are plain values with no AppKit in them, so most behavior has a test with literal frames. The parts that need a
real screen (overlays, the event tap, window moves) I checked by running the daemon.

## Credits

wm borrows ideas from projects it does not copy code from:

- [Hyprland](https://hypr.land/): the dwindle layout, special workspaces and submaps (modes).
- [which-key.nvim](https://github.com/folke/which-key.nvim) for Neovim: the idea of a panel that lists the next keys.
- [niri](https://github.com/niri-wm/niri) and PaperWM: the scrolling strip of columns.
- [AeroSpace](https://github.com/nikitabobko/AeroSpace): emulated workspaces on macOS without disabling SIP.
- [Ribbon](https://meetribbon.app/): the pictures of the tile templates. The patterns are an original implementation and
  use none of its code.

The scrolling semantics are ported from [paneru](https://github.com/karinushka/paneru) (MIT). Lua is vendored under the
MIT license. `legal/THIRD_PARTY.md` has the full notices.

## License

wm is released under the MIT License. See [LICENSE](LICENSE). The notices of the code that wm includes are in
[legal/THIRD_PARTY.md](legal/THIRD_PARTY.md).
