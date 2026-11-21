---
title: "Jump to a window"
description: "Number the visible windows and pick one by its number."
group: Features
order: 8
---
`jump` puts a giant number in the middle of every visible window, as the pane select of Zellij does. Type the number to pick the window. wm has no default key for it:

```lua
wm.bind("alt-j", "jump")               -- focus the window
wm.bind("alt-shift-j", "jump --swap")  -- swap it with the focused window
wm.bind("alt-ctrl-j", "jump --close")  -- close it
```

## Which windows, which numbers

- Every tiled and floating window of the workspace that each monitor shows gets a number. Windows of other workspaces do not.
- Numbers start at 1. They go from left to right over the displays, then from top to bottom (and left to right) inside a display.
- The number of the focused window uses the `focus` color. The others use `background` and `text`. See [Label colors](/docs/hints#label-colors).
- The size of a number follows the size of its window.

## Keys

| Key | Effect |
| --- | --- |
| `1`-`9` | pick the window of that number |
| a second digit | with ten windows or more, `1` waits for the next digit (`1` then `0` is 10) |
| `Return` | pick the window of the digits typed so far (`1` when 10 also exists) |
| `Backspace` | undo a digit |
| `Esc`, a mouse click | close |

- A number never starts with `0`, and a number that no window has does nothing.
- A shortcut with Cmd, Ctrl or Alt ends the mode and goes to the app.
- Any other key ends the mode too, so it never gets stuck.
- Opening `jump` closes `hints`, `scroll` and `select`, and the other way around.

## Flags

```
wm jump [open|close|toggle] [--swap] [--close]
```

- With no flag, the window is focused.
- `--swap`: the window trades places with the focused one. It works for two tiled windows of the same workspace. For any other pair, the window is only focused. Picking the focused window does nothing.
- `--close`: the window is closed.
- `--swap` and `--close` do not go together.
- `open`, `close` and `toggle` work as in `hints`. The default is `toggle`.
