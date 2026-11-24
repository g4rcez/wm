---
title: "Command line"
description: "The wm CLI: commands, output, choosing a window, scripting, logs and wm:// URLs."
group: Reference
order: 1
---
- `wm help` lists every command, with examples, global options, exit codes and environment variables. `wm help <command>` shows one command with its options and an example; `wm help window` lists a group.
- The same words work in `wm.bind`, in Lua (`wm.dispatch`) and in `wm://` URLs.

```
FOCUS AND MOVE   focus <dir> | focus back | focus next|prev | focus window <id> | focus monitor <monitor> | focus layer
                 focus app <name> [--launch] | focus urgent | focus urgent-or-last
                 focus column <first|last|n> | focus stack <first|last|n>
                 move <dir> [points] [--wrap] | swap <dir> [--wrap] | resize <width|height|smart|left|right|up|down> <+n|-n>
                 resize dir <left|right|up|down> <n>
WINDOWS          window close | float [on|off] | center | fullscreen | native-fullscreen | maximize | pseudo | raise-floating | rescue
                 window snap <left|right|top|bottom|top-left|top-right|bottom-left|bottom-right|top-center|bottom-center|center> | sticky
                 window place <pattern> <n> | move-to <x> <y>
                 window minimize | swipe <left|right|up|down>
                 window mark <name> | unmark [name] | remember [--title] | forget [--title]
                 window send workspace <name> | monitor <monitor> | strip <horizontal|vertical>
WORKSPACES       workspace <name|back|next|prev|empty> | workspace special [name]
                 workspace move monitor <monitor> | workspace float-all [off|pattern]
                 workspace all <layout>
                 workspaces balance [count]
LAYOUT           layout set <scrolling|tiling|master|monocle|floating> | balance | rotate | flip | tile | preselect <dir>
                 layout split <toggle|swap|root|ratio> | column <width|match|expand|center|center-visible>
                 layout stack <join|leave|tabs|equalize|height> | column move <first|last|n>
                 layout master <promote|count|ratio|orientation>
INTERFACE        switcher | overview | palette | cheatsheet [tui|gui|cli] | menu | mode <name|back> | pointer <window|monitor> | zen [on|off]
                 hints [all|window] [open|close|toggle] [--wait] | scroll [open|close|toggle] | select [open|close|toggle] | jump [open|close|toggle] [--swap] [--close]
                 exec [options] <command> | batch <commands> | set <key> <value> | animations [on|off] [kind] [--json] | menubar set <text> | menubar reset | notify <text> | key send <chord> | key press <chord>
INSPECT          doctor [--json] | pick [--json] | list [windows|workspaces|monitors|keyboards|memory|binds] | query [what] | subscribe [--snapshot] [event ...] | logs [-n count] [-f] [-o otel|json]
MEMORY           memory list | forget <app> [--title=<text>] [--all] | clear
DAEMON           daemon start | stop | status | reload | version
EDITOR           lsp [--write] [--force]
CONFIG           init [template] [--mod=<alt|cmd|ctrl|hyper>] [--lua] [--force]
                 config check [path]
SHELL            completion <zsh|bash>
AGENTS           skills
```

Options for every command:

| Option | Effect |
|---|---|
| `--window <w>` | acts on that window (see [Choosing a window](#choosing-a-window)) |
| `--json` | prints JSON (`list`, `memory list`, `daemon status`, `animations`, `doctor`, `pick`) |
| `-v`, `--verbose` | prints the state after the command |
| `-h`, `--help` | shows help |

- `wm doctor` checks the config, `shortcuts.toml`, the daemon, Accessibility, the key tap and Screen Recording. It prints a hint for each check that is not ok and exits with 1 when one failed.
- `wm config check [path]` loads a config file in a new Lua state without applying it. It prints the first error with its line, and a `warn:` line for each bind that `init.lua` and `shortcuts.toml` both make. Inside it, `wm.exec` and `wm.dispatch` do nothing and `wm.query` finds nothing.
- `wm skills` prints a `SKILL.md` that teaches an AI agent to use wm, built from the same table as `wm help`: `mkdir -p ~/.claude/skills/wm && wm skills > ~/.claude/skills/wm/SKILL.md`.
- `wm daemon reload` loads the config again. When the running wm is another build than this `wm` (after `brew upgrade wm`), it stops it and starts the new one instead, then prints `wm restarted: <old> -> <new>`. The release is signed with the same certificate, so the permissions stay. `wm daemon start` on a stale wm says so and points to `reload`.
- `doctor`, `config check`, `lsp`, `init`, `skills` and `completion` need no daemon.

## Output

- A command that works prints nothing. Errors go to stderr with up to three lines: what went wrong, a `usage:` line and a `hint:`.
- Exit code 2: the command was used wrongly. Exit code 1: it could not run now (`wm daemon status || wm daemon start`).
- Commands that take `on` and `off` (`window float on`, `zen off`) set a state, so running them again changes nothing.
- Colors appear only on a terminal. `NO_COLOR` or `TERM=dumb` turns them off; `CLICOLOR_FORCE=1` turns them on in a pipe.

`wm subscribe` prints one JSON event per line until you stop it:

```sh
wm subscribe                                          # every event
wm subscribe --snapshot window_focus workspace_changed # the first line is the state of wm now
wm subscribe | jq -c 'select(.event == "window_focus") | .app'
```

Every line has an `event` field plus the fields that `wm.on` handlers get. With `--snapshot`, the first line is `{"event":"snapshot","mode":"main","state":<wm list --json>}`. An unknown event name is an error that lists the names.

**The socket.** `wm` is a client of a unix socket (mode 0600) named `wm.sock` in the temporary folder of your user (`getconf DARWIN_USER_TEMP_DIR`; `/tmp/wm.sock` when that fails). A message is a 4-byte big-endian length, then that many bytes of JSON. The request is `{"args":["focus","left"],"windowId":null,"windowSelector":null}` and the answer `{"exitCode":0,"stdout":"","stderr":""}`. After a `subscribe` request the connection stays open and the daemon writes one frame per event.

## Logs

The daemon writes `$XDG_STATE_HOME/wm/wm.log` (`~/.local/state/wm/wm.log` by default), one JSON record per line, and its stderr. `WM_LOG_LEVEL` (`debug`, `info`, `warn`, `error`) sets the lowest level that goes to the file; the default is `debug`. At 5 MB the file becomes `wm.log.1`.

`wm logs` reads the file, so it works when the daemon is stopped.

| Option | Effect |
|---|---|
| `-n`, `--lines <count>` | the last records (default 100; `0` shows all) |
| `-f`, `--follow` | wait for new records |
| `-o`, `--output otel\|json` | text in the OpenTelemetry log model (default), or one JSON object per line (`time`, `level`, `message`, `source`) |

`source` is `lua`, `config`, `exec`, `url`, `state`, `memory`, `login`, `daemon` or `window`. A `window` record says what wm did with a window that opened: workspace, floating or tiled, and which rule matched.

## Choosing a window

`--window` takes a window id or a selector:

| Selector | The window |
|---|---|
| `focused` | the focused one |
| `app:<name>` | of that app: bundle id or app name, case does not matter |
| `title:<regex>` | whose title matches the regular expression |
| `mark:<name>` | that has this mark (`window mark`) |
| `pid:<n>` | of that process |

With several matches the focused window wins, then the most recently used one on the focused workspace, then the lowest id. No match is an error. In Lua: `wm.dispatch("window close", { window = "app:Notes" })`.

## Scripting

- `wm batch 'workspace 2; layout set tiling'` runs commands in order and stops at the first error.
- `wm set gaps.inner 4` changes one config value until the next reload; lists are comma-separated (`wm set scrolling.presets 0.3,0.5,1`). `workspaces` and `url` only change in the config file.
- `wm key send cmd-shift-r --window app:OBS` types a key into an app in the background. Bind a chord to it for a global hotkey for that app.
- `wm exec --float --center --size 0.5,0.5 -- /path/to/program` makes a rule for the window the program opens. Options: `--float`, `--tile`, `--center`, `--maximize`, `--focus`, `--no-focus`, `--workspace`, `--monitor`, `--width`, `--size`, `--layout`. For `open -a Notes`, or an app that hands the work to a copy that already runs, add `--app Notes`. The options apply to the first window that opens within 15 seconds, or `--timeout <seconds>` (1 to 600). In Lua: `wm.exec(command, { float = true, app = "Notes" })`.

## URL scheme

Format: `wm://<command>/<arg>...` or `wm://<command>?args=<url-encoded arguments>`.

```sh
open "wm://workspace/2"
open "wm://window/send/workspace/3?args=--stay"
open "wm://window/close?window=app:Safari"
```

Any app or web page can open a `wm://` URL, so a URL may only run commands that act on wm itself.

- `exec`, `key`, `daemon` and `subscribe` are blocked, also inside a `batch`. To allow one on purpose: `url = { allow = { "exec" } }`.
- `?window=` takes an id, `focused`, `app:`, `mark:` or `pid:`. It does not take `title:`: that selector is a regular expression that runs on the main thread. Use `wm --window title:<regex>` on the command line.
