---
title: "Features"
description: "The switcher, palette, hints, jump, scroll and select modes, cheatsheet, window memory, menu bar, status bar and more."
group: Features
order: 1
---
Every feature is a command. Bind it in your config, or run it with `wm <command>`. `wm help <command>` lists the flags. See [Configuration](/docs/config) for binds and the `appearance` table (the look shared by all overlays), and [CLI](/docs/cli) for the command line.

## Switcher

A miniature of the focused workspace with a picture of each window, and an overview of all workspaces.

```lua
wm.bind("alt-tab", "switcher")
wm.bind("alt-o", "overview")
```

Hold Alt and press Tab. `switcher --all` lists the windows of every workspace as a row of tiles, most recent first.

Tab and Shift+Tab or the arrow keys move the selection. Letting go of Alt, or Return, focuses the window. Escape cancels. Cmd+W closes the selected window.

The pictures need the Screen Recording permission.

**Overview.** `overview` darkens the screen and shows every workspace as a small copy of its screen, one under the other. `overview open` and `overview close` do only one of the two. Type to dim the cards that do not match. Arrows and `Tab` move the selection (`Ctrl` with `h` `j` `k` `l` or `a` `s` `w` `d` too). `Return` focuses, `Cmd+W` closes the window, `Escape` closes the overview. Drag a card onto another workspace to move the window there.

| Config key | Default | Meaning |
| --- | --- | --- |
| `switcher.thumbnails` | `true` | pictures of the windows |
| `overview.zoom` | `0.5` | a workspace is its screen times this (0.2 to 0.75) |
| `overview.gap` | `48` | points between two workspaces |
| `appearance.background` | | the dim layer behind the overview |

## Palette

One text field above a list, to find windows, apps, browser tabs, wm commands and menu items.

```lua
wm.bind("alt-p", "palette")
```

| Input | Effect |
| --- | --- |
| nothing typed | the running apps, each followed by its windows |
| text | finds windows (title, app, workspace, mark), apps and tabs; a fuzzy match is enough (`ffx` finds Firefox) |
| `>` | finds wm commands; Tab puts one in the field, then the list shows what can follow it |
| `/` | the menu items of the app that was in front |
| `Up`, `Down` | move (in the app and window lists, Tab and Shift-Tab too) |
| `Return`, `Escape` | run the row, close |
| `Cmd-0` | forget the moved spot |

- `palette commands` starts in the commands list. `palette tabs` lists all tabs. `palette reset` forgets a moved spot.
- With `switcher.thumbnails` on and Screen Recording given, the lists show a preview.

**Tabs.** An app with tabs (a browser, Rex) shows its tabs, and Return focuses the tab and its window. wm reads tabs from Chromium browsers and Safari through Apple events, from Rex, and from tmux. Firefox is not read.

**Cmd+Tab.** `palette --cmdtab` works like the app switcher of macOS: it lists the running apps, most recent first, and selects the previous one. Tab, Shift+Tab or the arrows move while you hold Cmd. Letting go of Cmd, or Return, switches. Escape cancels.

```lua
wm.bind("cmd-tab", "palette --cmdtab")
wm.bind("cmd-shift-tab", "palette --cmdtab --reverse")
```

## Hints

Click, scroll and select text from the keyboard, as in Homerow. wm has no default keys for these modes. Each lists its keys in the key panel.

```lua
wm.bind("cmd-shift-space", "hints")
wm.bind("cmd-alt-space", "hints --wait")
wm.bind("cmd-shift-j", "scroll")
wm.bind("cmd-shift-y", "select")
```

`hints` puts a label of two letters on every clickable element of the focused window, the menu bar (and its extras) and the Dock. With more than 676 elements, labels have three letters. Type the letters and wm clicks the element with a real mouse click.

| Key | Effect |
| --- | --- |
| two letters | click that element |
| second letter with `Shift` | right click |
| second letter with `Cmd` | Cmd-click |
| `/` | search: words in any order, letters in order, case ignored (`sv as` finds "Save As") |
| `Backspace` | undo a letter, then the search |
| `Tab`, `Down`, `Ctrl-N` / `Shift-Tab`, `Up`, `Ctrl-P` | next, previous match |
| `Return` | click the focused element or the only match (`Shift`: right click); again within 300 ms: double click |
| `Esc`, a mouse click | close |

**`hints --wait`** starts the search at once, with no `/`. A label highlights its element instead of clicking. `Return` clicks it.

**Scroll mode.** `scroll` numbers the scroll areas of the focused window (up to ten) and scrolls the active one, the largest first.

| Key | Effect |
| --- | --- |
| `h` `j` `k` `l` | scroll left, down, up, right by 60 points |
| `Shift` + `h` `j` `k` `l` | five times as far |
| `d`, `u` | half a page down, up |
| `gg`, `G` | top, bottom |
| `Tab`, `Shift-Tab` | next, previous area |
| `0`-`9` | the area of that number |
| `Esc`, a mouse click | close |

**Select mode.** `select` reads the text of the windows on the focused display. Type text to search, then `Return` to select the focused place. Each place then has a two-letter label.

| Select key | Effect |
| --- | --- |
| a label | select that place; a second label extends the selection |
| `h` `l`, `w` `b` `e`, `j` `k`, `0` `$` | move by character, word, line, line edge |
| `v`, `Space` | extend; grow by words |
| `y`, `Cmd-C`, `Return` | copy |
| `Shift-Return` | right-click on the first word of the selection |
| `/`, `Backspace` | back to the search |
| `Esc`, a mouse click | close |

A window that gives fewer than 8 words is read from a picture of the display, which needs Screen Recording. Password fields are not read.

| Config key | Default | Meaning |
| --- | --- | --- |
| `hints.background` | `"#ffd60af5"` | background of a label |
| `hints.text` | `"#141414"` | letters of a label |
| `hints.focus` | `"#30d158"` | label and ring of the focused element |
| `hints.area` | `"#0a84ff"` | rings and numbers of the scroll areas |
| `hints.letters` | the whole alphabet, home row first | letters of the labels: 4 to 26 different lowercase letters |
| `hints.scroll_step` | `60` | points that `h j k l` scroll (10 to 500) |
| `hints.scroll_dash_factor` | `5` | what Shift multiplies the step by (1 to 20) |
| `select.keys.<action>` | see below | chords of a select action |

Colors are `"#rrggbb"` or `"#rrggbbaa"`. The select mode keeps its own letters. `jump` uses the same colors.

`select.keys` actions: `copy`, `right_click`, `extend`, `search`, `expand`, `left`, `right`, `down`, `up`, `next_word`, `previous_word`, `word_end`, `line_start`, `line_end`. An action that you set replaces its keys. The others keep theirs. A chord can belong to one action only, and `hyper` cannot be used.

```lua
wm.config { select = { keys = { copy = { "y", "cmd-c" }, line_end = { "4", "shift-4", "cmd-right" } } } }
```

Hints and scroll show what the app gives through Accessibility, at most 6000 elements. A plain web `div` with a click handler has no label.

## Jump

`jump` puts a big number in the middle of every visible window. Type the number to pick the window.

```lua
wm.bind("alt-j", "jump")               -- focus the window
wm.bind("alt-shift-j", "jump --swap")  -- swap it with the focused window
wm.bind("alt-ctrl-j", "jump --close")  -- close it
```

Every tiled and floating window of the workspace that each monitor shows gets a number. Numbers start at 1, left to right over the displays, then top to bottom inside a display. The focused window uses the `hints.focus` color, the others `hints.background` and `hints.text`.

| Key | Effect |
| --- | --- |
| `1`-`9` | pick the window of that number |
| a second digit | with ten windows or more, `1` waits for the next digit |
| `Return` | pick the digits typed so far |
| `Backspace` | undo a digit |
| `Esc`, a mouse click | close |

`wm jump [open|close|toggle] [--swap] [--close]`. The default is `toggle`. `--swap` works for two tiled windows of the same workspace. For any other pair, the window is only focused. `--swap` and `--close` do not go together.

## Cheatsheet

Every key bind of your config on one sheet, grouped by what it does, with a filter.

```lua
wm.bind("hyper-k", "cheatsheet")
```

```
wm cheatsheet [tui|gui|cli]   # tui: in the terminal; gui: the panel (run it again to close it); cli: the keys as plain text, one per line
```

- `wm cheatsheet cli` prints every bind on one line (`alt+shift+H  # Swap left  [focus swap left]`; a chord is `hyper+W > H`), in plain text with no colors, columns or paging, so `wm cheatsheet cli | grep workspace`, `less` and `more` work. Like `tui`, it reads the config file when wm does not run.
- Typing filters the rows. `release` binds, `noop` and binds with `hidden = true` are left out. `main` and every other mode have a page each.

Type to filter. `←` `→` or Tab change the mode, `↑` `↓` scroll, `Escape` clears the filter, then closes (`Cmd-W` or a click elsewhere closes the panel).

With no terminal on stdout (a pipe), it prints plain text. `NO_COLOR` turns the colors off. When wm does not run, it reads the config file. It has no config key.

## Menu anywhere

Shows the menus of the focused app as a pop-up at the mouse pointer. Choosing an item runs it in that app.

```lua
wm.bind("ctrl-alt-m", "menu")
```

`wm --window app:Notes menu` shows the menus of another app. wm reads the menus through the Accessibility API, four levels deep and at most 3000 items. Items that an app adds only when you open its menu can be missing. It has no config key.

## Mouse

- Drag an edge or corner of a tiled window. The dividers you moved follow, and the neighbours with them.
- Drag a tiled window by its title bar and drop it on another tile of the same workspace to swap them. A drop anywhere else sends it back to its tile. `wm swap <dir>` does the swap from the keyboard.

**Modifier drag.** Hold the modifier and drag anywhere in a window. The left button moves it (a tiled window swaps with the tile you drop it on). The right button resizes it from the corner nearest to the pointer. wm swallows these clicks.

```lua
wm.config { mouse = { move_modifier = "alt", resize_modifier = "alt" } }
```

| Config key | Default | Meaning |
| --- | --- | --- |
| `mouse.move_modifier` | off | chord text: `alt`, `alt+shift`, `ctrl+alt`, ... |
| `mouse.resize_modifier` | off | the same |

Both are off until you set them, because Option-click means something in Finder and in many editors.

## Run or raise

One key: focus the app if it runs, start it if it does not.

```lua
wm.bind("alt-b", "focus app Safari --launch", { description = "Browser" })
wm.bind("alt-return", "focus app net.kovidgoyal.kitty --launch", { description = "Terminal" })
```

`<name>` is the app name or the bundle id. The command focuses the most recent window of the app. If the app already has the focus, it goes to the next window, so one key walks through the windows. With `--launch`, an app that has no window starts.

## Window memory

`wm window remember` keeps how the focused window is now. The next window of the same app that opens gets the same state and the focus.

```lua
wm.bind("alt-space>r", "window remember", { description = "Remember this window" })
wm.bind("alt-space>shift-r", "window forget", { description = "Forget this window" })
```

- **Kept:** workspace and monitor, floating or tiled, the place and size of a floating window, maximized, pseudotiled size, scrolling column width and strip, and the marks.
- **Matching:** by the app (bundle id). `window remember --title` also keeps the exact title. A window with that title uses its entry. Any other window of the app uses the entry without a title. Remembering again replaces the entry.
- **When it applies:** only to windows that open while wm runs. It wins over `wm.rule` for the same window.
- **Managed windows only:** standard windows and dialogs, not native fullscreen. `wm logs` has a `window skipped` line for each new window that wm left alone.
- The entries are in `~/.local/state/wm/memory.json` (`$XDG_STATE_HOME/wm/memory.json`). `wm list memory` (`--json`) shows them. `wm.query("memory")` returns them to the config.

**Manage the entries.** `wm memory list`, `wm memory forget <app> [--title=<text>|--all]` and `wm memory clear` (see `wm help memory`). They need the daemon, which owns the file: editing `memory.json` by hand while wm runs is overwritten. Windows that are open stay where they are.

**Floating windows remember their place.** When a floating window closes, wm keeps where it was and how big. The next window that a rule floats opens there. A window with the same app and exactly the same title gets its own place. Any other window of the app gets the place of the last one that closed.

It does not touch a window that `window remember` knows, a window whose rule gives a `size`, a tiled window, or dialogs. The last 200 places are in `float-memory.json` next to `memory.json`. Delete the file to forget them all.

| Config key | Default | Meaning |
| --- | --- | --- |
| `floating.remember_position` | `true` | floating windows keep their place |

## Swallowing

A program that you start in a terminal (`mpv movie.mkv`) takes the tile of the terminal window. The terminal comes back in the same place when the program's window closes. It is off until you turn it on.

```lua
wm.config {
  swallow = {
    enabled = true,
    terminals = { "com.mitchellh.ghostty", "com.apple.Terminal" },
    exceptions = { "us.zoom.xos" },
  },
}
```

| Config key | Default | Meaning |
| --- | --- | --- |
| `swallow.enabled` | `false` | turn swallowing on |
| `swallow.terminals` | Ghostty, Terminal, iTerm2, kitty, Alacritty, WezTerm | terminal apps (bundle ids or names, any case) |
| `swallow.exceptions` | none | apps that never swallow a terminal |

- A new window swallows when its program was started from that terminal app (wm reads the parent processes), the window is not a dialog, and its app is not a terminal and not in `exceptions`.
- It takes the slot of the terminal. The terminal is parked in a corner of the screens and `wm list` shows `swallowed`. If you go to the terminal while it is swallowed, it comes back at once.
- Events: `window_swallow` (`id`, `terminal`, `workspace`) and `window_unswallow` (`id` of the terminal, `program`, `workspace`).
- A window is not swallowed when a rule sets `workspace` or `monitor` for it, or when `window remember` knows it.

Limits: wm picks the terminal window that had the focus when the program's window opened. It cannot work for `open -a Foo`, `code .` and other apps that hand the work to a running copy.

## Menu bar

While the daemon runs, the menu bar icon shows the workspaces that have windows, lowest first. The workspace in focus is written as `<mode>:<name>`.

`T:1 2 5` means workspace 1 is in focus (tiling) and 2 and 5 have windows. `F:9` means the focused window floats, on workspace 9.

- **Mode:** `T` is tiling, `S` scrolling, `M` master and `O` monocle. `F` replaces it while the focused window floats.
- **Order:** numbers first, from the lowest (`2` before `10`), then other names in ASCII order. The workspace in focus is always listed.
- Minimized windows count. A sticky window belongs to no workspace. A special workspace is not listed.

| Config key | Default | Meaning |
| --- | --- | --- |
| `menubar.workspaces` | `"occupied"` | `"occupied"`: every workspace with windows and the one in focus. `"current"`: only the one in focus |
| `menubar.current` | `"{mode}:{name}"` | text of the workspace in focus |
| `menubar.other` | `"{name}"` | text of every other workspace |
| `menubar.separator` | `" "` | between workspaces |
| `menubar.modes` | the letters above | text of `{mode}` by layout; all optional; any text, even empty |

`current` and `other` take `{mode}`, `{name}` (cut at 7 characters), `{count}` (how many windows) and `{layout}` (`tiling`, `scrolling`, `master`, `monocle` or `floating`). Any other word in braces is a config error.

**With Lua.** `wm menubar set <text>` puts a text in the icon in place of the workspaces. `wm menubar reset` goes back to the automatic text. A config reload does not clear it. Build the text in a `wm.on` handler: see [Lua API](/docs/lua-api).

## Status bar

wm has no bar of its own. It gives any bar or widget that can run a script two things: the state now (`wm list --json`) and a stream of events (`wm subscribe`). Run a script on each event, and it asks for the whole state, so it cannot drift:

```sh
wm subscribe workspace_changed window_focus window_open window_close | while read -r _; do wm list --json | jq -r '[.workspaces[] | select(.visible) | .name] | first'; done
```

`wm subscribe --snapshot` adds a first `snapshot` line with the state. For a bar that polls, read once: `wm list workspaces --json`.

Events to follow: `workspace_changed` (`workspace`, `previous`, `monitor`), `window_open`, `window_close`, `window_moved`, `window_focus` (`id`, `app`, `title`), `window_title`, `mode_changed` (`mode`), `special_changed`, `layout_changed` (`workspace`, `layout`), `displays_changed` (`count`, `monitors`), `window_urgent` (`id`, `app`, `badge`), `window_swallow`, `window_unswallow` and `config_reloaded`.

`displays_changed` also fires once when wm starts. The same events reach `wm.on` in your config. A Lua handler that takes more than 2 seconds is stopped. See [CLI](/docs/cli) for the socket protocol.

## Saved state

wm saves its layouts to `$XDG_STATE_HOME/wm/state.json`, or `~/.local/state/wm/state.json`, half a second after a change and when it quits. Delete the file to start fresh. A layout that you change in the config while wm is stopped wins over the saved one.

**After a daemon restart** (a rebuild, a crash, `wm daemon stop` then `start`), windows that are still open go back to their workspace, layout, stacks, scroll position, floating frame and monitor. A restored window runs no rules and fires no `window_open`.

**After a reboot:** window ids are new and the apps open one by one. The saved layouts come back at once, with a place for every saved window. Each window that opens takes the place of a saved window of the same app (the one with the same title, else the first). It gets that window's workspace, floating state, marks, place, size, stack and tabs. Displays are found by name. No rule and no `window_open` hook runs for it. After 2 minutes, or when every saved window is back, unclaimed places are given up. wm saves nothing during that time.

**Sleep and lock.** wm does not read or move windows while the Mac sleeps or is locked, and for two seconds after.
