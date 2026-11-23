---
title: "Getting started"
description: "What wm is, how to install it, and the first five minutes."
group: Start
order: 1
---
wm is a tiling window manager for macOS. It is written in Swift, runs with SIP on, and you configure it in Lua.

## How wm thinks

- **Layouts.** Each workspace has one layout, and you can change it while wm runs.
  - `scrolling` puts windows in columns on a strip that moves sideways, as niri and PaperWM do. A new window opens beside the focused one and never resizes the others.
  - `tiling` splits the screen in a binary tree, as Hyprland's dwindle layout does. A new window splits the focused one.
  - Floating windows sit above the layout. See [Layouts](/docs/layouts).
- **Workspaces.** They are emulated, as in AeroSpace: wm hides the windows of other workspaces at a screen corner, so it needs no macOS desktops. Names are free.
- **Monitors.** A workspace shows on one monitor at a time. Name a monitor by role (`main` has the menu bar; `secondary` and `tertiary` are the others from left to right), by number (1 is the leftmost) or by part of its name.
- **Special workspaces.** A scratchpad, like Hyprland's. One key shows it on the focused monitor, and the same key hides it.
- **Modes.** A mode is a separate set of binds. Enter one with `mode <name>`, leave with `mode main`.
- **Rules.** A rule matches new windows by app or title and decides where they go and how they look.

One command set has three entry points: the `wm` CLI, Lua (`wm.dispatch`) and `wm://` URLs. See [Command line](/docs/cli) and [Lua API](/docs/lua-api).

wm has no default key bindings. Until you bind keys in `init.lua`, it only reacts to the `wm` command and to the built-in trackpad swipes (see [Configuration](/docs/config)).

## Install

Requirements:

- macOS 14 or later.
- The Swift 6.2 toolchain (Xcode or the command line tools).
- No other window manager running (AeroSpace, yabai, Amethyst). Two of them fight over the same windows.

There is no published binary. Homebrew builds wm from source for you, or you build it yourself.

### Homebrew

```sh
brew install g4rcez/tap/wm
wm daemon start
```

- The formula needs the Swift 6.2 toolchain (Xcode 26 or newer).
- It builds the latest tagged release. `brew install --HEAD g4rcez/tap/wm` builds `main`.
- It links `wm` and `wmd` in `$(brew --prefix)/bin`.

### Build from source

```sh
git clone https://github.com/g4rcez/wm.git wm
cd wm
make install CODESIGN_IDENTITY="<name>"    # build, sign, copy to /Applications/wm.app, link wm in ~/.local/bin, start it
```

- `make` lists the other tasks, such as `make test` and `make identities` (lists your code-signing certificates).
- `make install` uses `CODESIGN_IDENTITY`, else the first "Apple Development" certificate. It stops when there is none.
- `./build-app.sh` builds `.build/wm.app` and starts it. `NO_START=1` skips the start, `debug` makes a debug build.

### Signing

macOS keeps the Accessibility and Screen Recording grants of an app by its signature. An ad hoc signature changes at every build, so macOS asks for the permissions again. Homebrew signs ad hoc.

- To keep the grants, sign with your own certificate: `codesign --force --sign "<certificate>" "$(brew --prefix)/opt/wm/wm.app"`.
- For `start_at_login`, copy the app to a fixed place: `ditto "$(brew --prefix)/opt/wm/wm.app" /Applications/wm.app`.

### First run

The first time wm starts, it opens a **setup window**. It moves no window until you press **Start managing windows**.

- The window shows the permissions and checks them each second, so you can grant them in System Settings and come back. Start is enabled when Accessibility is granted.
- When you have no config, it offers a starter. Pick a preset (Omarchy is the first) and a modifier key. **Write config** saves `~/.config/wm/init.lua`.
- Pressing Start writes `~/.local/state/wm/onboarded`. Delete the file to see the window again.

### Permissions

| Permission | Needed | Used for |
| --- | --- | --- |
| Accessibility | Required | Moving windows. System Settings > Privacy & Security > Accessibility. |
| Screen Recording | Optional | Window pictures in the Alt+Tab switcher and the overview (otherwise the app icon and title), and `wm select` on windows that draw their own text. |
| Automation | Optional | The palette reads and selects browser tabs (and brings Rex to the front). macOS asks once for each app. System Settings > Privacy & Security > Automation > `wm`. |

The menu bar icon needs one more switch: System Settings > Menu Bar > "Allow in the Menu Bar" > `wm`.

### Completion

```sh
eval "$(wm completion zsh)"   # in ~/.zshrc, after compinit
eval "$(wm completion bash)"  # in ~/.bashrc
wm lsp --write                # once: completion for init.lua in your editor
```

### Run it

```sh
wm daemon start    # starts wm.app in the background and returns when the daemon answers
wm daemon status   # whether it runs, the workspace, the mode, the window count
wm daemon stop     # quits wm; hidden windows come back on screen
wmd --background   # from a terminal: a detached daemon that survives closing the terminal
```

The menu bar shows the workspaces that have windows. Mode letters: `T` tiling, `S` scrolling, `M` master, `F` a floating focused window.

To start wm at login, copy `wm.app` to `/Applications` and set `start_at_login = true` in the config.

## First five minutes

1. Run `wm init [omarchy|osx|windows|i3|hyprland|niri]` to start from the keys of another system. Without a name, it writes the [Omarchy](https://omarchy.org/manual/hotkeys/) keys.
   - It asks for the main modifier: `alt`, `cmd`, `ctrl` or `hyper`. `--mod=alt` skips the question.
   - It writes the binds to `~/.config/wm/shortcuts.toml`, and `~/.config/wm/init.lua` with the settings, the modes and the line `wm.shortcuts()`.
   - If a file exists, `wm init` prints the template and leaves the files alone. `--force` replaces them.
2. Or write `~/.config/wm/init.lua` by hand:

```lua
wm.config {
  layout = "tiling",
  gaps = { inner = 8, outer = 8 },
  border = { enabled = true, width = 2, active = "#89b4fa" },
}

wm.bind("alt-h", "focus left --wrap")
wm.bind("alt-l", "focus right --wrap")
for n = 1, 9 do
  wm.bind("alt-" .. n, "workspace " .. n)
  wm.bind("alt-shift-" .. n, "window send workspace " .. n)
end
wm.bind("alt-space", "window float")
wm.bind("alt-s", "layout set scrolling")
wm.bind("alt-t", "layout set tiling")
wm.bind("alt-shift-c", "daemon reload")
```

3. Save the file. wm reloads it on its own. `wm daemon reload` does the same by hand. A reload shows a notification, `Config reloaded: init.lua` or `wm: config error` with the message. On an error, the old config stays active.
4. Open a few windows and try the keys.

The Omarchy template uses `cmd` as its main modifier, in the place of Super. These are the keys you need first:

| Keys | Action |
| --- | --- |
| `mod-space` | Open the palette |
| `mod-w` or `mod-q` | Close a window |
| `mod-N` and `mod-shift-N` | Show workspace N, send the window there |
| `mod-arrows` and `mod-shift-arrows` | Focus and swap |
| `mod-l` | Cycle the layouts (tiling, scrolling, floating) |
| `mod-s` and `mod-backtick` | Show the scratchpad and the Quake console (special workspaces) |
| `mod-return` | Open a terminal |

Run `wm help` to see every command. For keys, binds, rules and appearance see [Configuration](/docs/config). For the switcher, palette, hints and the rest, see [Features](/docs/features). If something fails, see [Troubleshooting](/docs/troubleshooting).
