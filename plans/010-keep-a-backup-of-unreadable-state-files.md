# Plan 010: Move an unreadable `memory.json`, `float-memory.json` or `state.json` aside before it is overwritten

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md` — unless a reviewer dispatched you and told you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat cabd7ca..HEAD -- Sources/App/MemoryStore.swift Sources/App/StateStore.swift Sources/Common`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug (data loss)
- **Planned at**: commit `cabd7ca`, 2026-11-22

## Why this matters

When `memory.json` (the entries of `wm window remember`) cannot be decoded, because it is truncated or from another version, `MemoryStore.load` logs a warning and returns an empty memory. The next save writes that empty memory over the file, and every remembered window is gone with no copy. `float-memory.json` and `state.json` behave the same way. A single bad read should keep the old bytes for the user to look at.

## Current state

`Sources/App/MemoryStore.swift:10-26` (`MemoryStore.load`) returns `WindowMemory()` on a missing file, on a version mismatch (after a `Log.write(.warn, "ignoring \(url.path): version ...")`) and on a decode error (`"ignoring \(url.path): \(error)"`). `FloatMemoryStore.load` (`:37-44`) does the same with one combined `guard`. `StateStore.load` (`Sources/App/StateStore.swift:62-73`) returns `nil` in the same two cases. All writes go through `StateStore.write(_:to:)` (`StateStore.swift:100-104`), which uses `.atomic` writes in a 0700 directory.

A missing file is normal (first run) and must not be backed up. `App` has no test target, so the logic that can be tested must live in `Common` (its tests: `Tests/CommonTests`).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `swift build` | `Build complete!` |
| Focused tests | `timeout 300 swift test --filter StateBackupTests` | all pass |
| All tests | `timeout 300 swift test` | all pass |

## Scope

**In scope**: `Sources/Common/FileBackup.swift` (create), `Tests/CommonTests/StateBackupTests.swift` (create), `Sources/App/MemoryStore.swift`, `Sources/App/StateStore.swift`.

**Out of scope**: the file formats, versions, the write path, other stores (`custom-templates.json`), a restore command.

## Git workflow

- Branch `advisor/010-state-backup`. Commits: `feat(common): set an unreadable file aside as .bak`, `fix(state): keep an unreadable state or memory file as .bak`. Explicit paths. Never run `git config`. Do NOT push.

## Steps

### Step 1: The helper, with tests first

Create `Sources/Common/FileBackup.swift` with `@discardableResult public func setAsideUnreadableFile(at url: URL) -> URL?`: if the file exists, copy it to `<url path>.bak` (replace an older `.bak`), keep the permissions, and return the backup URL; return `nil` if the file does not exist or the copy fails (never throw, never crash).

Create `Tests/CommonTests/StateBackupTests.swift` (temporary directory pattern from `Tests/CommonTests/LogTests.swift:tempLog()`): tests for: a missing file returns `nil` and creates nothing; an existing file gets a `.bak` with the same bytes and the original stays; a second call replaces the `.bak`.

**Verify**: `timeout 300 swift test --filter StateBackupTests` → pass.

### Step 2: Use it in the three loaders

In `MemoryStore.load`, `FloatMemoryStore.load` and `StateStore.load`, call `setAsideUnreadableFile(at: url)` in the version-mismatch and decode-error branches (not for a missing file), and include the backup path in the existing warning text (`"... ignoring \(url.path), kept as \(backup.path)"`). Do not change what the functions return.

**Verify**: `swift build` → `Build complete!`; `grep -n 'setAsideUnreadableFile' Sources/App/*.swift` → 4 matches (memory has two branches).

### Step 3: Manual check (needs the app; say so if skipped)

Write `{` into a copy of `memory.json` in a temporary `XDG_STATE_HOME`, start the daemon with that variable set, and check `memory.json.bak` holds the `{` and the log has the warning.

## Test plan

Step 1. The loaders are three-line call additions; the manual check covers them.

## Done criteria

- [ ] `timeout 300 swift test` exits 0 with the new tests.
- [ ] `grep -c 'setAsideUnreadableFile' Sources/App/MemoryStore.swift Sources/App/StateStore.swift` totals 4 or more.
- [ ] Only in-scope files changed; `plans/README.md` updated.

## STOP conditions

- The loaders no longer have separate version-mismatch and decode-error branches that you can hook without changing return values.
- Backups would be written outside the state directory (they must sit next to the original).

## Maintenance notes

- One `.bak` per file is kept; a second corruption replaces it. That is deliberate (no growth).
- Reviewer: a missing file must never create a `.bak`.
