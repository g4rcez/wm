---
title: "Lua API"
description: "wm.config, wm.bind, wm.on, wm.dispatch, wm.query and the rest, with editor support."
group: Reference
order: 2
---
`wm.config`, `wm.bind`, `wm.remap`, `wm.shortcuts`, `wm.mode`, `wm.gesture`, `wm.rule`, `wm.workspace`, `wm.profile`, `wm.on`, `wm.dispatch`, `wm.query`,
`wm.exec`, `wm.press`, `wm.log` and `wm.version`.

- `wm.dispatch(command [, { window = id or selector }])` runs a command. It returns stdout, or `nil, stderr` when the
  command failed.
- `wm.query(kind)` returns a Lua table. The kinds are `windows`, `focused`, `workspaces`, `monitors` and `monitor` (the
  focused monitor). A monitor has `id`, `name`, `index` (1 is the leftmost), `role` (`main`, `secondary`, `tertiary`),
  `main`, `workspace`, `special`, `focused`, `frame` and `work_area`. `wm list monitors` shows the same, and
  `wm list monitors --focused` only the monitor that has the focus (add `--json` for scripts). The `monitor_changed` event has
  the `monitor` id, its `name` and its `workspace`, so a config can react to the monitor in use:

  ```lua
  wm.on("monitor_changed", function(e)
    if e.name:find("LG") then wm.dispatch("layout set scrolling") else wm.dispatch("layout set tiling") end
  end)
  local here = wm.query("monitor")   -- the focused monitor: here.name, here.index, here.role
  ```
- Events: `window_open`, `window_close`, `window_focus`, `window_title`, `window_floating`, `window_fullscreen`,
  `window_moved`, `workspace_changed`, `special_changed`, `monitor_changed`, `displays_changed`, `layout_changed`, `mode_changed` and
  `config_reloaded`. `wm.on(event, [filter,] handler)` takes an optional table of fields that must match.
- `wm.exec(command [, options])` runs a shell command and returns nothing. It does not wait for the command and it drops its output.
  wm runs it as `/bin/zsh -c "<command>"`, which does not read `.zshrc`: use absolute paths (`/opt/homebrew/bin/htop`).
  `$HOME` and `$(...)` work. A folder such as `/Applications/Foo.app` is not a command: use `open -a Foo`, or the program
  inside it (`/Applications/Foo.app/Contents/MacOS/foo`). A command that cannot start is in `wm logs` (source `exec`).

  ```lua
  wm.bind("alt-t", function() wm.exec("open -a Terminal") end)
  wm.bind("alt-shift-t", "exec open -a Terminal")      -- the same, as a command string
  ```

  `options` make a one-shot rule for the window that the command opens: `float`, `workspace`, `layout`, `size`, `center`,
  `maximize`, `width`, `monitor`, `focus` and `run`, as in [`wm.rule`](/docs/rules). Two more keys say how to find the window:
  `timeout` (seconds to wait, 1 to 600, default 15) and `app` (a bundle id or name). A window is found by process first, so the
  options reach a program that the command starts itself. For `open -a Notes`, or an app that gives the work to a copy that
  already runs, add `app`: the first new window of that app within the timeout takes the options.

  ```lua
  wm.bind("alt-n", function()
    wm.exec("open -a Notes", { app = "Notes", float = true, center = true, size = { 0.5, 0.6 } })
  end)
  ```

  An option that does not exist, or `timeout` or `app` without an action, is an error in the log. Options that nothing used
  expire after the timeout and `wm logs` says so (source `exec`, at debug level).

  To give the new window options (a workspace, a size, floating), use the `exec` command of wm through `wm.dispatch`.
  The options are `--float`, `--tile`, `--center`, `--maximize`, `--no-focus`, `--workspace <n>`, `--monitor <m>`,
  `--width <fraction>`, `--size <w>,<h>` and `--layout <name>`, and they go before `--`. They add to the `wm.rule` rules.

  ```lua
  wm.dispatch("exec --float --center --size 0.5,0.5 -- /Applications/kitty.app/Contents/MacOS/kitty -e htop")
  ```
- `wm.shortcuts()` binds the `[[shortcut]]` entries of `shortcuts.toml`, the file that the Shortcuts window writes. See
  [shortcuts.toml](/docs/config#shortcutstoml). A `wm.bind` for the same keys after the call replaces the shortcut.
- `wm.press(key)` types a key now (`"play"`, `"cmd-shift-4"`), and `wm.remap(chord, key)` makes a chord type another key. See
  [The hyper key, remaps and typing keys](/docs/keys#the-hyper-key-remaps-and-typing-keys).
- `wm.config`, `wm.bind`, `wm.remap`, `wm.shortcuts`, `wm.mode`, `wm.gesture`, `wm.rule`, `wm.workspace` and `wm.profile` work only while the config file
  loads (not inside a bind or an event handler). `wm.dispatch`, `wm.exec`, `wm.press`, `wm.query`, `wm.log` and `wm.on` work
  everywhere. A function bind or handler runs on its own thread, so a slow one never blocks the keyboard; one that runs
  longer than 2 seconds is stopped. `wm.log` writes to `wm logs`, a script that fails too (source `lua`).
- The config folder is on Lua's `package.path`, so a long config can be split in files: `require("hyper")` loads
  `hyper.lua` that sits next to `init.lua`. A change to `init.lua` reloads the config; after a change in a module, run
  `wm daemon reload`.

## Editor support

`init.lua` gets completion, hover help and warnings in any editor that runs
[lua-language-server](https://luals.github.io/) (LuaLS): VS Code with the Lua extension, Neovim with `lua_ls`, Helix, Zed
and others. The server reads the type stubs in `types/wm.lua`. They describe the whole API: config keys with defaults and
ranges, enum values, command strings, bind options, rule fields, event fields and the tables that `wm.query` returns.
wm never loads this file. It exists for the editor.

`build-app.sh` puts the stubs inside the app, so you do not need this repository to use them. One command sets
everything up:

```sh
wm lsp            # shows the folder of the stubs and the .luarc.json that LuaLS needs
wm lsp --write    # saves it next to your config, as ~/.config/wm/.luarc.json
```

`--write` stops if a `.luarc.json` is already there. Use `--force` to replace it, or add the printed folder to the
`workspace.library` list of your file by hand. This is what the file looks like:

```json
{
  "diagnostics.neededFileStatus": { "missing-fields": "Any", "undefined-field": "Any" },
  "runtime.version": "Lua 5.4",
  "workspace.library": ["/Applications/wm.app/Contents/Resources/types"]
}
```

Open `init.lua` and the editor does the rest. LuaLS finds the file because it sits in the folder of `init.lua`. If you
move `wm.app`, run `wm lsp --write --force` again, because the path of the stubs changes. If you work on wm itself, you
can point `workspace.library` at the `types` folder of the repository instead.

`wm lsp --write` also writes a `.taplo.toml` next to your config. It points [Taplo](https://taplo.tamasfe.dev/) (the
TOML server of the "Even Better TOML" extension) at `types/shortcuts.schema.json`, so `shortcuts.toml` gets completion, hover
help and a warning for an unknown key, for a missing `keys`, and for a shortcut that has both `action` and `remap` (or
neither). If a `.taplo.toml` is already there, the command prints the rule to add instead of replacing the file, unless you use
`--force`. `--force` replaces both `.luarc.json` and `.taplo.toml`. See [shortcuts.toml](/docs/config#shortcutstoml).

`wm.shortcuts()` has a stub too, so LuaLS completes it and shows its help.

Some examples of what you get: completion for `wm.config { ... }` keys and values (`layout = "` offers `scrolling` and
`tiling`), the command strings of `wm.bind`, the fields of `wm.rule`, the event names of `wm.on` with the fields of each
event, and a warning for a wrong value (`layout = "grid"`) or a wrong event name. LuaLS does not warn about an unknown key
inside a table (`gaps = { outr = 1 }`). wm still rejects it when the config loads.

A test keeps the stubs in step with the API: it fails when a `wm` function or a top-level config key has no stub.
