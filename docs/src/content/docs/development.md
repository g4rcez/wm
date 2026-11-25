---
title: "Development"
description: "Build, test and work on wm itself."
group: Guides
order: 2
---
```sh
timeout 300 swift test      # unit tests: layout engines, geometry, Lua host, IPC, command parsing
./build-app.sh debug        # a debug build of the app bundle
```

The app icon is `assets/icon-windows.svg`. `assets/make-icns.sh` makes `bundle/wm.icns` from it. It needs `rsvg-convert`,
`magick` and `iconutil`. `build-app.sh` copies the icns into the app. Run the script again when the SVG changes.

A compiler warning is an error in every target, the tests too (`treatAllWarnings` in `Package.swift`). Only the vendored Lua is
left out. A newer Swift or Xcode can add warnings: fix them, so that CI and a build from source keep passing.

| Target | Role |
|---|---|
| `CLua` | Vendored Lua 5.4.9 |
| `Common` | IPC (length-prefixed JSON over a unix socket), command table, help, URL parsing and shell completion |
| `Core` | Pure layout engines, animator, gaps, navigation, the geometry of the overview. No AppKit. |
| `Scripting` | Lua host, chords, binds, gestures, config validation |
| `Platform` | Accessibility threads, displays, event tap, overlays, SkyLight reader |
| `App` | `wmd`: window manager state, commands, config, menu bar, URL handler |
| `Cli` | `wm` |

## Releases and signing

`scripts/release.sh patch|minor|major|X.Y.Z` tests, bumps `Version.swift`, tags, pushes, then waits for the release workflow
and points `Formula/wm.rb` of `g4rcez/homebrew-tap` at the asset it attached.

The workflow (`.github/workflows/release.yml`) builds a universal `wm.app` with `build-app.sh`, signs it with the project
certificate and attaches `wm-<version>-macos.tar.gz` (and its `.sha256`) to the GitHub release. It fails when the signature
is ad hoc (`cdhash` in the designated requirement). macOS keeps the Accessibility and Screen Recording grants by that
requirement, which with one certificate is the same for every release: users grant the permissions once, and `brew upgrade wm`
plus `wm daemon reload` is all an update needs.

The certificate is made once by `scripts/make-signing-cert.sh`. It prints the two repository secrets, `WM_SIGNING_P12` and
`WM_SIGNING_P12_PASSWORD`. Back the `.p12` up: a new certificate makes every user grant the permissions again.

The engines are plain values with no AppKit, so most behavior has a test with literal frames. The parts that need a real
screen (overlays, the event tap, window moves) were checked by running the daemon.
