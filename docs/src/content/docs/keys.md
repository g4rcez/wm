---
title: "Keys, chords and the hyper key"
description: "Chords and sequences, the hyper key, remaps, typing keys and per-keyboard settings."
group: Configure
order: 2
---
## Chords and sequences

A chord is modifiers and a key joined by `-` or `+`: `alt-h`, `cmd+ctrl-2`. The modifiers are `alt` (or `opt`), `cmd`,
`ctrl`, `shift` and `hyper` (see below). The key is a letter, a digit, or one of `esc`, `space`, `tab`, `enter`, `backspace`,
`left`, `right`, `up`, `down`, `minus`, `equal`, `comma`, `period`, `slash`, `backslash`, `semicolon`, `quote`,
`backtick`, `leftsquarebracket`, `rightsquarebracket`, `f1` to `f20`, `home`, `end`, `pageup` and `pagedown`.

The last key can also be the symbol itself: `[` `]` `-` `=` `,` `.` `/` `\` `;` `'` or `` ` ``. `"cmd-shift-["` is
`"cmd-shift-leftsquarebracket"` and `"cmd-shift--"` is `"cmd-shift-minus"`. The symbol has to be the last key of the chord. `+` is
always a separator (it is Shift with `=` on a US keyboard), so type `shift-equal`.

A bind can also be a sequence of chords separated by `>`: `"ctrl-p>h"`, `"alt-space > t > n"`. wm takes the first chord of
a sequence from every app, so choose one your apps do not need. A key that continues no sequence cancels it and is
swallowed, as in tmux, so a typo never reaches the app you are typing in. A sequence waits until the next key or Escape:
it has no timeout, and it ends after one command unless `wm.commands` says otherwise. (`prefix.timeout` of old configs is still accepted and ignored.) The screenshot shortcuts of macOS
(Cmd+Shift+3, 4, 5, 6) are the exception: they go to macOS and the key hints and the waiting prefix stay, so you can take a
picture of the hints. Clicks and drags already go through the hints.

### Many commands after one prefix

By default a sequence ends after one command (`normal`). With `mode = "persistent"` the keys after the prefix stay active, as in a
Hyprland submap that you leave by waiting: press the prefix once and then the keys as many times as you want. The sequence ends
when `timeout` milliseconds pass without a command, or on Escape.

```lua
wm.commands = { mode = "persistent", timeout = 800 }   -- mode: "normal" | "persistent"; timeout: 100 to 10000 ms, default 800
wm.bind("alt-space>h", "resize width -50")
wm.bind("alt-space>l", "resize width +50")
-- alt-space, then h h l h ...: the key panel stays until 800 ms pass without a key
```

- The first wait after the prefix has no timeout. The timer starts when the first command has run and restarts with each command.
- A key that is not a command of the prefix ends the sequence and goes on to the app, so fast typing loses no key. (The first key
  after the prefix keeps the old rule: a wrong key is eaten.)
- A command that goes to another mode (`mode resize`) ends the sequence.
- `wm.config { commands = { ... } }` is the same as `wm.commands = { ... }`. Binding modes (`wm.mode`) are not changed: they stay on
  until you leave them.

In one mode, a chord cannot be a bind by itself and also the start of a sequence, and a sequence cannot be the start of a
longer one (`a>b` and `a>b>c`). Both are config errors. `wm.bind("cmd-h", "")` with an empty string swallows a key.

## Shortcuts window and shortcuts.toml

You can also keep binds in `shortcuts.toml` and manage them from the **Shortcuts…** item of the menu bar menu: add, edit and
delete, with the keys checked before the file is saved. Type the keys or press **Record** and press them, `hyper` too. `wm.shortcuts()` in `init.lua` binds them, and a `wm.bind` for the
same keys that comes after it wins. `wm doctor` lists those conflicts. The format and the rules are in
[shortcuts.toml](/docs/config#shortcutstoml).

## The hyper key, remaps and typing keys

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

### Keyboards

The CapsLock mapping reaches every keyboard that macOS has, also one that connects later (USB, Bluetooth): wm sees it come and
gives it the mapping within a second, and again after sleep and on `wm daemon reload`. A keyboard whose keys come through a
consumer-control or mouse part (the Dygma Raise, for example) is found too. `wm query keyboards` shows them:

```
$ wm query keyboards
NAME                                ID         TRANSPORT  BUILT-IN  STATE    CAPSLOCK
Apple Internal Keyboard / Trackpad  0000:0000  FIFO       yes       enabled  hyper
Raise                               1209:2201  USB        no        enabled  hyper
```

`id` is `vendor:product` in hex (a built-in keyboard has none: use its name). `capslock` is what the system reports now: `hyper`
means CapsLock sends F18 on this keyboard. `wm query keyboards --json` and `wm.query("keyboards")` give the same list as data.

`keyboards` in `wm.config` turns a keyboard on or off for wm. Every keyboard is on unless the config says no:

```lua
wm.config { keyboards = {
  default = true,                                  -- what a keyboard that is not named gets
  ["Apple Internal Keyboard / Trackpad"] = true,   -- by name (the match ignores case) ...
  ["1209:2201"] = true,                            -- ... or by vendor:product. The id wins over the name.
  -- ["Some USB Receiver"] = false,                -- keeps its own CapsLock
} }
```

A keyboard that wm manages has CapsLock as the hyper key. One that the config turns off gets wm's mapping taken away. What wm
cannot do is tell which keyboard a key came from, so the binds (`alt-h`, remaps of the hyper key) work on all keyboards: `keyboards`
decides where CapsLock becomes the hyper key.
