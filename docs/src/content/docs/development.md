---
title: "Development"
description: "Build, test and work on wm itself."
group: Guides
order: 2
---
```sh
timeout 600 swift test      # unit tests: layout engines, geometry, Lua host, IPC, command parsing
./build-app.sh debug        # a debug build of the app bundle
```

`make` lists the same tasks: `make deps` checks the toolchain, `make test` runs the tests with a timeout, `make version-check`
checks that `Version.swift` is the latest tag, and `make install` builds, signs and installs the app. CI runs the tests, the
version check and a release build on every push.

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
| `PrivateApi` | C bindings to private macOS functions (SkyLight, MultitouchSupport), loaded at run time |
| `Cheatsheet` | The key sheet of `wm cheatsheet`, for the terminal and the panel |
| `App` | `wmd`: window manager state, commands, config, menu bar, URL handler |
| `Cli` | `wm` |

## Releases and signing

Releases are made on the Mac that holds the Developer ID certificate, not in CI. `scripts/release.sh patch|minor|major|X.Y.Z`:

1. checks that `main` is clean and in sync, that the certificate and the notarization credentials work, that `gh` is logged in,
   and that `CHANGELOG.md` has an entry under `## Unreleased` (`scripts/changelog.sh check`);
2. runs the tests and bumps `Version.swift`;
3. builds a universal `wm.app` with `build-app.sh` and signs it with the Developer ID certificate, the hardened runtime and a
   secure timestamp, without the debug symbols (they name your folders);
4. checks the signature, sends the app to Apple to be notarized and staples the ticket to it. It waits up to 2 hours for
   Apple (`NOTARY_TIMEOUT=4h` waits longer); without an answer, nothing is published;
5. packs the app and runs `scripts/verify-release.sh` on the archive, before anything is published;
6. renames `## Unreleased` to the version, commits, tags, pushes and creates the GitHub release with `wm-<version>-macos.tar.gz`
   (and its `.sha256`); the notes are the changelog section, followed by the generated list of commits;
7. downloads the asset again, and only when it is the verified file writes `Formula/wm.rb` of `g4rcez/homebrew-tap` from
   `scripts/wm.rb.in`. Change the formula there, not in the tap.

`--dry-run` stops after the checks of step 1.

### What a release asserts

`scripts/verify-release.sh <archive>` fails, and so does the release, unless:

- `wm.app` has exactly the designated requirement of `scripts/designated-requirement`;
- the signature is intact, Gatekeeper sees a notarized Developer ID app and the ticket is stapled;
- the owners in the archive are `root:wheel`, and it contains no home folder, user name or computer name of the release Mac.

`brew test wm` checks the installed app: the signature is intact, it is of the pinned team and the notarization ticket is
there. Gatekeeper does not run in the sandbox of the test. To ask it, run
`spctl --assess --type execute --verbose "$(brew --prefix)/opt/wm/wm.app"`.

A Developer ID signature is public: every copy of the app carries the name on the certificate (for an individual membership,
your legal name), the country and the Team ID.

### Set up a release Mac

You need a paid Apple Developer Program membership. Do these once.

1. Make a **Developer ID Application** certificate (only the Account Holder can): Xcode > Settings > Accounts, select the team,
   Manage Certificates, `+`, Developer ID Application. `make identities` must then list it. An "Apple Development" certificate
   does not work for a release.
2. Write the Team ID, the 10 characters in parentheses at the end of the certificate name, to `scripts/signing-team-id`, and
   commit the file.
3. Make an app-specific password at [account.apple.com](https://account.apple.com) (Sign-In and Security), then save the
   notarization credentials in your keychain. The command asks for the password:

   ```sh
   xcrun notarytool store-credentials wm-notary --apple-id "<your Apple ID>" --team-id "<Team ID>"
   ```

To release from another Mac, export the certificate with its private key from Keychain Access (a `.p12`), import it there, and
run step 3 again. Keep that `.p12` and its password somewhere safe, and never commit them.

### Permissions across releases

macOS keeps the Accessibility and Screen Recording grants of an app by its designated requirement. For a Developer ID signature it
names the bundle id and the Team ID. It is the same for every release, also after the certificate is renewed: users grant the
permissions once, and `brew upgrade wm` plus `wm daemon reload` is all an update needs. `scripts/signing-team-id` picks the
certificate, `scripts/designated-requirement` pins the requirement, and the release stops when the app has another one. A new
team or bundle id makes every user grant the permissions again: change the pin only when you mean that.

### Signing of local builds

`scripts/signing-identity.sh` picks the certificate for `build-app.sh`, `make install`, `scripts/make-dmg.sh` and the release:

1. the Developer ID Application certificate of the team in `scripts/signing-team-id`;
2. without it, the first "Apple Development" certificate (not for a release);
3. without any, `build-app.sh` signs ad hoc and `make install` stops.

`CODESIGN_IDENTITY` overrides the choice. On the release Mac, a local build and a release have the same designated requirement,
so the permissions stay when you go from `make install` to the Homebrew install and back. A local build has no secure timestamp
and works without the network. Only the release asks for one (`TIMESTAMP=1`) and is notarized.

The first time `codesign` uses the key, macOS asks for access: choose **Always Allow**.

### Hardened runtime

A release build of `build-app.sh` signs with the hardened runtime and `bundle/wm.entitlements`:

| Entitlement | Why |
|---|---|
| `com.apple.security.automation.apple-events` | The palette reads and selects browser tabs with Apple events |
| `com.apple.security.cs.disable-library-validation` | A config can `require` a Lua C module that someone else signed. By default `package.cpath` is only the config folder (`?.so`), so no module loads from a shared folder; a config that wants another one sets `package.cpath` |

A new use of a protected resource (camera, microphone, location) needs its entitlement there and its usage text in
`bundle/Info.plist`. A debug build has no hardened runtime, so that `lldb` can attach.

The engines are plain values with no AppKit, so most behavior has a test with literal frames. The parts that need a real
screen (overlays, the event tap, window moves) were checked by running the daemon.
