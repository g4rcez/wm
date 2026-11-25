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

Releases are made on the Mac that holds the release certificate, not in CI. `scripts/release.sh patch|minor|major|X.Y.Z`:

1. checks that `main` is clean and in sync, that the certificate is in your keychain and that `gh` is logged in;
2. runs the tests and bumps `Version.swift`;
3. builds a universal `wm.app` with `build-app.sh` and signs it with the release certificate, without the debug symbols (they name your folders);
4. checks the signature, then commits, tags, pushes and creates the GitHub release with `wm-<version>-macos.tar.gz` (and its
   `.sha256`);
5. writes `Formula/wm.rb` of `g4rcez/homebrew-tap` from `scripts/wm.rb.in`. Change the formula there, not in the tap.

`--dry-run` stops after the checks of step 1.

macOS keeps the Accessibility and Screen Recording grants of an app by its designated requirement, which names the bundle id and
the certificate. With one certificate it is the same for every release: users grant the permissions once, and `brew upgrade wm`
plus `wm daemon reload` is all an update needs. `scripts/signing-cert.sha1` pins the certificate, and the release stops when the
build has another signature.

`scripts/make-signing-cert.sh` makes the certificate once. It imports it into your login keychain and keeps a backup (`.p12` and
password) in `~/Library/Application Support/wm-signing`. Copy that folder somewhere safe. To release from another Mac, import the
backup there:

```sh
security import wm-signing.p12 -P "$(cat password.txt)" -T /usr/bin/codesign
```

A new certificate makes every user grant the permissions again.

The engines are plain values with no AppKit, so most behavior has a test with literal frames. The parts that need a real
screen (overlays, the event tap, window moves) were checked by running the daemon.
