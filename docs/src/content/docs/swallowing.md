---
title: "Window swallowing"
description: "A program that you start in a terminal takes the place of the terminal window, and the terminal comes back when it closes."
group: Features
order: 12
---
You type `mpv movie.mkv` in a terminal. The video window opens, and the terminal window is still there, taking a tile and doing
nothing. With swallowing, the video window takes the tile of the terminal, and the terminal comes back in the same place when
the video window closes. It is the window swallowing of Hyprland and dwm.

It is off until you turn it on:

```lua
wm.config {
  swallow = {
    enabled = true,
    terminals = { "com.mitchellh.ghostty", "com.apple.Terminal" },   -- default: Ghostty, Terminal, iTerm2, kitty, Alacritty, WezTerm
    exceptions = { "us.zoom.xos" },                                   -- apps that never swallow a terminal
  },
}
```

`terminals` and `exceptions` are bundle ids or app names, and case does not matter.

## What happens

- A new window swallows a terminal window when its program was started from that terminal app (wm looks at the parent processes
  of the program), the window is a normal window (not a dialog), and its app is not a terminal or in `exceptions`.
- The program's window takes the slot of the terminal in the layout: position, size, column, stack, `pseudo` and `maximize`. If the
  terminal floated, the new window floats where the terminal was.
- The terminal window is parked in a corner of the screens, like a window of a hidden workspace. It is not in the switcher, the
  palette or the focus order.
- When the program's window closes, the terminal comes back in its slot (on the workspace where the program's window is by then) and
  gets the focus.
- If you go to the terminal while it is swallowed (Cmd-Tab, the Dock), it comes back at once and the program's window stays tiled
  beside it.
- If the terminal closes while it is swallowed, the program's window stays as a normal window.
- `wm list` shows `swallowed` for the parked terminal. The events are `window_swallow` (`id` of the program's window, `terminal`,
  `workspace`) and `window_unswallow` (`id` of the terminal, `program`, `workspace`).
- A rule that sets `workspace` or `monitor` for the program's window, and a window that `window remember` knows, are not swallowed.

## Limits

wm cannot always tell which terminal *window* started a program. A terminal runs the shells of all its windows as children of one
process, so the process tree names the terminal app, not the window. wm takes the terminal window that had the focus when the program's
window opened, which is the window where you typed the command, and otherwise the terminal window that you used last. It is wrong when
you move the focus to another terminal window before the program's window appears (a slow app, or a command that you started in the
background).

It works for a program that the shell starts itself, such as `mpv`, `zathura`, `neovide` or a binary inside an `.app`. It cannot work for:

- `open -a Foo` and `open file.pdf`: the app is started by macOS, not by the shell.
- `code .` and any app that hands the work to a copy that already runs: the window belongs to the old process.
- Apps that launch through a helper or `launchd`.

A restart of wm forgets what was swallowed: the parked terminal windows come back as normal windows.
