<p align="center">
  <img src="assets/icon-windows.svg" width="128" height="128" alt="The wm icon: a window with nine blocks, three of them lit on a diagonal">
</p>

# wm

wm is a tiling window manager for macOS. It is written in Swift, runs with SIP on, and you configure it in Lua.

It has two layouts. **Scrolling** puts windows in columns on a strip that moves sideways, as niri and PaperWM do.
**Tiling** splits the screen in a tree, as Hyprland's dwindle layout does. You choose the layout per workspace and
change it while wm runs.

What you get:

- Emulated workspaces (like AeroSpace): wm hides the windows of other workspaces, so it needs no macOS desktops.
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

A `Makefile` wraps the common tasks. `make` lists them:

```sh
make deps                                  # checks the Swift toolchain; installs librsvg and imagemagick (only for the icon) if missing
make build                                 # compiles only: it does not touch the app that runs (CONFIG=debug for a debug build)
make test                                  # runs the unit tests, with a 300 second timeout when timeout or gtimeout exists
make identities                            # lists your code-signing certificates
make install CODESIGN_IDENTITY="<name>"    # build, sign, copy to /Applications/wm.app, link wm in ~/.local/bin, start it
```

`make install` stops when there is no certificate (it uses `CODESIGN_IDENTITY`, else the first "Apple Development" one), so
it never installs an ad hoc build that loses the permissions at every rebuild. `APP_DIR` and `BIN_DIR` change where it
installs. It stops the running wm, replaces `wm.app` and starts the new one.

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

Save the file. wm reloads it on its own, and `wm daemon reload` does the same by hand. Each reload shows a notification of
macOS: `Config reloaded: init.lua`, or `wm: config error` with the message. The first one asks you to allow notifications for
wm; if you say no, wm still reloads and the answer is in the menu bar and in `wm logs`. A new notification replaces the last
one, so saving often does not fill Notification Center. The load when wm starts shows none. If the new file has an error, the
old config stays active and the error shows in the notification, in the menu bar and in the output of `wm daemon reload`.

The config path is `~/.config/wm/init.lua`, or `$XDG_CONFIG_HOME/wm/init.lua`, or the file named by `$WM_CONFIG`.

Open a few windows and try the keys. Then run `wm help` to see every command.

## How wm thinks

**Layouts.** Each workspace has one layout. `scrolling` is a strip of columns. A new window opens beside the focused one
and never resizes the others. A column can hold a stack of windows or show them as tabs. A scrolling workspace can also
have a second, vertical strip at one side. `tiling` is a binary tree. A new window splits the focused one, and wm
picks side by side or stacked from the shape of the cell.

**Workspaces.** wm hides the windows of other workspaces by parking them at a screen corner. You can have as many
workspaces as you want, with any name.

**Monitors.** A workspace is shown on one monitor at a time. Showing a workspace that another monitor has swaps the two.
Where a command or a rule takes a monitor, you can name it by role: `main` is the display with the menu bar, and
`secondary` and `tertiary` are the other displays from left to right. A number (1 is the leftmost) and a part of the name
work too. `focus monitor last` goes back to the monitor that had the focus before.
`workspace move monitor <monitor>` sends the workspace you are on to that monitor: the monitor shows it from now on, and
your monitor shows the lowest free workspace number. A workspace that a `wm.workspace` rule binds to a monitor stays
there, and the command refuses to move it. Floating windows keep their relative place on the new monitor. `move` is
therefore not usable as a workspace name.

**Special workspaces.** A special workspace is a scratchpad. One key shows it on the focused monitor and the same key
hides it. It works like Hyprland's.

**Modes.** A mode is a separate set of key binds, for example a resize mode where `h` and `l` change the width. You enter
a mode with `mode <name>` and leave it with `mode main`.

**Rules.** A rule matches new windows by app or title and decides where they go and how they look.

## Examples

A complete configuration in use, with binds, a prefix key, binding modes, window rules and layouts, is in the author's dotfiles:
[`config/wm/init.lua`](https://github.com/g4rcez/dotfiles/blob/master/config/wm/init.lua). It is a good place to see how the pieces below fit together.

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

After `alt-space`, wm waits for the next key (or Escape) and shows the keys that can follow.

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

For a whole file, see the [author's configuration](https://github.com/g4rcez/dotfiles/blob/master/config/wm/init.lua).

```lua
wm.config {
  layout = "tiling",                   -- scrolling | tiling | master
  gaps = { inner = 8, outer = 8 },     -- outer can also be { top=, right=, bottom=, left= }
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

### Chords and sequences

A chord is modifiers and a key joined by `-` or `+`: `alt-h`, `cmd+ctrl-2`. The modifiers are `alt` (or `opt`), `cmd`,
`ctrl`, `shift` and `hyper` (see below). The key is a letter, a digit, or one of `esc`, `space`, `tab`, `enter`, `backspace`,
`left`, `right`, `up`, `down`, `minus`, `equal`, `comma`, `period`, `slash`, `backslash`, `semicolon`, `quote`,
`backtick`, `leftsquarebracket`, `rightsquarebracket`, `f1` to `f20`, `home`, `end`, `pageup` and `pagedown`.

A bind can also be a sequence of chords separated by `>`: `"ctrl-p>h"`, `"alt-space > t > n"`. wm takes the first chord of
a sequence from every app, so choose one your apps do not need. A key that continues no sequence cancels it and is
swallowed, as in tmux, so a typo never reaches the app you are typing in. A sequence waits until the next key or Escape:
it has no timeout. (`prefix.timeout` of old configs is still accepted and ignored.) The screenshot shortcuts of macOS
(Cmd+Shift+3, 4, 5, 6) are the exception: they go to macOS and the key hints and the waiting prefix stay, so you can take a
picture of the hints. Clicks and drags already go through the hints.

In one mode, a chord cannot be a bind by itself and also the start of a sequence, and a sequence cannot be the start of a
longer one (`a>b` and `a>b>c`). Both are config errors. `wm.bind("cmd-h", "")` with an empty string swallows a key.

### The hyper key, remaps and typing keys

With `wm.config { binds = { capslock = "hyper" } }` CapsLock becomes the `hyper` modifier: hold it with a key to make a
chord such as `hyper-k`, and a quick tap alone types Esc. wm sets the key mapping of the keyboards while it runs (like
`hidutil`: it replaces any other `UserKeyMapping`, and takes it off again when it quits). A keyboard that connects later
gets the mapping after wake or `wm daemon reload`. Quit Karabiner-Elements first: it takes the keyboard before wm sees it.
A hyper chord that nothing binds is swallowed.

```lua
wm.config { binds = { capslock = "hyper" } }

wm.remap("hyper-k", "up")                       -- types Up; the key repeats and comes up with it
wm.remap("hyper-4", "cmd-right")
wm.bind("hyper-w>1", "workspace 1")             -- Caps+w, then 1 (Caps can stay down or be released)
wm.bind("hyper-s>p", "key press play")          -- a media key
wm.bind("hyper-s>n", function()                 -- several things for one chord
  wm.press("cmd-shift-4")
  wm.exec("open -g raycast://extensions/raycast/confetti")
end)

wm.bind("hyper-v", "mode vim")                  -- a layer that stays on: a mode
wm.mode("vim", {
  h = { remap = "left" }, l = { remap = "right" }, w = { remap = "alt-right" },
  esc = "mode main", ["hyper-v"] = "mode main",
})
```

- `wm.remap(chord, key [, options])` types `key` when `chord` is pressed. Modifiers that are held besides the ones of
  `chord` go with it: after `wm.remap("hyper-h", "left")`, `hyper-shift-h` types `shift-left`. In `wm.mode`, a remap is the
  table `{ remap = "left" }`. A remap takes a single chord, not a sequence.
  A remap is the first thing that happens to a key, so it works in every place, also in the palette, the window switcher and
  the template picker: `hyper-j` → `down` moves their selection. A hyper chord with no remap and no bind types nothing there.
- `wm.press(key)` (and `wm key press <key>`) types a key now. `key` is a chord such as `cmd-shift-4`, or a media key:
  `volume_up`, `volume_down`, `mute`, `play`, `next`, `previous`, `brightness_up`, `brightness_down`.
- `wm key send` types into one app and works for a background app. `key press` types for the system. Secure Keyboard Entry
  (password fields, some terminals) blocks every key tap, so hyper chords do nothing there.
- `hyper` works in chords only. `mouse` and `wm.gesture` modifiers stay `alt`, `cmd`, `ctrl` and `shift`.

### The key panel

While a mode other than `main` is active, or while a prefix waits for its next key, a panel shows what you can press.
It has a chip with the mode name and one chip per key, with the key's `description` or else its command:

```
( resize )  ( h ) Wider   ( j ) Taller   ( k ) Shorter   ( l ) Narrower   ( esc ) Exit
```

- The order is fixed: letters and digits, then chords with modifiers, then other keys, then `esc`.
- A letter shows as it was written (`h`, `⇧y`, `⌥w`), not in capitals. Named keys show as a glyph so the chips stay narrow:
  `[ ] , . - = / \\ ; ' \``, `← ↑ → ↓`, `␣` (space), `⇥` (tab), `↩` (enter), `⌫` (backspace) and `⌦` (delete).
- A bind with `hidden = true` is left out, and so is a bind that only swallows a key. Universal binds show in every mode.
- After a prefix chord, the first chip is the prefix and the keys are the ones that can follow. A key that starts a longer
  sequence shows `…`.
- The layout follows the position. In the middle (`top-center`, `center`, `bottom-center`) the keys form a grid in a row,
  with the mode chip on the left. At a side (`top-left`, `top-right`, `bottom-left`, `bottom-right`, and the older `left` and
  `right`) the panel is a list with one key per line. A long list gets more columns instead of growing taller than 70% of
  the screen, and the columns have the same height.
- `show_keys = false` leaves only the mode chip. `wm notify` uses the same pill, with text only, even when
  `enabled = false`.

### Bind options

`wm.bind(chord, action, options)` takes a table as its third argument. Inside `wm.mode`, an action can be a table too:
`h = { "resize width +50", description = "Wider" }`.

| Option | What it does |
|---|---|
| `description` | Text for `wm list binds` and the key panel. |
| `repeating = false` | Run once per press. Without it, a held key repeats the action. |
| `repeating = true` | A second bind of the same chord: it runs for each repeat while the key is held, and the plain bind runs only when the key goes down. Alone, it runs on the press and on every repeat. |
| `release = true` | Run when the key comes up. A chord can have a press bind and a release bind. |
| `long_press = true` | Run when the key is held for `binds.long_press_timeout` seconds. A short press runs the normal bind of the same chord. |
| `universal = true` | The bind works in every mode. `submap_universal` is the same option, with the name that Hyprland uses. |
| `hidden = true` | Leave the key out of the key panel. |

`release`, `long_press` and `repeating = true` need a single chord (on a sequence `repeating` has no effect). `release` and
`long_press` cannot be combined with each other or with `repeating`. The names `release`, `long_press`, `repeating` and
`description` are the names that the Hyprland bind flags use.

A separate action for the repeats of a held key, for example a Cmd+Tab that opens the switcher once and then steps it:

```lua
wm.bind("cmd-tab", "switcher")                               -- when the key goes down
wm.bind("cmd-tab", "switcher next", { repeating = true })    -- for each repeat while it is held
```

While the switcher is open, Tab and Shift+Tab belong to the switcher itself and move its selection. `wm list binds` shows a
`repeating = true` bind with `repeat` in its `when` column.

**macOS Cmd+Tab.** wm swallows the keys of a bind, but if the macOS app switcher still opens on top of yours (for example when
you hold the keys), set `binds = { disable_system_cmd_tab = true }` in `wm.config`. wm then turns off the Cmd+Tab and
Cmd+Shift+Tab of macOS (a private call, `CGSSetSymbolicHotKeyEnabled`) and turns them on again when the option goes away
after a reload, and when wm quits. The setting belongs to your login session: if wm is killed with `kill -9` or crashes, macOS
Cmd+Tab stays off until you log out, or until you set the option, reload, and remove it again. `WM_DEBUG=1 wm daemon start`
(in a terminal) prints a line when macOS disables wm's event tap, which also sends keys to macOS. The mode name `*` is reserved for universal binds.
`wm list binds` (and `--json`) shows every bind with its mode, keys, trigger and command.

### Gestures

`wm.gesture { mods, direction, command }` runs a command when you swipe with two fingers while you hold modifiers.
`mods` is one or more of `alt`, `shift`, `ctrl` and `cmd` (`"alt+shift"`). `direction` is `left`, `right`, `up` or
`down`. With natural scrolling, which is the macOS default, it is the direction of your fingers. The command can be a
string or a Lua function. It runs once per swipe, when the scroll has gone `threshold` points (10 to 2000, default 100).

macOS does not say how many fingers scroll, so a gesture with `mods` is a modifier and a direction. A swipe on an axis that
no gesture uses goes on to the built-in Option + scroll, which moves the scrolling strip.

#### Swipes with 3 or 4 fingers

The private MultitouchSupport framework does say how many fingers touch the pad. Turn it on, and name the fingers in the
gesture instead of (or besides) the modifier:

```lua
wm.config { trackpad = { enabled = true, scroll_fingers = 3, speed = 1 } }

wm.gesture { fingers = 3, direction = "up",   command = "workspace next" }
wm.gesture { fingers = 3, direction = "down", command = "workspace prev" }
wm.gesture { fingers = 4, direction = "up",   command = "overview" }
```

- A swipe starts when the same number of fingers (3 or 4) has touched the pad for a few frames. It ends when the fingers
  lift, or when their number changes; then no new swipe starts until all fingers are up.
- A gesture claims the swipe on its axis, as above. A swipe that no gesture claims scrolls the scrolling strip when its
  finger count is `scroll_fingers` (3 by default, 4, or 0 for never). The strip goes on a little after the fingers lift
  and then settles on a column. `speed` (0.1 to 10) says how far a swipe moves the strip.
- `trackpad.enabled` is off by default. A config reload looks for trackpads again.

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
| `monitor` | Open on the workspace that this monitor shows: a role, its number (1 is the leftmost) or part of its name. `workspace` wins when both are set. |
| `focus = false` | Open without taking the focus. The window that had it gets it back. |
| `run` | A command or a list of commands to run after the other actions. |
| `stop = false` | Let later rules add to this one. By default the first match is the last. |

A rule needs `app` or `title`. Rules apply in order, and later values win.

### Workspace rules

`wm.workspace(name, options)` needs at least one option.

| Option | Meaning |
|---|---|
| `layout` | `scrolling` or `tiling`. |
| `monitor` | Bind the workspace to a monitor (a role, a number or part of its name). Showing it shows it there. |
| `default` | With `monitor`: the monitor starts with this workspace. |
| `gaps`, `border` | Settings for this workspace only. |
| `layout_options` | Tiling, scrolling and master options for this workspace only, for example `{ split_ratio = 0.6 }`. The master options have `master_` in front: `master_ratio`, `master_count`, `master_orientation`, `master_new_window`. |

## Layouts in detail

### Tiling

- `layout preselect <left|right|up|down>`: the next window that opens splits the focused one on that side, once.
- `layout split ratio 0.7` gives the focused window 70% of its split. A number from 0.1 to 0.9, or a change like `+0.1`.
- `layout split root` makes the focused window a child of the root split. It gets half the screen.
- `layout split toggle` flips the split of the window. `layout split swap` swaps its two sides.
- `layout flip` turns every split from side by side to stacked, and back.
- `window pseudo` keeps the window at the size it has now, centered in its tile. Run it again to tile it normally.
- `tiling.smart_split = true` makes a new window split the tile under the mouse pointer on the side that the pointer is
  nearest to (measured along the diagonals of the tile). A `layout preselect` still wins, and a pointer outside the
  tile means the usual split. Moving a window with `move <dir>` already swaps it with its neighbour, so there is no
  separate command to move a tile up or down.
- `tiling.split_under_pointer = true` makes a new window split the tile that the mouse pointer is over, and not the focused
  tile, on the side that the pointer is nearest to. With no tile under the pointer it uses the focused tile, as usual.
  It does not need `smart_split`. A `layout preselect` still wins.
- `tiling.force_split = "first"` puts new windows on the left or top. `tiling.split_width_multiplier = 2` keeps columns
  on an ultrawide screen before the first stacked split.

### Scrolling

- `layout column width <fraction|cycle>`, `layout column match` and `layout balance` set column widths.
  `balance` fits all columns on screen.
- `visible_columns = 3` makes 2 columns grow in proportion until they fill the screen. The widths that you chose stay
  stored, and come back when the third column opens. A lone column follows `single_window_fit` instead. With the default `"fill"` it fills the screen, until
  you set its width (`layout column width`, a resize, `layout balance`): a width that you set is kept while the column is alone.
  `layout column expand` grows the focused column into the room that the other columns on screen leave free.
- `orientation = "vertical"` turns the strip: windows become rows that scroll up and down, and `move`, `focus` and
  `resize` follow the screen (`focus down` goes to the next row). `orientation = "auto"` does this on a monitor that is
  taller than it is wide, so you can set it once and use a portrait display beside a landscape one. A workspace can set it
  in `layout_options`. A stack is side by side inside a row, tile templates turn with the screen, and the second strip
  moves to the bottom (or the top) of the screen. `window send strip horizontal` and `vertical` keep meaning the main strip
  and the second strip. Swipes with Option scroll along the strip, whichever way it runs.
- The strip does not loop. Set `wrap_focus = true`, or use `focus left --wrap`, to go from the last column to the first.
- `layout column move <first|last|n>` moves the column to a place in the strip. `n` counts from 1, and a number that is
  too large means the last place.
- `focus column <first|last|n>` focuses a column (the window that had the focus last in it). `focus stack <first|last|n>`
  focuses a window of the column you are in. `focus next` and `focus prev` walk through all windows in layout order,
  also in the tiling layout; add `--wrap` to go around.
- `window send workspace <name> --column` (and `window send monitor <monitor> --column`) sends the whole column, with
  its stack, width and tabs. It joins the layout there like `--tile`.
- `layout stack join` puts the window in the column on its left. `layout stack leave` takes it out.
  Both take a side: `layout stack join right` puts the window at the bottom of the column on its right, and
  `layout stack leave left` puts it in a new column on its left.
  `layout stack tabs` shows the column as tabs. `layout stack equalize` evens out the heights.
  `layout stack height <fraction|cycle>` gives the window a share of the column.
- A tab indicator, a thin bar with one segment per tab, shows which window of a tabbed column is on top. It is a separate
  window drawn over a few points of the column, like the focus border. `tab_indicator.enabled = false` turns it off.
- `layout column center` and `layout column center-visible` scroll the strip.
- `window maximize` grows the column to the whole zone. Run it again to restore it.
- A second, vertical strip sits at one side of the screen. `window send strip vertical` and `window send strip horizontal`
  move a window between the two, and `focus` crosses from one to the other at the edge.
- Hold Option and swipe with two fingers to move the strip. It settles on the nearest column.

### Master-stack

`wm layout set master` (or `layout = "master"`, per workspace with `wm.workspace`) puts the first windows in a big master area and
the others in a stack beside it, like dwm, xmonad and Hyprland's master layout. A lone window fills the screen.

```lua
wm.config {
  layout = "master",
  master = { ratio = 0.55, count = 1, orientation = "left", new_window = "stack" },
}
wm.bind("alt-return", "layout master promote")
wm.bind("alt-i", "layout master count +1")
wm.bind("alt-d", "layout master count -1")
wm.bind("alt-o", "layout master orientation")
```

- `orientation` is where the master area is: `left`, `right`, `top`, `bottom`, or `center` (the master in the middle, the stack on
  both sides: the first stack window on the right, the next on the left, and so on; with one stack window it is the left layout).
- `ratio` is the share of the screen along the split (0.1 to 0.9). `count` is how many windows are masters; they share the master
  area equally, and so do the windows of the stack. With as many masters as windows, they share the whole screen.
- `new_window = "stack"` puts a new window at the top of the stack; `"master"` makes it the master and the old master goes to the
  stack (dwm and xmonad).
- Commands: `layout master promote` swaps the focused window with the master (when it is the master, the first stack window takes
  its place), `layout master count <n|+n|-n>`, `layout master ratio <ratio|+n|-n>`, and `layout master orientation [place|next]`.
  They change the live layout, and the workspace keeps them while the config is the same; a changed config wins when it reloads.
  `resize width` (or `height`, with the master on top or bottom) and the mouse move the divider too; `layout balance` sets the ratio to
  0.5. `move`, `swap`, `focus` and `layout rotate` work as in the other layouts.
- Tile templates (`layout tile`) and the scrolling commands do not apply to this layout.

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
| `center` | any | the windows share the middle two thirds of the width, with a sixth of margin on each side (tiling layout only) |
| `chain` | - | back to single columns, and removes the margin of `center` |

In the scrolling layout the group is the focused window and the windows after it (or before it, when too few come after).
It is one block in the strip, so scrolling moves it as one screen. In the tiling layout the pattern applies to all tiled
windows of the workspace, and their number has to match. The picker has a one-character key on each picture: a number for
the grids, `l` and `r` for `2+1` and `1+2`, `t`, `q` and `w` for `2/3`, `3/4` and `1/4`, `z` for `center`, and `c` for the chain.

`center` is a frame, not a grid: it does not arrange the windows. It keeps the windows as they are and lays them out in the
middle two thirds, for one window or many, so a lone window is a centered window and not a maximized one. A grid applied after
`center` fills the whole width again, and so does `layout tile chain`.

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

`wm.templates` has `two`, `three`, `four`, `five`, `six`, `stack_left`, `stack_right`, `two_thirds`, `three_quarters`,
`one_quarter` and `centered` (the `center` frame).

- `name` is what `layout tile <name>` takes. It has no spaces, it is not `chain`, and it is unique in the list.
- `key` is optional: one of `a-z` or `0-9`, not `c`, unique in the list. It picks the template in the picker.
- `title` is optional: the text in the menu bar menu (the default is the name).
- `cells` is a list of `{ x, y, width, height }` as fractions of the screen, in reading order. The windows take the cells in
  that order. There are two or more cells. They fill the screen with straight cuts and do not overlap.
- `area` is optional: `{ x, y, width, height }` as fractions of the screen, the part that the cells fill. Without it they
  fill the whole screen. One cell `{ 0, 0, 1, 1 }` with a smaller `area` is a frame like `center` (tiling layout only), for example
  `{ name = "wide", cells = { { 0, 0, 1, 1 } }, area = { 0.1, 0, 0.8, 1 } }`.
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

### Floating windows, native fullscreen and marks

- `window float` moves the window to the middle of its screen. It keeps its size, but a window that fills (about) the whole work
  area gets 60% of it, so you can see it float. Windows that open floating (rules, dialogs) keep their own place.
- `window snap <place>` floats the window (a tiled one first) into a part of the work area inside the gaps: `left`, `right`,
  `top`, `bottom`, the four corners, or `center`. The same place again goes on to the next size: half, a third, two thirds
  (`center`: 60%, 80%, 40%).
- `window raise-floating` brings the floating windows of the workspace to the front. `window rescue` moves a floating
  window that is mostly off screen back into the work area of its monitor (a window larger than the area is cut down).
- `window native-fullscreen` enters or leaves macOS fullscreen. A window in macOS fullscreen has a Space of its own, so
  wm leaves it out of the layout until it comes back. `list windows` shows it as `fullscreen`.
- `window mark <name>` gives the window a name, and `window unmark [name]` takes it away (without a name, all marks of the
  window). A name belongs to one window, so marking another window with it moves the mark. `focus mark <name>` focuses the
  window, and `--window mark:<name>` acts on it. Marks last until the window closes, and wm saves them with the layout.

## Switcher and overview

```lua
wm.bind("alt-tab", "switcher")
wm.bind("alt-o", "overview")
```

Hold Alt and press Tab to open a miniature of the focused workspace with a picture of each window. Tab and Shift+Tab move
the selection, the arrow keys move it across the miniature, and letting go of Alt focuses the window. Return focuses
too, and Escape cancels. The header names the selected window and its workspace. The pictures fill their tiles (what does
not fit is cropped). `switcher = { thumbnails = false }` turns the pictures off.

`switcher --all` lists the windows of every workspace as a row of tiles, most recent first (the scope of a Cmd-Tab
switcher). Choosing a tile shows the workspace of that window. In the switcher and in the overview, Cmd+W closes the
selected window, and the panel stays open without it.

`overview` opens a panel in the middle of the screen (it does not cover the screen). A search field is at the top, and below
it there is one row for each workspace that holds windows or that a monitor shows. A row shows its workspace in the layout
that it has: a scrolling workspace is the whole strip of columns, with a dashed outline around the part that is on screen,
and a tiling workspace is the tiles of the screen. Every window is a card with its picture, the icon of its app and its title;
a floating window has a dashed edge. The workspace of the focused monitor has a dot and a bright edge. If there are more rows
than the panel can hold, the rows get smaller, and then the list scrolls.

- **Search:** type, and the cards that do not match (their title, app, workspace name or marks) are dimmed. The selection
  goes to the most recent match, and the number in the field shows how many there are. Backspace deletes a letter. Escape always
  closes the overview, also when nothing matches.
- **Keys:** the arrow keys and Tab move the selection, Return focuses the window and shows its workspace, Cmd+W closes it.
- **Mouse:** move the pointer onto a card to select it, and a red button appears at its corner that closes the window. Click a
  card to focus it. A click anywhere outside the panel closes it, and the click goes on to what is under it (so you can start a screenshot). The mouse wheel or the trackpad scrolls the rows.
- **Move a window:** **drag a card onto another row to move the window there.** The last row, an empty screen with a `+`, is a
  new workspace with the first unused number. The focus and the shown workspace stay as they are.

The pictures come from Screen Recording. A window that wm parked off screen (another workspace) is captured with a private
macOS call (SkyLight), and wm also keeps the last picture of every window that was on screen. If both fail, for example an app
that draws nothing while it is parked, the card shows the icon of the app.

## Sticky windows and zen mode

`window sticky` shows a floating window on every workspace of its monitor (a tiled window floats first): a chat, a player or
Picture-in-Picture stays with you when you switch workspaces. Press it again to end it. It follows the workspace that the monitor
shows, also a special workspace. `window remember` keeps it. (A sticky window changes its workspace name as you switch, so a
remembered or listed sticky window has the workspace it was on at that moment.)

`wm zen` shows only the focused window, centered, and hides the others (they are moved off screen, like the windows of a hidden
workspace; the layout is not changed). Focusing another window shows that one instead. `wm zen` again brings everything back.
A fullscreen window wins over it, and a restart of the daemon ends it.

```lua
wm.config { zen = { width = 0.7 } }   -- the width of the window, 0.3 to 1 of the work area
wm.bind("alt-space>shift-z", "zen")
wm.bind("alt-space>shift-s", "window sticky")
```

## Run or raise

`wm focus app <name>` focuses a window of an app (the name or the bundle id). The most recent window of the app gets the focus;
when the focus is on the app already, the next window of it, so one key walks through the windows. With `--launch` an app that has
no window starts:

```lua
wm.bind("alt-b", "focus app Safari --launch", { description = "Browser" })
wm.bind("alt-return", "focus app net.kovidgoyal.kitty --launch", { description = "Terminal" })
```

## Window memory

`wm window remember` keeps how the focused window is now. The next time a window of the same app opens, wm gives it the same
state and focuses it (and shows its workspace):

```lua
wm.bind("alt-space>r", "window remember", { description = "Remember this window" })
wm.bind("alt-space>shift-r", "window forget", { description = "Forget this window" })
```

- **What is kept:** the workspace and the monitor (by its name); floating or tiled; for a floating window its place and size,
  as fractions of the work area, so it fits a monitor of another size; maximized; the size of a pseudotiled window; in the
  scrolling layout the column width and the strip; the marks. A monitor that is gone falls back to the workspace.
- **Matching:** by the app (bundle id). `window remember --title` also keeps the exact title, for an app with several windows
  (a title that changes will not match again). A window with that title uses its entry; any other window of the app uses the
  entry without a title. Remembering again replaces the entry; `window forget` (with the same `--title`) removes it.
- **When it applies:** only to windows that open while wm runs. Windows that are open when the daemon starts do not move.
  The memory wins over `wm.rule` for the same window, and a window that comes back always takes the focus.
- `wm list memory` (`--json` for scripts) shows the entries, and `wm.query("memory")` returns them to the config. They are in
  `~/.local/state/wm/memory.json` (`$XDG_STATE_HOME/wm/memory.json`), next to `state.json`. The file has no window ids, so it
  survives a reboot.

## Command palette

`wm.bind("alt-p", "palette")` opens one text field above a list. Without a prefix it lists the running apps, each
followed by its windows; typing finds windows (by title, app, workspace and mark) and apps. Every row has an icon: the
app icon, or a small window drawn for the wm command. `>` finds wm commands:
Tab puts a command in the field, and after the command name the list shows what can follow (workspaces, modes, marks,
the values that the command takes). `/` finds the menu items of the app that was in front, with its icon. A fuzzy match is enough:
`ffx` finds Firefox. Up and down move (in the lists of apps and windows Tab and Shift-Tab move too; in the `>` list Tab
completes), Return runs the row, and Escape closes. `palette commands` starts in the
commands list. If a command is not in the list, type it in full after `>` and press Return.

With `switcher.thumbnails` on and the Screen Recording permission given (the same as the window switcher), the lists of apps and
windows show a preview on the right: the picture of the selected window, or of the most recent window of the selected app.
A window of another workspace has a picture too: wm captures windows that it parked off screen.

Drag the panel by its background (the header, the preview or the footer) to move it. wm keeps the spot as a fraction of the
screen, and opens the palette there on the screen that has the mouse.

**Cmd+Tab.** `palette --cmdtab` works like the app switcher of macOS, with the thumbnails of the palette:

```lua
wm.bind("cmd-tab", "palette --cmdtab")
wm.bind("cmd-shift-tab", "palette --cmdtab --reverse")
```

It lists the running apps (the most recent first), selects the previous one, and moves with Tab and Shift+Tab (or the arrow
keys) while you hold Cmd. Letting go of Cmd, or Return, switches to the app, and Escape cancels. Any other key closes the
palette and goes on to the app. wm swallows Tab and the arrow keys while this palette is open, so the macOS switcher does not
open on top of it. (The normal palette passes every key to its text field.)

The panel takes the keyboard without making wm the active app, so the menu items belong to the app you came from.
While the palette is open no key bind runs. Remaps still do: `wm.remap("hyper-j", "down")` moves the selection.

## Menu Anywhere

`wm.bind("ctrl-alt-m", "menu")` shows the menus of the focused app as a pop-up menu at the mouse pointer, so you do not have
to move to the menu bar. Choosing an item runs it in that app. wm reads the menus through the Accessibility API, so it
shows what the app gives it: items that an app adds only when you open its menu can be missing, and a big menu (Xcode, Office)
takes a moment. A read looks at four levels and at most 3000 items. `wm --window app:Notes menu` shows the menus of
another app.

## Mouse

- Drag an edge or corner of a tiled window. When you let go, wm moves the dividers you moved, and the neighbours follow.
- Drag a tiled window by its title bar and drop it on another tile of the same workspace. The two windows swap places. A
  drop anywhere else sends the window back to its tile.
- `wm swap <dir>` does the swap from the keyboard.
- With `mouse = { move_modifier = "alt", resize_modifier = "alt" }`, hold the modifier and drag **anywhere** in a window
  (no title bar needed). The left button moves the window, and the right button resizes it from the corner that is nearest
  to the pointer. A floating window follows the pointer. A tiled window that you move swaps places with the tile that you
  drop it on (anywhere else it goes back), and the resize of a tiled window moves the dividers like the edge drag above.
  wm swallows these clicks, so the app never sees them. Both are off until you set them, because Option-click means
  something in Finder and in many editors. The modifiers are chord text: `alt`, `alt+shift`, `ctrl+alt`, and so on.

## Command line

`wm help` lists every command and `wm help <command>` has details and examples. The same words work in `wm.bind`, in
Lua (`wm.dispatch`) and in `wm://` URLs.

```
FOCUS AND MOVE   focus <dir> | focus back | focus next|prev | focus window <id> | focus monitor <monitor> | focus layer
                 focus app <name> [--launch]
                 focus column <first|last|n> | focus stack <first|last|n>
                 move <dir> | swap <dir> | resize <width|height|smart> <+n|-n>
WINDOWS          window close | float | fullscreen | native-fullscreen | maximize | pseudo | raise-floating | rescue
                 window snap <left|right|top|bottom|top-left|top-right|bottom-left|bottom-right|center> | sticky
                 window mark <name> | unmark [name] | remember [--title] | forget [--title]
                 window send workspace <name> | monitor <monitor> | strip <horizontal|vertical>
WORKSPACES       workspace <name|back|next|prev|empty> | workspace special [name]
                 workspace move monitor <monitor>
LAYOUT           layout set <scrolling|tiling> | balance | rotate | flip | tile | preselect <dir>
                 layout split <toggle|swap|root|ratio> | column <width|match|expand|center|center-visible>
                 layout stack <join|leave|tabs|equalize|height> | column move <first|last|n>
INTERFACE        switcher | overview | palette | menu | mode <name> | pointer <window|monitor> | zen [on|off]
                 exec [options] <command> | batch <commands> | set <key> <value> | notify <text> | key send <chord> | key press <chord>
INSPECT          list [windows|workspaces|monitors|memory|binds] | subscribe | logs [-n count] [-f] [-o otel|json]
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

### Logs

The daemon writes its log to `$XDG_STATE_HOME/wm/wm.log` (`~/.local/state/wm/wm.log` by default), one JSON record per
line, and to its stderr as before. At 5 MB the file becomes `wm.log.1`, so the log takes about 10 MB at most. `wm logs`
reads the file, so it works when the daemon is stopped or has crashed.

```
$ wm logs -n 2
2026-11-16T22:57:03.123Z INFO  config loaded: /Users/me/.config/wm/init.lua source=config
2026-11-16T22:57:09.870Z ERROR config error: ... source=config

$ wm logs -f -o json
{"time":"2026-11-16T22:58:00.000Z","level":"warn","message":"blocked wm:// command 'exec'; ...","source":"url"}
```

- The default output is text in the OpenTelemetry log data model: the time (UTC), the severity (`DEBUG`, `INFO`, `WARN`,
  `ERROR`), the message, then the attributes (`source=`). A new line in a message is written `\n`, so a record is one line.
- `-o json` (`--output json`) prints one flat JSON object per line: `time`, `level`, `message` and `source`. Use it with `jq`.
- `-n count` (`--lines`) shows the last records, 100 by default; `-n 0` shows all of them. `-f` (`--follow`) waits for new
  records until you stop it.
- `source` is `lua` for `wm.log` and for scripts that fail, `config`, `exec`, `url`, `state`, `memory`, `login`, `daemon` or `window`.
  A `window` record (level `debug`) says what wm did with a window that opened: its app id, title, workspace, whether it floats,
  and which rule matched. `wm logs -f` shows why a window was tiled or floated.

### Choosing a window

`--window` takes a window id or a selector:

| Selector | The window |
|---|---|
| `focused` | the focused one |
| `app:<name>` | of that app: bundle id or app name, exact, case does not matter |
| `title:<regex>` | whose title matches the regular expression |
| `mark:<name>` | that has this mark (see `window mark`) |
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

`wm.config`, `wm.bind`, `wm.remap`, `wm.mode`, `wm.gesture`, `wm.rule`, `wm.workspace`, `wm.on`, `wm.dispatch`, `wm.query`,
`wm.exec`, `wm.press`, `wm.log` and `wm.version`.

- `wm.dispatch(command [, { window = id or selector }])` runs a command. It returns stdout, or `nil, stderr` when the
  command failed.
- `wm.query(kind)` returns a Lua table. The kinds are `windows`, `focused`, `workspaces`, `monitors` and `monitor` (the
  focused monitor). A monitor has `id`, `name`, `index` (1 is the leftmost), `role` (`main`, `secondary`, `tertiary`),
  `main`, `workspace`, `special`, `focused`, `frame` and `work_area`. `wm list monitors` shows the same, and
  `wm list monitors --focused` only the monitor that has the focus (add `--json` for scripts). The `monitor_changed` event has
  the `monitor` id, its `name` and its `workspace`, so a config can react to the monitor in use:

  ```lua
  wm.on("monitor_changed", function(e)
    if e.name:find("LG") then wm.dispatch("layout set scrolling") else wm.dispatch("layout set tiling") end
  end)
  local here = wm.query("monitor")   -- the focused monitor: here.name, here.index, here.role
  ```
- Events: `window_open`, `window_close`, `window_focus`, `workspace_changed`, `special_changed`, `monitor_changed`,
  `layout_changed`, `mode_changed` and `config_reloaded`. `wm.on(event, [filter,] handler)` takes an optional table of
  fields that must match.
- `wm.exec(command)` runs a shell command and returns nothing. It does not wait for the command and it drops its output.
  wm runs it as `/bin/zsh -c "<command>"`, which does not read `.zshrc`: use absolute paths (`/opt/homebrew/bin/htop`).
  `$HOME` and `$(...)` work. A folder such as `/Applications/Foo.app` is not a command: use `open -a Foo`, or the program
  inside it (`/Applications/Foo.app/Contents/MacOS/foo`). A command that cannot start is in `wm logs` (source `exec`).

  ```lua
  wm.bind("alt-t", function() wm.exec("open -a Terminal") end)
  wm.bind("alt-shift-t", "exec open -a Terminal")      -- the same, as a command string
  ```

  To give the new window options (a workspace, a size, floating), use the `exec` command of wm through `wm.dispatch`.
  The options are `--float`, `--tile`, `--center`, `--maximize`, `--no-focus`, `--workspace <n>`, `--monitor <m>`,
  `--width <fraction>`, `--size <w>,<h>` and `--layout <name>`, and they go before `--`. They add to the `wm.rule` rules.

  ```lua
  wm.dispatch("exec --float --center --size 0.5,0.5 -- /Applications/kitty.app/Contents/MacOS/kitty -e htop")
  ```
- `wm.press(key)` types a key now (`"play"`, `"cmd-shift-4"`), and `wm.remap(chord, key)` makes a chord type another key. See
  [The hyper key, remaps and typing keys](#the-hyper-key-remaps-and-typing-keys).
- `wm.config`, `wm.bind`, `wm.remap`, `wm.mode`, `wm.gesture`, `wm.rule` and `wm.workspace` work only while the config file
  loads (not inside a bind or an event handler). `wm.dispatch`, `wm.exec`, `wm.press`, `wm.query`, `wm.log` and `wm.on` work
  everywhere. A function bind or handler runs on its own thread, so a slow one never blocks the keyboard; one that runs
  longer than 2 seconds is stopped. `wm.log` writes to `wm logs`, a script that fails too (source `lua`).
- The config folder is on Lua's `package.path`, so a long config can be split in files: `require("hyper")` loads
  `hyper.lua` that sits next to `init.lua`. A change to `init.lua` reloads the config; after a change in a module, run
  `wm daemon reload`.

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

## Replace Karabiner-Elements with wm

wm can do the common part of a Karabiner-Elements setup that is built around a hyper key: CapsLock as the hyper key (Esc when
tapped alone), keys that type other keys (`hyper-h` types Left), layers of shortcuts (`hyper-w`, then a key) that run
commands, open apps and URLs or send media keys, and a layer that stays on (a vim mode). It does not do everything
that Karabiner does, see [What wm does not do](#what-wm-does-not-do).

### Karabiner to wm

| Karabiner-Elements | wm |
|---|---|
| CapsLock to hyper, Esc when alone | `wm.config { binds = { capslock = "hyper" } }`. A tap alone types Esc. wm uses it first, so it also closes the key panel and leaves a mode that binds Esc. |
| `from` hyper + key, `to` another key | `wm.remap("hyper-k", "up")` |
| `to` with modifiers (`right_arrow` with `left_command`) | `wm.remap("hyper-4", "cmd-right")` |
| `shell_command`, `open` an app or a URL | a function bind: `function() wm.exec("open -a Spotify") end`, or the command string `"exec open -a Spotify"` |
| Media, volume and brightness keys | `"key press play"`, `volume_up`, `volume_down`, `mute`, `next`, `previous`, `brightness_up`, `brightness_down` |
| A sublayer: press hyper + `w`, then a key | a key sequence: `wm.bind("hyper-w>1", "workspace 1")` |
| A layer that stays on (`set_variable` and `variable_if`) | a mode: `wm.bind("hyper-v", "mode vim")` with `wm.mode("vim", { ... })` |
| The layer notification | the key panel, which lists the keys that can follow, with their `description` |
| Several actions for one key (`to` is a list) | one function bind that calls `wm.exec`, `wm.press` and `wm.dispatch` |

Key names: `return_or_enter` is `enter`, `spacebar` is `space`, `escape` is `esc`, `delete_or_backspace` is `backspace`,
`delete_forward` is `delete`, `hyphen` is `minus`, `equal_sign` is `equal`, `open_bracket` is `leftsquarebracket`,
`close_bracket` is `rightsquarebracket`, `grave_accent_and_tilde` is `backtick`, and `left_arrow`, `right_arrow`, `up_arrow`
and `down_arrow` are `left`, `right`, `up` and `down`. Letters, digits, `tab`, `comma`, `period`, `slash`, `backslash`,
`semicolon`, `quote`, `home`, `end`, `pageup`, `pagedown` and `f1` to `f20` have the same names.

### Move over

If you want a full configuration to read first, the author's is [on GitHub](https://github.com/g4rcez/dotfiles/blob/master/config/wm/init.lua).

1. **Quit Karabiner-Elements** and stop it from starting at login. It takes the keyboard before wm sees it, so both cannot
   own CapsLock.
2. Give wm the Accessibility permission, as for the other binds (see [Permissions](#permissions)).
3. Put the new binds in their own file, `~/.config/wm/hyper.lua`, and load it at the end of `init.lua`:

   ```lua
   require("hyper")
   ```
4. Run `wm daemon reload`. A mistake in the file is in the menu bar, in the output of the command and in `wm logs`. Then
   `wm list binds` shows what wm took.
5. Try each kind of bind (see the list below), then delete the Karabiner configuration when you are sure.

An example of `hyper.lua`, with the shapes that you need to translate a whole file:

```lua
wm.config { binds = { capslock = "hyper" } }

local function run(command)
  return function() wm.exec(command) end
end
local function open(url) return run("open -g '" .. url .. "'") end
local function app(name) return run("open -a '" .. name .. "'") end

-- Keys that hyper + key types.
wm.remap("hyper-k", "up",    { description = "Up" })
wm.remap("hyper-j", "down",  { description = "Down" })
wm.remap("hyper-h", "left",  { description = "Left" })
wm.remap("hyper-l", "right", { description = "Right" })
wm.remap("hyper-4", "cmd-right", { description = "End of line" })
wm.remap("hyper-0", "cmd-left",  { description = "Start of line" })

-- A direct shortcut.
wm.bind("hyper-e", open("raycast://extensions/raycast/emoji-symbols/search-emoji-symbols"), { description = "Emojis" })

-- A layer: hyper + w, then a key. Every key of it is a sequence.
for n = 1, 9 do
  wm.bind("hyper-w>" .. n, "workspace " .. n, { description = "Workspace " .. n })
  wm.bind("hyper-m>" .. n, "window send workspace " .. n, { description = "Send window to " .. n })
end
wm.bind("hyper-w>f", "window fullscreen", { description = "Fullscreen" })
wm.bind("hyper-w>h", "focus left --wrap",  { description = "Focus left" })
wm.bind("hyper-w>l", "focus right --wrap", { description = "Focus right" })

-- A system layer: media keys and a script.
wm.bind("hyper-s>p", "key press play",         { description = "Play or pause" })
wm.bind("hyper-s>l", "key press next",         { description = "Next track" })
wm.bind("hyper-s>h", "key press previous",     { description = "Previous track" })
wm.bind("hyper-s>equal", "key press volume_up",   { description = "Volume up" })
wm.bind("hyper-s>minus", "key press volume_down", { description = "Volume down" })
wm.bind("hyper-s>n", run("osascript $HOME/bin/clear-notifications"), { description = "Clear notifications" })

-- Open apps.
wm.bind("hyper-o>s", app("Spotify"),  { description = "Spotify" })
wm.bind("hyper-o>t", app("Telegram"), { description = "Telegram" })

-- A layer that stays on: vim keys, until Esc (or hyper + v again).
wm.bind("hyper-v", "mode vim", { description = "Vim mode" })
wm.mode("vim", {
  h = { remap = "left",  description = "Left" },
  j = { remap = "down",  description = "Down" },
  k = { remap = "up",    description = "Up" },
  l = { remap = "right", description = "Right" },
  w = { remap = "alt-right", description = "Word right" },
  b = { remap = "alt-left",  description = "Word left" },
  esc = { "mode main", description = "Exit" },
  ["hyper-v"] = { "mode main", description = "Exit" },
})
```

What to try after the reload:

- Tap CapsLock alone: Esc. Tap it while the key panel is open: the panel closes.
- Hold CapsLock and press `k`: Up, and holding `k` repeats it. With Shift also held, it selects.
- Press `hyper-w`: the key panel shows the keys that follow. Press `1`: workspace 1. Esc cancels a sequence.
- Press `hyper-v`: the vim mode shows in the panel. `h`, `j`, `k` and `l` move, and Esc leaves.
- Quit wm: CapsLock works as it did before.

### What is different

- **A layer is a sequence, not a held key.** In Karabiner a layer works while you hold the hyper key, or stays on after a
  tap, depending on its `hold` setting. In wm, `hyper-w>1` is hyper + `w`, then `1`; the hyper key may stay down or be
  released between the two keys. Releasing it does not cancel the layer; Esc does. A layer that must stay on is a mode.
- **A chord is a bind or the start of a sequence, not both.** `hyper-w` cannot do something by itself and also start
  `hyper-w>1`. wm rejects this when the config loads. A sequence cannot start a longer one either (`a>b` and `a>b>c`).
- **Every hyper chord that is not bound is swallowed**, so a typo never types a letter into the app.
- **How CapsLock is remapped.** wm sets the key mapping of the keyboards, as `hidutil` does, to send CapsLock as F18, and
  takes it away when it quits. It replaces any other `UserKeyMapping` that is set while wm runs. A keyboard that connects
  later (Bluetooth) gets the mapping after the next wake, or after `wm daemon reload`.
- **If wm crashes**, CapsLock stays mapped to F18 until wm starts again. This puts it back at once:

  ```sh
  hidutil property --set '{"UserKeyMapping":[]}'
  ```

### What wm does not do

- **Secure Keyboard Entry.** Password fields and some terminals block every event tap, so hyper chords and remaps do nothing
  there. Karabiner works in those places because it is a driver.
- **No per-app or per-device rules.** There is no `frontmost_application_if` or `device_if`. For a chord that must act
  differently in an app, use a function bind and look at `wm.query("focused")`.
- **No left and right modifier distinction**, no `fn` or Globe key, no modifier-only chords (apart from the hyper key), no
  simultaneous keys, and no mouse button or pointing device remaps.
- **Tap and hold is only for the hyper key** (and for any other chord with `long_press = true` in the bind options, see
  [Bind options](#bind-options)). A tap of another modifier key does not do anything.
- **Media keys** are typed as system events. `next` and `previous` send the same keys as F9 and F7. Brightness works on
  displays that macOS can control with the keyboard.

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
so wm cannot keep the special windows above them.

## Saved state

wm saves its layouts to `$XDG_STATE_HOME/wm/state.json`, or `~/.local/state/wm/state.json`, half a second after a change
and when it quits. After a restart of the daemon (a rebuild, a crash, `wm daemon stop` and `start`), the windows that are
still open go back to their workspace, layout, column sizes, stacks, tile blocks, split tree, scroll position, floating
frame and monitor. wm matches windows by window id and bundle id, so an app that you closed or relaunched meanwhile
counts as new. A restored window runs no rules and fires no `window_open`.

**After a reboot** the window ids are new, and the apps open one by one over the next minute. wm notices the new start of
the Mac (the state has the time of the last start) and restores in another way: the saved layouts of all workspaces come
back at once, with a place for every saved window. Each window that opens takes the place of the saved window of the same
app, the one with the same title when there are several, else the first one in the layout. It gets the workspace, the
floating state and frame, the marks, and the place, size, stack and tabs of that window. The displays are found by their
name when their ids changed. No rule and no `window_open` hook runs for a window that took a place.

While the places wait, the layouts show empty gaps where the apps have not opened yet. After 2 minutes, or as soon as every
saved window is back, the places that nobody took are given up and the other windows close the gaps. wm saves nothing
during that time, so a start in progress does not replace the good state. If you shut the Mac down within those 2 minutes,
the old state is still there for the next start. A state that an older wm saved has no start time, so it is restored the
old way once; the next save adds it.

wm does not read or move windows while the Mac sleeps or is locked, and for two seconds after. A window moves only when
you ask.

A layout that you change in the config while wm is stopped wins over the saved one. A state saved by the removed
`native` mode is ignored. Delete the file to start fresh.

## Troubleshooting

- **Nothing happens when I press a key.** Check that wm has Accessibility permission and that `wm daemon status` says it
  runs. Without a config, wm has no key binds.
- **My config has `workspaces = "native"` and no key works.** wm no longer has native macOS desktops, so that value is an
  error and the config does not load. Delete the line, or set `workspaces = "emulated"`.
- **I rebuilt and macOS asks for permissions again.** The build was signed ad hoc. See [Signing](#signing).
- **The menu bar icon is missing.** Switch on `wm` in System Settings > Menu Bar. `wm daemon status` says
  `menu bar: hidden by macOS` when the icon is not on screen.
- **The switcher shows icons and not pictures.** Grant Screen Recording, or set `switcher = { thumbnails = false }`.
- **A window hides behind others, or stays out of the layout.** Some windows (dialogs, palettes) float by design. Use
  `wm window float` to toggle one, or add a rule.
- **My config has an error.** The old config stays active. The message is in the menu bar, in the output of
  `wm daemon reload` and in `wm logs`.
- **wm and another window manager fight.** Quit the other one. Quitting wm puts every hidden window back on screen.

## Limits

- Animations move real windows through the Accessibility API, one call per frame. Slow apps (Electron) can stutter, and a
  window with an AX call still running skips frames.
- wm cannot blur, fade or shadow other apps' windows.
- The border and the tab indicator are separate overlay windows above normal windows.
- A window with a minimum size larger than its tile overlaps its neighbours.
- Gestures with `mods` see only a modifier and a scroll direction, not the finger count. Gestures with `fingers` read the
  trackpad through the private MultitouchSupport framework. A macOS update can change it. When it cannot be loaded, wm
  says so and the gestures stay off. macOS keeps its own three-finger gestures: turn them off in System Settings >
  Trackpad (or use four fingers), or both act on the same swipe.
- When a display goes away (lid closed, display asleep, unplugged), its workspace keeps its windows, and they stay hidden.
  The display shows that workspace again when it comes back. Until then, `wm workspace N` shows it on another monitor.

## Development

```sh
timeout 300 swift test      # unit tests: layout engines, geometry, Lua host, IPC, command parsing
./build-app.sh debug        # a debug build of the app bundle
```

The app icon is `assets/icon-windows.svg`. `bundle/wm.icns` is made from it by `assets/make-icns.sh` (it needs `rsvg-convert`,
`magick` and `iconutil`), and `build-app.sh` copies it into the app. Run the script again when the SVG changes.

| Target | Role |
|---|---|
| `CLua` | Vendored Lua 5.4.7 |
| `Common` | IPC (length-prefixed JSON over a unix socket), command table, help, URL parsing and shell completion |
| `Core` | Pure layout engines, animator, gaps, navigation, the geometry of the overview. No AppKit. |
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
