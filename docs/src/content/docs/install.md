---
title: "Install"
description: "Build wm from source, grant the permissions, sign it, put it on your PATH and start it."
group: Start
order: 2
---
## Requirements

- macOS 14 or later.
- The Swift 6.2 toolchain (Xcode or the command line tools).
- Quit any other window manager first (AeroSpace, yabai, Amethyst). Two of them fight over the same windows.

I have not published a binary. You build wm from source.

## Build

```sh
git clone https://github.com/g4rcez/wm.git wm
cd wm
./build-app.sh                       # builds .build/wm.app (daemon and CLI), signs it, and starts it
```

`./build-app.sh debug` makes a debug build. `NO_START=1 ./build-app.sh` builds without starting the daemon. If wm is
already running, the script stops it before it replaces the bundle.

A `Makefile` wraps the common tasks. `make` lists them:

```sh
make deps                                  # checks the Swift toolchain; installs librsvg and imagemagick (only for the icon) if missing
make build                                 # compiles only: it does not touch the app that runs (CONFIG=debug for a debug build)
make test                                  # runs the unit tests, with a 300 second timeout when timeout or gtimeout exists
make identities                            # lists your code-signing certificates
make install CODESIGN_IDENTITY="<name>"    # build, sign, copy to /Applications/wm.app, link wm in ~/.local/bin, start it
```

`make install` stops when there is no certificate (it uses `CODESIGN_IDENTITY`, else the first "Apple Development" one), so
it never installs an ad hoc build that loses the permissions at every rebuild. `APP_DIR` and `BIN_DIR` change where it
installs. It stops the running wm, replaces `wm.app` and starts the new one.

## First run

The first time that wm starts, it opens a **setup window**, and it moves no window until you press **Start managing
windows**. The window shows the Accessibility and Screen Recording permissions (it checks them each second, so you can grant
them in System Settings and come back), and, when you have no config, offers a starter: pick a preset and a modifier key, and
**Write config** saves `~/.config/wm/init.lua`. Start is enabled when Accessibility is granted.

Every user sees the window once, an upgrade included. Pressing Start writes the file `~/.local/state/wm/onboarded`
(`$XDG_STATE_HOME/wm/onboarded` when that variable is set). Delete the file to see the window again, or choose **Setup…** in
the menu bar menu to look at it without the gate. `wm doctor` shows `setup` as not finished until you press Start.

## Permissions

macOS asks for **Accessibility** when you press Grant in the setup window. Grant it in System Settings > Privacy & Security >
Accessibility. wm cannot move windows without it.

**Screen Recording** is optional. wm uses it for the window pictures in the Alt+Tab switcher and in the overview. Without
it those tiles show the app icon and the title. `wm select` uses it to read the windows that draw their own text.

**Automation** is optional. The palette uses it to read and select the tabs of browsers (and to bring Rex to the front), so
macOS asks once for each of those apps, the first time the palette opens while the app runs. Without it the palette lists no
tabs of that app. Change it in System Settings > Privacy & Security > Automation > `wm`.

The menu bar icon needs one more switch: System Settings > Menu Bar > "Allow in the Menu Bar" > `wm`.

## Signing

macOS keeps the Accessibility and Screen Recording grants of an app by its signature. An ad-hoc signature changes with
every build, so you would grant the permissions again after each rebuild. `build-app.sh` avoids that:

1. It signs with `CODESIGN_IDENTITY` (a certificate name or SHA-1 hash) when you set it.
2. Otherwise it uses the first "Apple Development" certificate in your keychain.
3. Otherwise it signs ad hoc and prints a warning.

Nothing about the certificate is written into the repository. The first build with a certificate makes macOS ask whether
`codesign` may use the key: choose **Always Allow**. Switching from ad hoc to a certificate changes the signature once, so
grant the permissions one more time. After that, rebuilds keep them. `codesign -dr - .build/wm.app` shows
`identifier "local.wm" and ... certificate leaf ...` and no `cdhash` when the signature is stable.

## Put `wm` on your PATH

The CLI lives inside the bundle. Link it somewhere on your PATH:

```sh
mkdir -p ~/.local/bin
ln -s "$PWD/.build/wm.app/Contents/MacOS/wm" ~/.local/bin/wm
```

`wm daemon start` finds the app that its own `wm` belongs to, also through this symlink. If it cannot, it tries
`/Applications/wm.app` and then `~/Applications/wm.app`.

## Editor autocomplete

Run `wm lsp --write` once to get completion for `init.lua` in your editor. See [Editor support](/docs/lua-api#editor-support).

## Shell completion

`wm completion zsh` and `wm completion bash` print a small script that asks `wm` for the candidates each time you press
Tab, so it never goes out of date. It completes the commands, their arguments and their options. While the daemon runs
it also completes window ids (with the app and title), `--window` selectors (`app:<name>`), workspace names, special
workspaces and modes. Without the daemon the fixed words still complete. Load it when the shell starts:

```sh
eval "$(wm completion zsh)"   # in ~/.zshrc, after compinit
eval "$(wm completion bash)"  # in ~/.bashrc
```

## Start at login

Copy `wm.app` to `/Applications` and set `start_at_login = true` in the config. The app has to stay in a fixed place for
this to work.

## Run it

```sh
wm daemon start    # starts wm.app in the background and returns when the daemon answers
wm daemon status   # whether it runs, the workspace, the mode, the window count
wm daemon stop     # quits wm; hidden windows come back on screen
wmd --background   # from a terminal: a detached daemon that survives closing the terminal
```

While the daemon runs, a rounded square with the workspace name is in the menu bar. Its menu has reload, the tile
pictures, and quit.
