# Plan 013: Measure what a full window refresh costs, then decide whether to make it incremental

> **Executor instructions**: This is an INVESTIGATION plan. Its product is a short report, not a fix. Follow the steps in order. Do not commit instrumentation. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md` — unless a reviewer dispatched you and told you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat cabd7ca..HEAD -- Sources/App/WindowManager.swift Sources/Platform/AppWatcher.swift`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: M
- **Risk**: MED (if it leads to a fix; the investigation itself changes nothing that is committed)
- **Depends on**: none
- **Category**: perf (investigate)
- **Planned at**: commit `cabd7ca`, 2026-11-22

## Why this matters

Every accessibility notification that reaches wm schedules a refresh that reads about eight attributes of every window of every app and then relays out every monitor. That cost grows with the number of windows, and the auditor could not tell from reading whether it is noticeable. Optimizing it blind would risk the reconcile logic, which depends on fresh titles and roles. The right first step is a measurement.

## Current state

- `Sources/App/WindowManager.swift:190-199`: `start()` creates `AppTracker { [weak self] in self?.scheduleRefresh() }`.
- `Sources/App/WindowManager.swift:276-298`, `refresh()`:

```swift
        tracker.syncWatchers()
        let (infos, unread) = await tracker.snapshot()
        let focusedID = await tracker.focusedWindow()
        ...
        updateMonitors()
        beginRebootRestore()
        reconcile(infos, unread: unread)
        finishRestore()
        ...
        relayout()
        didFirstScan = true
```

- `Sources/Platform/AppWatcher.swift:182-206`, `readWindows()` (runs on the per-app AX thread): for each window it reads position, size, title, role, subrole, `AXIdentifier`, minimized and `AXFullScreen`, i.e. about eight AX calls, and subscribes to notifications.
- `Sources/Platform/AppWatcher.swift:100-114`, `frames()`: a cheaper path of two reads, used today only for the mouse gesture.
- `Sources/App/WindowManager.swift:540-551`, `holdOpeningPlace(of:)`: three more refreshes at 0.25, 0.7 and 1.3 s after a floating window opens, each guarded by `openingHold[id] != nil` (so they do nothing once the hold is cleared).
- AX calls run on the per-app threads, not the main thread; the main thread pays for `reconcile` and `relayout`.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `swift build -c release` | `Build complete!` |
| Run the app built from this tree | `./build-app.sh release` (stops and replaces the running wm; ask the operator first) | `Built .build/wm.app` |
| Read the log | `wm logs -n 200 -o json` | the timing records |

## Scope

**In scope**: temporary local instrumentation in `Sources/App/WindowManager.swift` (never committed), and the report file `plans/013-findings.md` (create).

**Out of scope**: any committed code change, `Sources/Platform/AppWatcher.swift` edits (except temporary timing), changing refresh triggers.

## Git workflow

- Work on a scratch branch `advisor/013-refresh-measure`, and discard the instrumentation with `git checkout -- Sources/App/WindowManager.swift` at the end. Only `plans/013-findings.md` is committed: `docs(plans): add the refresh cost measurement`. Never run `git config`. Do NOT push.

## Steps

### Step 1: Add temporary timing

In `refresh()`, wrap `tracker.snapshot()`, `reconcile(...)` and `relayout()` with `ContinuousClock` timing and one `Log.write(.debug, "refresh snapshot=…ms reconcile=…ms relayout=…ms windows=N apps=M", source: "perf")` per refresh. Do not change behaviour.

**Verify**: `swift build -c release` → `Build complete!`.

### Step 2: Measure three situations

Run the instrumented app (get the operator's OK before replacing the running wm) and record, from `wm logs`, the median and the worst of the three timings in each case:

1. A quiet desktop, about 10 windows: only focus changes (click between windows 30 times).
2. About 40 windows across apps, same focus changes, plus opening and closing a window.
3. Dragging a floating window for a few seconds (this is the heaviest event stream).

Also count refreshes per second in case 3.

### Step 3: Write the report and a verdict

Create `plans/013-findings.md` with the table of measurements, the machine (chip, macOS version), and one of three verdicts: **not worth doing** (all refreshes under about 4 ms of main-thread time and no visible lag), **worth a targeted fix** (name the expensive part and the cheapest safe change, for example reading only the focused window on focus events), or **needs a profile** (the numbers do not explain what you see; say what to profile with Instruments). If you recommend a fix, write it as an outline of a future plan, not as code.

### Step 4: Remove the instrumentation

**Verify**: `git diff --stat -- Sources` → empty.

## Test plan

No code is delivered. The report is the artifact.

## Done criteria

- [ ] `plans/013-findings.md` exists with measurements for the three cases and a verdict.
- [ ] `git diff --stat -- Sources` is empty (instrumentation removed).
- [ ] `plans/README.md` status row updated (DONE with the verdict in one line).

## STOP conditions

- The operator does not allow replacing the running wm: write down what you could measure without it (for example from the existing log), mark the plan BLOCKED.
- Timings show a refresh taking over 100 ms on the main thread: report it immediately, it is a real bug.

## Maintenance notes

- Numbers from a debug build are not comparable; use release.
- If a fix follows, the characterization tests of plan 014 should exist first.
