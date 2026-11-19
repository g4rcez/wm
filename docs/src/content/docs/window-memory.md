---
title: "Window memory"
description: "Remember how a window is now, and give the same state to the next window of that app."
group: Features
order: 4
---
`wm window remember` keeps how the focused window is now. The next time a window of the same app opens, wm gives it the same
state and focuses it (and shows its workspace):

```lua
wm.bind("alt-space>r", "window remember", { description = "Remember this window" })
wm.bind("alt-space>shift-r", "window forget", { description = "Forget this window" })
```

- **What is kept:** the workspace and the monitor (by its name); floating or tiled; for a floating window its place and size,
  as fractions of the work area, so it fits a monitor of another size; maximized; the size of a pseudotiled window; in the
  scrolling layout the column width and the strip; the marks. A monitor that is gone falls back to the workspace.
- **Matching:** by the app (bundle id). `window remember --title` also keeps the exact title, for an app with several windows
  (a title that changes will not match again). A window with that title uses its entry; any other window of the app uses the
  entry without a title. Remembering again replaces the entry; `window forget` (with the same `--title`) removes it.
- **When it applies:** only to windows that open while wm runs. Windows that are open when the daemon starts do not move.
  The memory wins over `wm.rule` for the same window, and a window that comes back always takes the focus.
- **Only managed windows:** wm manages standard windows and dialogs, and not windows in native fullscreen. Memory, rules and
  `window remember` do not reach any other window (some games and helper windows). From a key bind, `window remember` and
  `window forget` show a notification with what they did, or why they could not (`the focused window is not managed by wm`).
  `wm logs` has a `window skipped` line, with the role and the subrole, for each new window that wm left alone.
- `wm memory` manages the entries from the command line, with no window needed (see [below](#managing-the-entries)).
- `wm list memory` (`--json` for scripts) shows the entries, and `wm.query("memory")` returns them to the config. They are in
  `~/.local/state/wm/memory.json` (`$XDG_STATE_HOME/wm/memory.json`), next to `state.json`. The file has no window ids, so it
  survives a reboot.

### Managing the entries

An entry applies to every new window of its app, so a wrong one (a Rex window that always floats) is easy to miss. `wm memory`
shows and removes entries without a window to focus:

```sh
wm memory list                         # the same as `wm list memory`; --json for scripts
wm memory forget com.superlogical.rex  # the entry of the whole app (the name of the app works too, as `list` shows it)
wm memory forget Kitty --title=mail    # only the entry that has this exact title
wm memory forget Kitty --all           # every entry of the app, whatever its title
wm memory clear                        # every entry of every app
```

- **App:** the bundle id or the name, whatever the case. `wm memory list` shows the names. When the app has no entry of that kind,
  the command fails (exit 1); if the app has other entries, the error says to use `--title=<text>` or `--all`.
- **Windows that are open** stay where they are. Only the next window of the app opens as if nothing was remembered; use
  `wm window float off` or `wm window float on` to change one that is open.
- **Floating places:** `memory clear` does not touch `float-memory.json`, the places that closed floating windows keep.
- `wm memory` needs the daemon, which owns the file: editing `memory.json` by hand while wm runs is overwritten.

### Floating windows remember their place

Nobody has to ask for this one. When a **floating** window closes, wm keeps where it was and how big it was. The next window that
a rule floats (`float = true`, also the [default floating rules](/docs/rules#default-floating-rules): the picture-in-picture window of Meet,
Finder, Preview) opens **there**, with that size, instead of the place that the rule or the app gives. Move or resize a Finder window
once, close it, and the next Finder window opens at that place.

- **Matching:** a window with the same app and exactly the same title gets its own place (the Meet window); any other window of
  the app gets the place of the last one that closed (a Finder window of another folder). The place is a fraction of the work area of
  the monitor, so it fits a monitor of another size. The window also opens on that monitor, when it is connected.
- **What it does not touch:** windows that were open when the daemon started, a window that `window remember` knows (that wins), a
  tiled window (a window that you floated by hand does not open floating next time), and dialogs, which wm floats by themselves.
- **Off:** `wm.config { floating = { remember_position = false } }`. The places are in `float-memory.json` next to `memory.json`
  (the last 200 are kept); delete the file to forget them all.
