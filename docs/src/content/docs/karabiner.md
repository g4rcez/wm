---
title: "Replace Karabiner-Elements"
description: "Move a Karabiner-Elements setup to wm, and what is different."
group: Guides
order: 2
---
wm can do the common part of a Karabiner-Elements setup that is built around a hyper key: CapsLock as the hyper key (Esc when
tapped alone), keys that type other keys (`hyper-h` types Left), layers of shortcuts (`hyper-w`, then a key) that run
commands, open apps and URLs or send media keys, and a layer that stays on (a vim mode). It does not do everything
that Karabiner does, see [What wm does not do](#what-wm-does-not-do).

## Karabiner to wm

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

## Move over

If you want a full configuration to read first, the author's is [on GitHub](https://github.com/g4rcez/dotfiles/blob/master/config/wm/init.lua).

1. **Quit Karabiner-Elements** and stop it from starting at login. It takes the keyboard before wm sees it, so both cannot
   own CapsLock.
2. Give wm the Accessibility permission, as for the other binds (see [Permissions](/docs/install#permissions)).
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

## What is different

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

## What wm does not do

- **Secure Keyboard Entry.** Password fields and some terminals block every event tap, so hyper chords and remaps do nothing
  there. Karabiner works in those places because it is a driver.
- **No per-app or per-device rules.** There is no `frontmost_application_if` or `device_if`. For a chord that must act
  differently in an app, use a function bind and look at `wm.query("focused")`.
- **No left and right modifier distinction**, no `fn` or Globe key, no modifier-only chords (apart from the hyper key), no
  simultaneous keys, and no mouse button or pointing device remaps.
- **Tap and hold is only for the hyper key** (and for any other chord with `long_press = true` in the bind options, see
  [Bind options](/docs/key-panel#bind-options)). A tap of another modifier key does not do anything.
- **Media keys** are typed as system events. `next` and `previous` send the same keys as F9 and F7. Brightness works on
  displays that macOS can control with the keyboard.
