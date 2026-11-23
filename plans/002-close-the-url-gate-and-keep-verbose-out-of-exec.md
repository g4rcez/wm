# Plan 002: Make the `wm://` allow-list unbypassable, and stop the daemon from eating `--verbose` inside `exec`

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md` — unless a reviewer dispatched you and told you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat cabd7ca..HEAD -- Sources/Common/CommandText.swift Sources/App/Controller.swift Tests/CommonTests/CommandTextTests.swift`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1 (security)
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none (001 is nice to have first)
- **Category**: security + bug
- **Planned at**: commit `cabd7ca`, 2026-11-22

## Why this matters

Any web page or app can open a `wm://` URL. wm blocks `exec`, `key`, `daemon` and `subscribe` for URLs unless the config lists them in `url.allow`. The check only looks at the first word of the request, but the daemon later deletes every `--verbose` word. A URL whose first word is `--verbose` passes the check and then runs `exec` (an arbitrary shell command) or `key` (typed keys). The same deletion also changes `wm exec foo --verbose` into `foo`, which is a separate bug. This was confirmed by reading the code; it was not executed.

## Current state

`Sources/Common/CommandText.swift:3-15`:

```swift
public let urlBlockedCommands: Set<String> = ["exec", "daemon", "subscribe", "key"]

public func urlBlockedCommand(in words: [String], allowed: [String]) -> String? {
    guard let command = words.first else { return nil }
    if command == "batch" {
        let inner = splitBatch(words.dropFirst().joined(separator: " ")).map(splitCommand)
        return inner.lazy.compactMap { urlBlockedCommand(in: $0, allowed: allowed) }.first
    }
    return urlBlockedCommands.contains(command) && !allowed.contains(command) ? command : nil
}
```

`Sources/App/Controller.swift:147-153` (`run(_ request:)`) and `:562-570` (`handle(url:)`):

```swift
    func run(_ request: ClientRequest) -> ServerAnswer {
        var args = request.args
        let verbose = args.contains("--verbose")
        args.removeAll { $0 == "--verbose" }
        ...
    @MainActor func handle(url: URL) {
        guard let request = commandRequest(fromURL: url) else { return }
        if let command = urlBlockedCommand(in: request.args, allowed: manager.settings.urlAllow) {
            ...
            return
        }
        let answer = run(request)
```

The `exec` case in `Controller.run(_ args:target:)` is `args.dropFirst().joined(separator: " ")`. `Sources/Cli/main.swift:65-67` shows the intended rule: `-v` becomes `--verbose` everywhere except after `exec`, whose words belong to the shell command.

`commandWords(fromURL:)` (`CommandText.swift:46-58`) builds the words from the URL host, the path segments and `?args=`, so a URL like `wm://--verbose/exec?args=open%20-a%20Calculator` yields `["--verbose", "exec", "open", "-a", "Calculator"]`.

Existing tests: `Tests/CommonTests/CommandTextTests.swift:46-56` check `urlBlockedCommand` with `exec`, `batch` and `key`. Model new tests on them.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `swift build` | `Build complete!` |
| Focused tests | `timeout 300 swift test --filter CommandTextTests` | all pass |
| All tests | `timeout 300 swift test` | all pass |

## Scope

**In scope**: `Sources/Common/CommandText.swift`, `Sources/App/Controller.swift` (only `run(_ request:)`), `Tests/CommonTests/CommandTextTests.swift`, `Sources/Common/CommandSpec.swift` (one sentence in the `exec` details), `docs/src/content/docs/url-scheme.md` (one line, if it describes the block list).

**Out of scope**: the list of blocked commands, `url.allow` semantics, `Sources/Cli/main.swift`, anything about `batch` beyond what is below.

## Git workflow

- Branch `advisor/002-url-gate`. Commits: `fix(url): look past global flags when checking the blocked commands`, then `fix(exec): keep --verbose that belongs to the shell command`. Add files by explicit path. Never run `git config`.
- Do NOT push or open a PR unless the operator told you to.

## Steps

### Step 1: Write failing tests first

In `CommandTextTests.swift` add tests (same style as the existing ones) that expect:

- `urlBlockedCommand(in: ["--verbose", "exec", "open -a Calculator"], allowed: []) == "exec"`
- the same with `key` (`["--verbose", "key", "press", "cmd-space"]`) and `daemon`
- `["-v", "exec", "x"]`, `["--verbose", "--verbose", "exec", "x"]` → `"exec"`
- inside batch: `urlBlockedCommand(in: ["batch", "--verbose exec 'touch x'"], allowed: []) == "exec"`
- `["--verbose", "exec", "x"]` with `allowed: ["exec"]` → `nil`
- `["--verbose", "workspace", "2"]` → `nil`

**Verify**: `timeout 300 swift test --filter CommandTextTests` → the new tests FAIL (this proves they test the bug).

### Step 2: Make the gate skip leading flags

In `urlBlockedCommand`, replace `guard let command = words.first` with: the first word that does not start with `-` (`words.first(where: { !$0.hasPrefix("-") })`). A request with only flags returns `nil`. This only ever blocks more, never less. Do not change anything else in the function.

**Verify**: `timeout 300 swift test --filter CommandTextTests` → all pass, including the new ones.

### Step 3: Move the `--verbose` rule into a tested Common function

Add to `CommandText.swift`:

```swift
/// `--verbose` before the command word is always the flag. After `exec` it is part of the shell command and stays.
/// Anywhere else it is the flag too.
public func stripVerbose(_ args: [String]) -> (args: [String], verbose: Bool)
```

Behaviour: drop every leading word equal to `--verbose`. If the next word is `exec`, return the rest untouched. Otherwise drop every `--verbose` in the rest. `verbose` is true when anything was dropped. Add unit tests: `["focus","left","--verbose"]` → `(["focus","left"], true)`; `["exec","make","--verbose"]` → `(["exec","make","--verbose"], false)`; `["--verbose","exec","make","--verbose"]` → `(["exec","make","--verbose"], true)`; `["list"]` → `(["list"], false)`.

In `Controller.run(_ request:)` replace the three lines that compute `verbose` and strip with a call to `stripVerbose`. Keep the rest of the function as it is.

**Verify**: `swift build` → `Build complete!`; `timeout 300 swift test` → all pass.

### Step 4: Docs

In `CommandSpec.swift`, add to the `exec` `details`: "`--verbose` after `exec` belongs to the shell command." If `docs/src/content/docs/url-scheme.md` lists the blocked commands, make sure it does not claim anything the fix changes (it should not need an edit).

**Verify**: `swift build` → ok; `swift run wm help exec | grep verbose` → shows the new sentence.

## Test plan

Covered in steps 1 and 3 (Swift Testing, in `CommandTextTests.swift`). There is no daemon test target, which is why the strip rule moves to Common.

## Done criteria

- [ ] `timeout 300 swift test` exits 0 and includes the new tests.
- [ ] `grep -n 'removeAll { \$0 == "--verbose" }' Sources/App/Controller.swift` returns nothing.
- [ ] Only the in-scope files changed (`git status`).
- [ ] `plans/README.md` status row updated.
- [ ] Final report says: confirmed by tests, not by sending a real `wm://` URL to a running daemon.

## STOP conditions

- `commandWords(fromURL:)` or `run(_ request:)` no longer look like the excerpts.
- A step needs a change to `Sources/Cli/main.swift` or to the list `urlBlockedCommands`.
- Existing tests that you did not touch start to fail.

## Maintenance notes

- Any new global flag added to the CLI must be skipped by the gate (the rule "first word that does not start with `-`" covers it).
- Reviewer: check that the gate still sees `batch` inner commands, and that `exec` keeps every word after it.
- Deferred: a larger fix would run the gate inside `run` for all URL-originated requests, so no path can skip it. That needs a flag on `ClientRequest`; not done here.
