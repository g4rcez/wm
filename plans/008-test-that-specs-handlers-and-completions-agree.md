# Plan 008: Fail a test when a command spec, its handler or its completion values drift apart

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md` — unless a reviewer dispatched you and told you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat cabd7ca..HEAD -- Sources/Common/Completion.swift Sources/Common/CommandSpec.swift Sources/App/Controller.swift Sources/App/Commands.swift Tests`
> **Precondition**: the uncommitted `wm skills` change must be committed first (it edits `CommandSpec.swift`). `git status` must not list `Sources/Common/Skills.swift` as untracked.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: 001 (so the new tests run in CI)
- **Category**: tests
- **Planned at**: commit `cabd7ca` plus the uncommitted `wm skills` change, 2026-11-22

## Why this matters

`wm help`, the shell completions and the daemon dispatcher each know the list of commands separately. `CommandSpec` is the single source for help and `Completion.swift`, but the dispatcher in `Sources/App/Controller.swift` and `Sources/App/Commands.swift` is a hand-written `switch` on strings, and `Completion.swift` hard-codes value lists that copy Core enums. A command added to the spec but not to the switch fails at runtime with "unknown command"; a new layout name or snap place is not completed. Only rename targets and flag docs are tested today (`Tests/CommonTests/CommandSpecTests.swift`).

## Current state

- `Sources/Common/CommandSpec.swift`: `public let commandSpecs`, `public let commandNames: Set<String>` (the first word of every command).
- `Sources/App/Controller.swift:225-330` is the top-level `switch` with string cases such as `case "overview":`, `case "hints", "scroll":`, `case "jump":`, `case "exec":`, `case "key":`, `case "daemon":`, `case "batch":`. `Sources/App/Commands.swift` has the window-manager commands, again by `case "<word>"`. `App` has no test target.
- `Sources/Common/Completion.swift:46-79` has private lists that duplicate Core enums:

```swift
private let extraValues: [String: [String]] = [
    "layout set": ["scrolling", "tiling", "master", "monocle", "floating"],
    "window snap": ["left", "right", "top", "bottom", "top-left", ..., "center"],
    "workspace all": ["scrolling", "tiling", "master", "monocle", "floating"],
    "layout tile": ["2", "3", "4", "5", "6", "2+1", "1+2", "2/3", "3/4", "1/4", "center"],
    ...
```

- The public completion entry point is `complete(_ words: [String], source: CompletionSource) -> ...` and `renderCompletion(...)` (see how `Sources/Cli/main.swift:34-52` calls them, and `Tests/CommonTests/CompletionTests.swift` for how tests call them).
- Core enums with `CaseIterable` and a `String` raw value: `LayoutKind` (`Sources/Core/Settings.swift:4`), `SnapPlace` (`Sources/Core/Snap.swift:5`), `Direction` (`Sources/Core/Types.swift:7`).
- `Tests/ScriptingTests` depends on `Scripting`, `Core` and `Common` (see `Package.swift`), so a test there can see all three.
- Tests locate repo files with `#filePath` (see `typeStubs()` in `Tests/ScriptingTests/LuaHostTests.swift:914`).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `swift build` | `Build complete!` |
| Focused tests | `timeout 300 swift test --filter CommandSpecTests` and `--filter CompletionTests` | all pass |
| All tests | `timeout 300 swift test` | all pass |

## Scope

**In scope**: new `Tests/ScriptingTests/CommandConsistencyTests.swift`; `Sources/Common/Completion.swift` only if a test reveals a real drift that you fix by adding the missing value (list the drift in your report).

**Out of scope**: restructuring the dispatcher (plan 014), changing any command, the `Package.swift` dependency graph.

## Git workflow

- Branch `advisor/008-command-consistency`. Commit: `test(commands): check specs, handlers and completion values against each other`. Explicit paths. Never run `git config`. Do NOT push.

## Steps

### Step 1: The handler test

In the new test file, read `Sources/App/Controller.swift` and `Sources/App/Commands.swift` as text (repo root = three `deleteLastPathComponent()` from `#filePath`). For every word in `commandNames`, require that either file contains `case "<word>"` (as a substring, also matching inside a list such as `case "hints", "scroll":`). Commands handled outside the daemon are in `Sources/Cli/main.swift` (`cheatsheet`, `completion`, `logs`, `lsp`, `init`, `config`, `doctor`, `skills`, `daemon start/stop`, `version`): for these, require `arguments.first == "<word>"` in `Sources/Cli/main.swift`, or put them in a small named allow-list inside the test with a comment. Failure messages list the words.

**Verify**: `timeout 300 swift test --filter CommandConsistencyTests` → passes (if it fails because of a real gap, that is a finding: report it, do not hide it in the allow-list).

### Step 2: The completion-values test

Add tests that call the public `complete(...)` for `["layout", "set", ""]`, `["workspace", "all", ""]`, `["window", "snap", ""]` and `["resize", ""]` and `["window", "place", ""]` and assert the set of offered words equals: `LayoutKind.allCases.map(\.rawValue)` for the first two; `SnapPlace.allCases.map(\.rawValue)` for snap. Look at `Tests/CommonTests/CompletionTests.swift` for the exact call and result shape and copy it. If `LayoutKind` has cases that are intentionally not offered, the test must say so with a comment and a named exclusion.

**Verify**: `timeout 300 swift test --filter CommandConsistencyTests` → pass.

### Step 3: Whole suite

**Verify**: `timeout 300 swift test` → all pass.

## Test plan

Steps 1 and 2 are the tests. Weakness to document in a comment: the handler test is textual (App has no test target); it catches a missing `case`, not a wrong one.

## Done criteria

- [ ] `timeout 300 swift test` exits 0 and includes `CommandConsistencyTests`.
- [ ] Any drift found is either fixed in `Completion.swift` (with the diff described) or listed in the report.
- [ ] Only in-scope files changed.
- [ ] `plans/README.md` status row updated.

## STOP conditions

- `Controller.swift` no longer dispatches with `case "<word>"` strings (the dispatcher was restructured; then plan 014 may be done already).
- The test requires a new dependency in `Package.swift`.

## Maintenance notes

- If plan 014 makes the dispatcher table-driven, replace the textual test by a direct one.
- Reviewer: look at the allow-list; every entry must have a reason.
