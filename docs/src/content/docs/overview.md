---
title: "Overview"
description: "What wm is, what it can do, and how layouts, workspaces, monitors, modes and rules fit together."
group: Start
order: 1
---
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

wm has no default key bindings. Until you bind keys in `init.lua`, it only reacts to the `wm` command and to the
[built-in trackpad swipes](/docs/gestures#swipes-with-3-or-4-fingers).

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
