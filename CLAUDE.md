# wm

## Build

A task is not done while the code has a compile warning or error. `Package.swift` makes every warning an error (except in the
vendored Lua). Before you finish, run `swift build` and `timeout 600 swift test` and see both pass. Fix a warning at its cause; do
not turn the setting off.

## Documentation

A new or changed feature is not done until its docs are done. In the same change, update every place that describes it:

- the page in `docs/src/content/docs/` (and the README section that links to it);
- `types/wm.lua` for a Lua API or `wm.config` key (a test checks that every config key is described);
- `Sources/Common/CommandSpec.swift` for a command, its flags or its help text;
- the user's sample config, when the feature has config keys, only if the user asks for it.

Say in the final answer which docs you changed. If a feature needs no docs, say why.
