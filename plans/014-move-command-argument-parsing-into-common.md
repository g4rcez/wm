# Plan 014: Parse the `hints`, `scroll` and `jump` arguments in `Common`, with tests, instead of in the daemon

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md` — unless a reviewer dispatched you and told you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat cabd7ca..HEAD -- Sources/App/Controller.swift Sources/App/Answer.swift Sources/Common Tests/CommonTests`
> **Precondition**: the uncommitted `wm skills` change must be committed first (`git status` must be clean for `Sources/Common`).

## Status

- **Priority**: P3
- **Effort**: M (this plan is a first slice of a larger refactor; the rest is deferred)
- **Risk**: MED (user-visible error text and exit codes must not change)
- **Depends on**: 008, and 001 for CI
- **Category**: tests + tech-debt
- **Planned at**: commit `cabd7ca` plus the uncommitted `wm skills` change, 2026-11-22

## Why this matters

`Sources/App` has no test target, and it holds the highest-churn files (`WindowManager.swift` 24 commits since September, `Commands.swift` 16, `Controller.swift` 15). The parsing of command arguments, the allowed flags, the `usage:` strings and the exit codes are all in there, repeated per command, and no test notices a change. A full restructure is too large for one plan. This slice takes the most repeated pattern, the `open|close|toggle` commands, moves its pure logic into `Common`, and pins the current behaviour with tests so that later slices have a pattern to follow.

## Current state

`Sources/App/Controller.swift:225-285` repeats nearly the same validation for `hints`, `scroll` and `jump`. `overview` and `select` are a DIFFERENT shape: they take no flags at all, so `wm overview --x` fails with "overview takes open, close or toggle" (the flag is read as the mode), and `select` also checks `args.count <= 2`. Do NOT route those two through the new parser; leave them as they are (they stay as the baseline's reference for "what must not change"). `jump` has one extra rule after parsing, `guard flags.count < 2 else { return fail("jump takes --swap or --close, not both", 2, usage: "jump") }`, which stays in the controller. The excerpt:

```swift
        case "overview":
            let mode = args.dropFirst().first
            guard mode == nil || ["open", "close", "toggle"].contains(mode) else {
                return fail("overview takes open, close or toggle", 2, usage: "overview")
            }
            ...
        case "hints", "scroll":
            let flags = Set(args.dropFirst().filter { $0.hasPrefix("--") })
            let words = args.dropFirst().filter { !$0.hasPrefix("--") }
            if let bad = unknownOption(flags, allowed: args[0] == "hints" ? ["--wait"] : [], usage: args[0]) { return bad }
            let mode = words.first
            guard words.count <= 1, mode == nil || ["open", "close", "toggle"].contains(mode) else {
                return fail("\(args[0]) takes open, close or toggle", 2, usage: args[0])
            }
        ...
        case "jump":
            let flags = Set(args.dropFirst().filter { $0.hasPrefix("--") })
            let words = args.dropFirst().filter { !$0.hasPrefix("--") }
            if let bad = unknownOption(flags, allowed: ["--swap", "--close"], usage: "jump") { return bad }
            let mode = words.first
            guard words.count <= 1, mode == nil || ["open", "close", "toggle"].contains(mode) else {
                return fail("jump takes open, close or toggle", 2, usage: "jump")
            }
```

`unknownOption(_ flags: Set<String>, allowed: Set<String>, usage: String)` is in `Sources/App/Answer.swift:18`: it names the first unknown flag in sorted order (`flags.subtracting(allowed).sorted().first`) with exit code 2, and adds the hint "--silent is now --stay" for `--silent`. Keep calling it; the parser must not reimplement the message. The same options are documented in `CommandSpec.flags` and `commandOptions` (`Sources/Common/CommandOptions.swift`).

`Tests/CommonTests` covers `Common` (Swift Testing). `Common` has no dependencies.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `swift build` | `Build complete!` |
| Focused tests | `timeout 300 swift test --filter ToggleCommandTests` | all pass |
| All tests | `timeout 300 swift test` | all pass |
| Behaviour check (needs the daemon) | `wm hints bogus; echo $?` | the same text and exit 2 as before |

## Scope

**In scope**: `Sources/Common/ToggleCommand.swift` (create), `Tests/CommonTests/ToggleCommandTests.swift` (create), `Sources/App/Controller.swift` (only the argument handling of the `hints`/`scroll` and `jump` cases).

**Out of scope**: what the commands do after parsing (`switcher.overview`, `hints.command`, ...), every other command, `Commands.swift`, the `unknownOption` messages (reuse them as they are), splitting `WindowManager`.

## Git workflow

- Branch `advisor/014-toggle-parsing`. Commits: `test(controller): pin the error text of the open/close/toggle commands`, `refactor(controller): parse the open/close/toggle commands in Common`. Explicit paths. Never run `git config`. Do NOT push.

## Steps

### Step 1: Record the current behaviour before touching it

With the daemon running a build of this tree, record in `plans/014-baseline.txt` (created by you, committed with the first commit) the exact stdout, stderr and exit code of these invocations: `wm overview bogus`, `wm hints bogus`, `wm hints open extra`, `wm hints --bogus`, `wm scroll bogus`, `wm jump bogus`, `wm jump --bogus`, `wm jump open close`, `wm select bogus`, `wm overview --x`, `wm select open extra`. If you cannot run the daemon, derive the expected messages from the code above and say that you did.

### Step 2: The pure function, with tests first

Create `Sources/Common/ToggleCommand.swift`:

```swift
public enum ToggleMode: String { case open, close, toggle }
public struct ToggleArguments: Equatable { public let mode: ToggleMode?; public let flags: Set<String> }
public enum ToggleParseError: Equatable { case unknownFlag(String), badMode }
public func parseToggleArguments(_ args: [String], allowedFlags: [String]) -> Result<ToggleArguments, ToggleParseError>
```

`args` is the command words after the command name. Behaviour, matching the current code for `hints`, `scroll` and `jump`: words starting with `--` are flags and are returned in `flags` (all of them, known or not; the controller passes the set to `unknownOption`, which stays the one place that words the error and checks the flags first, as today); more than one non-flag word, or one that is not `open`/`close`/`toggle`, gives `.badMode`; no word gives `mode == nil`. Because the controller checks unknown flags BEFORE the mode, so `wm hints --bogus bogus` reports the flag, not the mode, keep that order. Drop `.unknownFlag` and the `allowedFlags` parameter if they are not needed: the simplest correct function is `parseToggleArguments(_ args: [String]) -> Result<ToggleArguments, ToggleParseError>` with only `.badMode`.

Write `Tests/CommonTests/ToggleCommandTests.swift` first: no arguments; each valid mode; a flag that is allowed; a flag that is not; two words; an unknown word; flag plus mode in either order.

**Verify**: `timeout 300 swift test --filter ToggleCommandTests` → pass.

### Step 3: Use it in the controller

In the `hints`/`scroll` case and the `jump` case only, replace the hand-written `flags`/`words`/`mode` lines with `parseToggleArguments`: call `unknownOption(parsed.flags, allowed: ..., usage: ...)` first (same allowed sets as today: `hints` `["--wait"]`, `scroll` none, `jump` `["--swap", "--close"]`), then map `.badMode` to the existing `fail("<command> takes open, close or toggle", 2, usage: "<command>")`, then (jump only) the existing "not both" check. Keep everything after parsing (the `onMain { ... }` blocks) exactly as it is. Do not touch `overview` and `select`.

**Verify**: `swift build` → ok; `timeout 300 swift test` → all pass; rerun the step 1 invocations with a daemon built from your branch and `diff` the output with the baseline → identical.

## Test plan

`ToggleCommandTests` (step 2) and the before/after diff of the baseline (step 3). No App-level unit tests are possible yet; that is the deferred part of this refactor.

## Done criteria

- [ ] `timeout 300 swift test` exits 0 with the new tests.
- [ ] The baseline diff is empty (or you list each difference and why).
- [ ] `grep -c '"open", "close", "toggle"' Sources/App/Controller.swift` drops from 4 to 2 (only `overview` and `select` keep their own check).
- [ ] Only in-scope files changed; `plans/README.md` updated.

## STOP conditions

- The current `hints`/`scroll`/`jump` cases differ from the excerpt: report.
- The baseline cannot be matched exactly with a shared parser (the commands differ in more than the allowed flags): report, do not change messages.

## Maintenance notes

- Deferred slices, in order: `focus`/`move`/`resize` argument parsing (`Commands.swift:10-60`), then driving flag validation from `CommandSpec.flags` instead of 22 hand-written `unknownOption(... allowed: [...])` calls, then extracting state persistence and the Dock-badge timer out of `WindowManager`.
- Reviewer: any change in error text or exit code is a regression.
