---
title: "Key panel and bind options"
description: "The which-key panel that lists the keys of a mode, and the options of wm.bind."
group: Configure
order: 3
---
## The key panel

A panel shows what you can press while a mode other than `main` is active, or while a prefix waits for its next key.
It has a chip with the mode name and one chip per key, with the key's `description` or else its command:

```
( resize )  ( h ) Wider   ( j ) Taller   ( k ) Shorter   ( l ) Narrower   ( esc ) Exit
```

- The order is fixed: letters and digits, then chords with modifiers, then other keys, then `esc`.
- A letter shows as it was written (`h`, `⇧y`, `⌥w`), not in capitals.
- Named keys show as a glyph, so the chips stay narrow: `[ ] , . - = / \\ ; ' \``, `← ↑ → ↓`, `␣` (space), `⇥` (tab), `↩` (enter), `⌫` (backspace) and `⌦` (delete).
- A bind with `hidden = true` is left out, and so is a bind that only swallows a key.
- Universal binds show in every mode.
- After a prefix chord, the first chip is the prefix and the other chips are the keys that can follow. A key that starts a longer sequence shows `…`.
- The layout follows the position:
  - In the middle (`top-center`, `center`, `bottom-center`), the keys form a grid in a row, with the mode chip on the left.
  - At a side (`top-left`, `top-right`, `bottom-left`, `bottom-right`, and the older `left` and `right`), the panel is a list with one key per line.
  - A long list gets more columns instead of growing taller than 70% of the screen. The columns have the same height.
- `show_keys = false` leaves only the mode chip.
- `wm notify` uses the same pill, with text only, even when `enabled = false`.
- The [hints, scroll and select modes](/docs/hints) show their keys in the same panel, at the same `position` and `offset`, even
  when `enabled = false` or `show_keys = false`. The mode chip is `hints`, `scroll`, `select` or `visual`, with the search text
  and the count of matches after it.

The panel looks like every other overlay: native by default, with a system blur and the text and accent colors of macOS in light
or dark. `appearance` sets the blur, corners, fonts, colors and density for all of them (see [Appearance](/docs/appearance)).
The pill takes the corner radius of `appearance.radius`, and is a capsule when that is bigger than the pill is tall.

## Bind options

`wm.bind(chord, action, options)` takes a table as its third argument. Inside `wm.mode`, an action can be a table too:
`h = { "resize width +50", description = "Wider" }`.

| Option | What it does |
|---|---|
| `description` | Text for `wm list binds` and the key panel. |
| `repeating = false` | Run once per press. Without it, a held key repeats the action. |
| `repeating = true` | A second bind of the same chord: it runs for each repeat while the key is held, and the plain bind runs only when the key goes down. Alone, it runs on the press and on every repeat. |
| `release = true` | Run when the key comes up. A chord can have a press bind and a release bind. |
| `long_press = true` | Run when the key is held for `binds.long_press_timeout` seconds. A short press runs the normal bind of the same chord. |
| `long_press = 0.8` | The same, with a wait of its own: 0.1 to 3 seconds. |
| `universal = true` | The bind works in every mode. `submap_universal` is the same option, with the name that Hyprland uses. |
| `hidden = true` | Leave the key out of the key panel and the [cheatsheet](/docs/cheatsheet). |

- `release`, `long_press` and `repeating = true` need a single chord. On a sequence, `repeating` has no effect.
- `release` and `long_press` cannot be combined with each other or with `repeating`.
- `release`, `long_press`, `repeating` and `description` are the names that the Hyprland bind flags use.

A separate action for the repeats of a held key, for example a Cmd+Tab that opens the switcher once and then steps it:

```lua
wm.bind("cmd-tab", "switcher")                               -- when the key goes down
wm.bind("cmd-tab", "switcher next", { repeating = true })    -- for each repeat while it is held
```

- While the switcher is open, Tab and Shift+Tab belong to the switcher and move its selection.
- `wm list binds` shows a `repeating = true` bind with `repeat` in its `when` column.

**macOS Cmd+Tab.** wm swallows the keys of a bind. If the macOS app switcher still opens on top of yours (for example when
you hold the keys), set `binds = { disable_system_cmd_tab = true }` in `wm.config`.

- wm then turns off the Cmd+Tab and Cmd+Shift+Tab of macOS (a private call, `CGSSetSymbolicHotKeyEnabled`).
- It turns them on again when the option goes away after a reload, and when wm quits.
- The setting belongs to your login session. If wm is killed with `kill -9` or crashes, macOS Cmd+Tab stays off until you log out, or until you set the option, reload, and remove it again.
- `WM_DEBUG=1 wm daemon start` (in a terminal) prints a line when macOS disables wm's event tap, which also sends keys to macOS.

The mode name `*` is reserved for universal binds.
`wm list binds` (and `--json`) shows every bind with its mode, keys, trigger, command, description and `hidden` flag.
