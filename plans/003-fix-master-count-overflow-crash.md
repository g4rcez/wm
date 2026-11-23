# Plan 003: `layout master count +<huge>` must not crash the daemon

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md` — unless a reviewer dispatched you and told you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat cabd7ca..HEAD -- Sources/Core/MasterEngine.swift Sources/App/Commands.swift Tests/CoreTests/MasterEngineTests.swift`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `cabd7ca`, 2026-11-22

## Why this matters

`wm layout master count +9223372036854775807` makes the daemon compute `count + value`, which overflows `Int`. Swift traps on overflow, so `wmd` exits: tiling and the key tap stop. The command can come from the CLI, Lua, the socket and a `wm://` URL (`layout` is not blocked for URLs). One command should never kill the window manager.

## Current state

`Sources/App/Commands.swift:615-625` (`masterGroup`):

```swift
        case "count":
            guard let amount, let number = Int(amount) else {
                return fail("layout master count needs a number, or +n or -n", 2, usage: "layout master count")
            }
            return masterCommand(.masterCount(number, relative: relative), id, "layout master count")
```

`Sources/Core/MasterEngine.swift:226-230`:

```swift
        case .masterCount(let value, let relative):
            let wanted = min(max(relative ? count + value : value, 1), 99)
            guard wanted != count else { return false }
            count = wanted
            return true
```

`Int("+9223372036854775807")` is `Int.max`, so `count + value` traps. The result is clamped to 1...99 afterwards, so the right behaviour for a huge value is the clamp. The existing tests for this engine are in `Tests/CoreTests/MasterEngineTests.swift` (Swift Testing; model new tests on the ones that exercise `.masterCount`).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `swift build` | `Build complete!` |
| Focused tests | `timeout 300 swift test --filter MasterEngineTests` | all pass |
| All tests | `timeout 300 swift test` | all pass |

## Scope

**In scope**: `Sources/Core/MasterEngine.swift`, `Tests/CoreTests/MasterEngineTests.swift`, and only the sites that step 3 proves are the same bug.

**Out of scope**: command syntax, error messages, the clamp range (1...99), Lua API.

## Git workflow

- Branch `advisor/003-master-count-overflow`. Commit: `fix(master): clamp a relative master count instead of overflowing`. Explicit paths. Never run `git config`. Do NOT push.

## Steps

### Step 1: Failing test

In `MasterEngineTests.swift` add a test that applies `.masterCount(Int.max, relative: true)` and `.masterCount(Int.min, relative: true)` to an engine with a few windows (copy the setup of an existing `.masterCount` test) and expects the count to be 99 and 1. Keep this test; it must not crash.

**Verify**: `timeout 300 swift test --filter MasterEngineTests` → the run crashes or fails on the new test.

### Step 2: Fix the arithmetic

In `MasterEngine.swift` compute the sum without trapping, for example `let (sum, overflow) = count.addingReportingOverflow(value)` and use `overflow ? (value > 0 ? 99 : 1) : sum` as the input to the clamp. Do not change the clamp.

**Verify**: `timeout 300 swift test --filter MasterEngineTests` → all pass.

### Step 3: Sweep for the same pattern (report, fix only the same bug)

Run: `grep -nE 'Int\(' Sources/App/Commands.swift Sources/App/Controller.swift Sources/App/RuntimeInput.swift Sources/Scripting/RuntimeInput.swift 2>/dev/null` and `grep -rnE 'relative' Sources/Core | head -40`. For each place where a user-typed integer is added to, subtracted from, or multiplied with another integer without a clamp, decide if it can trap. Known safe: `LaneIndex` (clamped, `Types.swift:161-186`), the `window place` index (range-checked at `Commands.swift:515`). If you find another unclamped arithmetic on a parsed `Int`, fix it with the same approach and add a test; if it needs a design decision, list it in your report instead of fixing.

**Verify**: `swift build` → ok; `timeout 300 swift test` → all pass.

## Test plan

The new test in `MasterEngineTests.swift` (step 1), plus one per extra site from step 3.

## Done criteria

- [ ] `timeout 300 swift test` exits 0 with the new tests.
- [ ] The report lists every `Int(` parse site you checked and the verdict for each.
- [ ] Only in-scope files changed.
- [ ] `plans/README.md` status row updated.

## STOP conditions

- The excerpts do not match the live code.
- Fixing a site from step 3 would change a command's documented behaviour.
- A test crashes the test process in a way you cannot isolate after two attempts.

## Maintenance notes

- Any new command that adds a user value to engine state should clamp before adding.
- Reviewer: confirm the clamp result for `+huge` is the maximum and for `-huge` the minimum, not a wrap-around.
