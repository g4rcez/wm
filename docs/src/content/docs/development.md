---
title: "Development"
description: "Build, test and work on wm itself."
group: Guides
order: 4
---
```sh
timeout 300 swift test      # unit tests: layout engines, geometry, Lua host, IPC, command parsing
./build-app.sh debug        # a debug build of the app bundle
```

The app icon is `assets/icon-windows.svg`. `bundle/wm.icns` is made from it by `assets/make-icns.sh` (it needs `rsvg-convert`,
`magick` and `iconutil`), and `build-app.sh` copies it into the app. Run the script again when the SVG changes.

| Target | Role |
|---|---|
| `CLua` | Vendored Lua 5.4.7 |
| `Common` | IPC (length-prefixed JSON over a unix socket), command table, help, URL parsing and shell completion |
| `Core` | Pure layout engines, animator, gaps, navigation, the geometry of the overview. No AppKit. |
| `Scripting` | Lua host, chords, binds, gestures, config validation |
| `Platform` | Accessibility threads, displays, event tap, overlays, SkyLight reader |
| `App` | `wmd`: window manager state, commands, config, menu bar, URL handler |
| `Cli` | `wm` |

The engines are plain values with no AppKit in them, so most behavior has a test with literal frames. The parts that need a
real screen (overlays, the event tap, window moves) I checked by running the daemon.
