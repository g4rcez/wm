---
title: "Command line"
description: "The wm CLI: commands, output, logs, choosing a window and scripting."
group: Reference
order: 1
---
`wm help` lists every command, with examples, the global options, the URL scheme, the exit codes and the environment
variables. `wm help <command>` is the page of one command: usage, what it does, an `Options` table that explains each
option, and an example. `wm help window` lists the commands of a group. The same words work in `wm.bind`, in Lua
(`wm.dispatch`) and in `wm://` URLs.

```
FOCUS AND MOVE   focus <dir> | focus back | focus next|prev | focus window <id> | focus monitor <monitor> | focus layer
                 focus app <name> [--launch]
                 focus column <first|last|n> | focus stack <first|last|n>
                 move <dir> [points] | swap <dir> | resize <width|height|smart> <+n|-n>
WINDOWS          window close | float [on|off] | center | fullscreen | native-fullscreen | maximize | pseudo | raise-floating | rescue
                 window snap <left|right|top|bottom|top-left|top-right|bottom-left|bottom-right|center> | sticky
                 window mark <name> | unmark [name] | remember [--title] | forget [--title]
                 window send workspace <name> | monitor <monitor> | strip <horizontal|vertical>
WORKSPACES       workspace <name|back|next|prev|empty> | workspace special [name]
                 workspace move monitor <monitor>
LAYOUT           layout set <scrolling|tiling> | balance | rotate | flip | tile | preselect <dir>
                 layout split <toggle|swap|root|ratio> | column <width|match|expand|center|center-visible>
                 layout stack <join|leave|tabs|equalize|height> | column move <first|last|n>
INTERFACE        switcher | overview | palette | menu | mode <name|back> | pointer <window|monitor> | zen [on|off]
                 exec [options] <command> | batch <commands> | set <key> <value> | notify <text> | key send <chord> | key press <chord>
INSPECT          list [windows|workspaces|monitors|keyboards|memory|binds] | query [what] | subscribe [--snapshot] [event ...] | logs [-n count] [-f] [-o otel|json]
DAEMON           daemon start | stop | status | reload | version
EDITOR           lsp [--write] [--force]
SHELL            completion <zsh|bash>
```

Options for every command: `--window <w>` acts on that window, `--json` prints JSON (`list`, `daemon status`),
`-v` or `--verbose` prints the state after the command, and `-h` or `--help` shows help.

## Output

A command that works prints nothing. Errors go to stderr with a non-zero exit code, in up to three lines: what went wrong,
the `usage:` line, and a `hint:`. Exit code 2 means the command was used wrongly, and 1 means it could not run, so a
script can tell "wrong" from "not now" (`wm daemon status || wm daemon start`). The commands that take `on` and `off`
(`window float on`, `zen off`) set a state, so running them again changes nothing.

Colors in `wm help` and in errors appear only on a terminal. `NO_COLOR` turns them off, `TERM=dumb` too, and
`CLICOLOR_FORCE=1` turns them on in a pipe (`wm help | less -R`). The text of a pipe or a file never has colors.

```
$ wm layout stak
wm: error: unknown layout command 'stak'
usage: wm layout set <scrolling|tiling>
       wm layout balance
       ...

$ wm list windows
   ID    APP         TITLE                     WORKSPACE  STATE
*  204   Terminal    1: zsh                    2          maximized
   7653  Notes                                 2          floating
```

`wm daemon status` exits with 1 when wm does not run, so a script can test it. `wm subscribe` prints one JSON event per
line until you stop it:

```sh
wm subscribe                                          # every event
wm subscribe window_focus workspace_changed           # only these events
wm subscribe --snapshot window_focus                  # the first line is the state of wm now
wm subscribe | jq -c 'select(.event == "window_focus") | .app'
```

Every line has an `event` field with the name, and the fields of the event (the same ones that `wm.on` handlers get). With
`--snapshot` the first line is `{"event":"snapshot","mode":"main","state":<wm list --json>}`, so a status bar can draw
itself and then follow the changes. An event name that wm does not know is an error, with the list of names.

**The socket.** `wm` is a client of a unix socket (mode 0600) named `wm.sock` in the temporary folder of your user
(`getconf DARWIN_USER_TEMP_DIR`; `/tmp/wm.sock` when that fails). One exchange is one request and one answer. Each message is a 4-byte big-endian length and then that many bytes of
JSON. The request is `{"args":["focus","left"],"windowId":null,"windowSelector":null}` (the words of the command, as the
CLI gets them) and the answer is `{"exitCode":0,"stdout":"","stderr":""}`. A `subscribe` request gets its answer, and the
connection stays open: the daemon then writes one frame for each event (and the snapshot first), until you close it.

## Logs

The daemon writes its log to `$XDG_STATE_HOME/wm/wm.log` (`~/.local/state/wm/wm.log` by default), one JSON record per
line, and to its stderr as before. At 5 MB the file becomes `wm.log.1`, so the log takes about 10 MB at most. `wm logs`
reads the file, so it works when the daemon is stopped or has crashed.

```
$ wm logs -n 2
2026-11-16T22:57:03.123Z INFO  config loaded: /Users/me/.config/wm/init.lua source=config
2026-11-16T22:57:09.870Z ERROR config error: ... source=config

$ wm logs -f -o json
{"time":"2026-11-16T22:58:00.000Z","level":"warn","message":"blocked wm:// command 'exec'; ...","source":"url"}
```

- The default output is text in the OpenTelemetry log data model: the time (UTC), the severity (`DEBUG`, `INFO`, `WARN`,
  `ERROR`), the message, then the attributes (`source=`). A new line in a message is written `\n`, so a record is one line.
- `-o json` (`--output json`) prints one flat JSON object per line: `time`, `level`, `message` and `source`. Use it with `jq`.
- `-n count` (`--lines`) shows the last records, 100 by default; `-n 0` shows all of them. `-f` (`--follow`) waits for new
  records until you stop it.
- `source` is `lua` for `wm.log` and for scripts that fail, `config`, `exec`, `url`, `state`, `memory`, `login`, `daemon` or `window`.
  A `window` record (level `debug`) says what wm did with a window that opened: its app id, title, workspace, whether it floats,
  and which rule matched. `wm logs -f` shows why a window was tiled or floated.

## Choosing a window

`--window` takes a window id or a selector:

| Selector | The window |
|---|---|
| `focused` | the focused one |
| `app:<name>` | of that app: bundle id or app name, exact, case does not matter |
| `title:<regex>` | whose title matches the regular expression |
| `mark:<name>` | that has this mark (see `window mark`) |
| `pid:<n>` | of that process |

With several matches, the focused window wins if it is one. Then the most recently used one on the focused workspace
wins, then the lowest id. No match is an error. The flag goes before or after the command. In Lua, use
`wm.dispatch("window close", { window = "app:Notes" })`. In a URL, use `?window=app:Notes`.

## Scripting

- `wm batch 'workspace 2; layout set tiling'` runs commands in order and stops at the first error.
- `wm set gaps.inner 4` changes one config value until the next reload. Lists are comma-separated:
  `wm set scrolling.presets 0.3,0.5,1`. `workspaces` and `url` only change in the config file.
- `wm key send cmd-shift-r --window app:OBS` types a key into an app that is in the background. Bind a chord of yours to
  it and you have a global hotkey for that app.
- `wm exec --float --center --size 0.5,0.5 -- /path/to/program` makes a rule for the window that the program opens. The
  options are `--float`, `--tile`, `--center`, `--maximize`, `--no-focus`, `--workspace`, `--monitor`, `--width`, `--size`
  and `--layout`. wm finds the window by process, so give the program itself and not `open -a`. The options apply to
  the first window that opens within 15 seconds.
- `wm workspace next|prev|empty` moves through the workspaces in use (wrapping around) or to the lowest free number.
