# Plan 005: List every command in `cli.md`, and fail a test when one is missing

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md` — unless a reviewer dispatched you and told you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat cabd7ca..HEAD -- docs/src/content/docs/cli.md Sources/Common/CommandSpec.swift Tests/CommonTests`
> **Precondition**: the `wm skills` command (files `Sources/Common/Skills.swift`, `Tests/CommonTests/SkillsTests.swift`, and edits to `CommandSpec.swift`, `Sources/Cli/main.swift`, `cli.md`, `README.md`) was uncommitted when this plan was written. It must be committed before you start (`git status` should not list those files as modified). If it is not, STOP and tell the operator.

## Status

- **Priority**: P2
- **Effort**: S (content) + S (test)
- **Risk**: LOW
- **Depends on**: none
- **Category**: docs
- **Planned at**: commit `cabd7ca` plus the uncommitted `wm skills` change, 2026-11-22

## Why this matters

`CLAUDE.md` requires a changed command to update `CommandSpec.swift` and its docs page. `docs/src/content/docs/cli.md` is the command reference, and it is already behind: when this plan was written, `hints`, `jump`, `pick`, `layout master promote` and `layout master orientation` did not appear in its command table (a word-by-word check; `scroll` and `select` also looked missing in the table). No test connects the two, so the gap grows with every feature.

## Current state

- `docs/src/content/docs/cli.md` starts with a fenced block (lines ~12-38) that lists commands by group, one group per line: `FOCUS AND MOVE`, `WINDOWS`, `WORKSPACES`, `LAYOUT`, `INTERFACE`, `INSPECT`, `MEMORY`, `DAEMON`, `EDITOR`, `CONFIG`, `SHELL`, `AGENTS`. For example:
  `INTERFACE        switcher | overview | palette | cheatsheet [tui|gui] | menu | mode <name|back> | pointer <window|monitor> | zen [on|off]`
  `LAYOUT           layout set <scrolling|tiling|master|monocle|floating> | balance | rotate | flip | tile | preselect <dir>`
- `Sources/Common/CommandSpec.swift` defines `commandSpecs` (public), a list of `CommandSpec` with `path` (for example `"layout master promote"`) and `words`.
- Tests find files next to the sources via `#filePath`: look at how `typeStubs()` is written in `Tests/ScriptingTests/LuaHostTests.swift` (around line 914) and copy that approach. `CommonTests` depends only on `Common`; the test file path is `Tests/CommonTests/...`, so the repo root is three `deletingLastPathComponent()` calls from `#filePath`.
- Existing test style: `Tests/CommonTests/CommandSpecTests.swift` (Swift Testing, `@testable import Common`).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Focused tests | `timeout 300 swift test --filter CommandSpecTests` | all pass |
| All tests | `timeout 300 swift test` | all pass |
| Docs build (optional) | `cd docs && pnpm build` | exit 0 |

## Scope

**In scope**: `docs/src/content/docs/cli.md`, `Tests/CommonTests/CommandSpecTests.swift` (or a new `CliDocsTests.swift`).

**Out of scope**: `CommandSpec.swift` text, other docs pages, generating `cli.md` from code (a larger direction item), the README.

## Git workflow

- Branch `advisor/005-cli-docs`. Commits: `test(docs): fail when cli.md misses a command`, `docs(cli): list hints, jump, scroll, select, pick and the master layout commands`. Explicit paths. Never run `git config`. Do NOT push.

## Steps

### Step 1: Write the test first

Add a test `everyCommandIsInTheCliDoc`: read `docs/src/content/docs/cli.md`, take the first fenced code block (the text between the first two lines that start with three backticks), and for every spec in `commandSpecs`, take the LAST word of `spec.path` (`"layout master promote"` → `promote`) and require that it appears in that block as a whole word. Whole word means the characters before and after are not letters, digits or `-` (so `scrolling` does not satisfy `scroll`). Report the missing paths in the failure message (`#expect(missing.isEmpty, "\(missing)")`).

**Verify**: `timeout 300 swift test --filter CommandSpecTests` → fails and lists the missing commands. Write the list into your report.

### Step 2: Add the rows

Edit the fenced block in `cli.md`, following the existing column layout and style, so that all missing commands appear. At least: `hints [open|close|toggle] [--wait]`, `scroll [open|close|toggle]`, `jump [open|close|toggle] [--swap] [--close]` and `select [open|close|toggle]` in `INTERFACE`; `pick [--json]` in `INSPECT`; and `layout master <promote|count|ratio|orientation>` in `LAYOUT`. Copy the exact argument text from `CommandSpec.swift` (`wm help hints` prints it). Keep lines readable; a new continuation line is fine.

**Verify**: `timeout 300 swift test --filter CommandSpecTests` → pass.

### Step 3: Whole suite

**Verify**: `timeout 300 swift test` → all pass.

## Test plan

The test in step 1. Its known weakness: it checks the last word only, so a multi-word command can hide behind a common last word. Say so in a comment above the test.

## Done criteria

- [ ] `timeout 300 swift test` exits 0 and includes `everyCommandIsInTheCliDoc`.
- [ ] `grep -nE 'hints|jump|pick|scroll|select|promote|orientation' docs/src/content/docs/cli.md` shows each in the table block.
- [ ] Only the two in-scope files changed.
- [ ] `plans/README.md` status row updated.

## STOP conditions

- The first fenced block of `cli.md` is not the command table any more.
- The test needs a file outside the repo, or `#filePath` is not usable from `CommonTests`.
- You find the docs describe a command differently from `CommandSpec.swift` (report it; do not rewrite pages).

## Maintenance notes

- A feature that adds a command now fails this test until `cli.md` is updated: that is the point.
- A stricter version would compare full paths; the table's compressed form (`window close | float [on|off]`) makes that hard. Generating the table from `commandSections` is the longer fix (see the direction list in the audit).
