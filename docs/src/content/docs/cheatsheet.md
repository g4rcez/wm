---
title: "Cheatsheet"
description: "Every key bind of the config on one sheet, in the terminal or in a panel, with a filter."
group: Features
order: 6
---
`wm cheatsheet` shows the key binds of your config. They are grouped by what they do (focus, windows, workspaces, layout,
interface, apps, modes). Each key is a cap: `⌥ H`, `✦ W › 3`.

Typing filters the rows. Every word has to match the title, the command, the section or the keys.

```
wm cheatsheet          # a terminal: the sheet in the terminal; anything else (a bind, a script): the panel
wm cheatsheet tui      # in the terminal
wm cheatsheet gui      # the panel over the screen; run it again to close it
```

To have the panel at hand, bind it: `wm.bind("hyper-k", "cheatsheet")`. A bind has no terminal, so it opens the panel.

## What the sheet lists

- Every bind that runs on a press, a long press, or a hold when the key has no plain bind.
- `release` binds, `noop` and binds with `hidden = true` are left out, as in the [key panel](/docs/key-panel).
- Binds that only differ in a direction or a number are one row when there are three or more: `Focus direction  ✦ ←↑↓→`,
  `Go to workspace N  ✦ 1–9`. Their descriptions (or commands) must be the same apart from that word.
- A sequence shows its steps with `›`.
- The title is the `description` of the bind, or its command (`exec ...` reads `Run ...`).
- `main` (with the binds that work in every mode) and every other mode have a page each.
- The panel and the terminal sheet open on the active mode.

## Terminal

The sheet takes the screen.

- Type to filter.
- `←` and `→` (or Tab) change the mode.
- `↑` and `↓` scroll.
- Escape clears the filter, then closes.
- Without a terminal on stdout (a pipe), it prints the sheet as plain text. `NO_COLOR` turns the colors off.
- When wm does not run, it reads the config file, so you can look at the keys before you start it.

## Panel

A panel in the middle of the screen, with the same filter and mode tabs.

- It takes the keyboard without making wm the active app, so the app you came from stays in front.
- Escape clears the filter, then closes. A click elsewhere or Cmd-W also closes it.
- It follows the light or dark look of macOS.

It needs no config key. Its look is the same as every other overlay, and `appearance.density` sets the width and the row height
(see [Appearance](/docs/appearance)).
