---
title: "Hotkeys of the starter templates"
description: "The keys of the six `wm init` templates: Omarchy, macOS, Windows, i3, Hyprland and Niri."
group: Configure
order: 6
---
`wm init <name>` writes `~/.config/wm/init.lua` with the keys of one system (see [First five minutes](/docs/first-five-minutes)).
This page lists them.

- `mod` is the main modifier. You pick it in `wm init` (or with `--mod=alt`). To change it later, edit `local mod = "..."` at the top of `init.lua`.
- `N` is a digit from 1 to 9.
- Keys with a fixed modifier (`alt-h`, `cmd-tab`) ignore `mod`.
- Every template also loads `shortcuts.toml` with `wm.shortcuts()`.

| Template | Default `mod` | Layout |
|---|---|---|
| `omarchy` (default) | `cmd` | tiling |
| `osx` | `ctrl` | tiling |
| `windows` | `alt` | tiling |
| `i3` | `alt` | tiling |
| `hyprland` | `alt` | tiling |
| `niri` | `alt` | scrolling |

## Omarchy

Keys from [Omarchy](https://omarchy.org/manual/hotkeys/), with `cmd` as Super. `hyper` is not allowed as `mod`. `alt*` and `ctrl*`
mean `alt` and `ctrl`, or `cmd` when `mod` is that key.

| Keys | Action |
|---|---|
| `mod-space` | command palette |
| `mod-alt*-space` | overview |
| `mod-return` | terminal |
| `mod-w`, `mod-q` | close window |
| `mod-t` | float / tile |
| `mod-j` | toggle split |
| `mod-o` | sticky window |
| `mod-p` | pseudo-tiling |
| `mod-f` | fullscreen |
| `mod-alt*-f` | maximize |
| `mod-ctrl*-f` | native fullscreen |
| `mod-l` / `mod-alt*-l` | next / previous layout |
| `mod-ctrl*-l` | lock screen |
| `mod-shift-r` | reload config |
| `mod-N` | go to workspace N |
| `mod-shift-N` | send window to workspace N |
| `mod-shift-alt*-N` | send window, stay here |
| `mod-tab` / `mod-shift-tab` | next / previous workspace |
| `mod-ctrl*-tab` | last workspace |
| `mod-s` / `mod-alt*-s` | show scratchpad / send window to it |
| `mod-backtick` / `mod-shift-backtick` | show Quake console / send window to it |
| `mod-<arrow>` | focus |
| `mod-shift-<arrow>` | swap |
| `mod-shift-ctrl*-<arrow>` | send window to monitor |
| `mod-shift-alt*-<arrow>` | send workspace to monitor |
| `mod-minus` / `mod-equal` | width −50 / +50 |
| `mod-shift-minus` / `mod-shift-equal` | height −50 / +50 |
| `mod-alt*-minus` / `mod-alt*-equal` | width −10 / +10 |
| `mod-ctrl*-minus` / `mod-ctrl*-equal` | width −200 / +200 |
| `mod-g` | column as tabs |
| `mod-alt*-g` | leave the column |
| `mod-alt*-tab` | next window |
| `mod-alt*-1` to `5` | focus tab N |
| `alt-tab` / `alt-shift-tab` | switcher (not when `mod` is `alt`) |
| `mod-ctrl*-c` | capture menu |
| `mod-ctrl*-alt*-c` | screenshot of an area |
| `mod-ctrl*-e` | emoji picker |

Apps, all with `mod-shift-`:

| Key | App | Key | App |
|---|---|---|---|
| `return` | Safari | `f` | Finder |
| `m` | Spotify | `slash` | 1Password |
| `q` | Calculator | `t` | Activity Monitor |
| `c` | Calendar | `e` | Mail |
| `a` | ChatGPT | `g` | Signal |
| `p` | Photos | `s` | Maps |
| `o` | Obsidian | `y` | YouTube |

`mod-alt*-shift-g` opens WhatsApp.

## macOS

`mod` is `ctrl`. The `alt` keys avoid the shell keys `ctrl-h/j/k/l`.

| Keys | Action |
|---|---|
| `cmd-tab` | switcher |
| `mod-up` | overview |
| `mod-left` / `mod-right` | previous / next workspace |
| `mod-N` | go to workspace N |
| `mod-shift-N` | send window to workspace N |
| `mod-shift-<arrow>` | snap to a half |
| `mod-shift-enter` | maximize |
| `mod-shift-c` | center window |
| `alt-h/j/k/l` | focus |
| `alt-shift-h/j/k/l` | swap |
| `alt-f` | fullscreen |
| `alt-space` | float / tile |
| `alt-p` | command palette |
| `alt-enter` | terminal |
| `alt-shift-r` | reload config |

## Windows

`mod` replaces the Windows key.

| Keys | Action |
|---|---|
| `mod-left` / `mod-right` | snap to a half |
| `mod-up` | maximize |
| `mod-down` | back to tiling |
| `mod-shift-left` / `mod-shift-right` | send window to monitor |
| `alt-tab` | switcher |
| `alt-f4` | close window |
| `mod-ctrl-tab` | overview |
| `mod-ctrl-left` / `mod-ctrl-right` | previous / next workspace |
| `mod-ctrl-d` | new workspace |
| `mod-N` | go to workspace N |
| `mod-shift-N` | send window to workspace N |
| `mod-e` | Finder |
| `mod-r` | command palette |
| `mod-enter` | terminal |
| `mod-shift-s` | screenshot of an area |
| `mod-shift-r` | reload config |

## i3

`mod` is Mod1. Focus uses `j k l ;`, as in i3.

| Keys | Action |
|---|---|
| `mod-enter` | terminal |
| `mod-shift-q` | close window |
| `mod-d` | command palette |
| `mod-shift-c` | reload config |
| `mod-j/k/l/semicolon` or `mod-<arrow>` | focus left / down / up / right |
| `mod-shift-j/k/l/semicolon` or `mod-shift-<arrow>` | swap |
| `mod-h` / `mod-v` | next window opens right / below |
| `mod-e` | toggle split |
| `mod-f` | fullscreen |
| `mod-shift-space` | float / tile |
| `mod-space` | switch between floating and tiled |
| `mod-s` / `mod-t` | scrolling / tiling layout |
| `mod-minus` / `mod-shift-minus` | show scratchpad / send window to it |
| `mod-N` | go to workspace N |
| `mod-shift-N` | send window to workspace N |
| `mod-r` | resize mode |

In resize mode, `j k l ;` or the arrows resize by 50. `enter` or `esc` leave it.

## Hyprland

`mod` is `$mainMod`.

| Keys | Action |
|---|---|
| `mod-q` | terminal |
| `mod-c` | close window |
| `mod-e` | Finder |
| `mod-v` | float / tile |
| `mod-r` | command palette |
| `mod-p` | pseudo-tiling |
| `mod-j` | toggle split |
| `mod-f` | fullscreen |
| `mod-<arrow>` | focus |
| `mod-shift-<arrow>` | swap |
| `mod-1` to `mod-0` | go to workspace 1 to 10 |
| `mod-shift-1` to `mod-shift-0` | send window to workspace 1 to 10 |
| `mod-s` / `mod-shift-s` | show magic workspace / send window to it |

## Niri

`mod` is Mod. Left and right move between columns, up and down inside one.

| Keys | Action |
|---|---|
| `mod-t` | terminal |
| `mod-d` | command palette |
| `mod-q` | close window |
| `mod-o` | overview |
| `mod-shift-r` | reload config |
| `mod-h/j/k/l` or `mod-<arrow>` | focus |
| `mod-home` / `mod-end` | first / last column |
| `mod-shift-h` / `mod-shift-l` (or arrows) | focus monitor left / right |
| `mod-ctrl-h/j/k/l` or `mod-ctrl-<arrow>` | move window |
| `mod-u` / `mod-i` | next / previous workspace |
| `mod-N` | go to workspace N |
| `mod-ctrl-N` | send column to workspace N |
| `mod-comma` / `mod-period` | join / leave the column on the left |
| `mod-w` | column as tabs |
| `mod-r` | cycle column width |
| `mod-f` | expand column |
| `mod-shift-f` | fullscreen |
| `mod-c` | center column |
| `mod-minus` / `mod-equal` | width −50 / +50 |
| `mod-v` | float / tile |
| `mod-shift-v` | switch between floating and tiled |
