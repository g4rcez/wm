# Plan 006: Resolve the settings of a workspace once, not on every call and every animation frame

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md` — unless a reviewer dispatched you and told you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat cabd7ca..HEAD -- Sources/App/WindowManager.swift Sources/Scripting/ConfigParsing.swift`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: perf
- **Planned at**: commit `cabd7ca`, 2026-11-22

## Why this matters

`settings(forWorkspace:)` copies the whole `Settings` struct and re-runs the Lua override table through `applyConfig` every time it is called when the workspace has a `wm.workspace` override. It is called from 18 places, including twice per animation frame through `updateBorder()`. That is config parsing on the main thread at the display rate while a window animates. Workspaces without overrides already return early, so only users of `wm.workspace { ... gaps/border/tiling/scrolling ... }` pay.

## Current state

`Sources/App/WindowManager.swift:80` and `:87`:

```swift
    var settings = Settings()
    ...
    private(set) var workspaceRules: [String: WorkspaceRule] = [:]
```

`workspaceRules` is assigned in one place: `Sources/App/WindowManager.swift:217` (`workspaceRules = newRules`, inside the config-load path). `settings` is mutated by config load and by `wm set`.

`Sources/App/WindowManager.swift:244-251`:

```swift
    /// The settings of a workspace: the global ones with the changes of its `wm.workspace` rule.
    func settings(forWorkspace name: String) -> Settings {
        guard let overrides = workspaceRules[name]?.overrides else { return settings }
        var copy = settings
        // The values were checked when the config loaded.
        try? applyWorkspaceOverrides(overrides, to: &copy)
        return copy
    }
```

Callers in the animation path: `tick()` (`:1741`) calls `updateBorder()` (`:1776-`) which calls `settings(forWorkspace:)` twice, and `layoutContext` calls it once per monitor on every `relayout`. `applyWorkspaceOverrides` is `Sources/Scripting/ConfigParsing.swift:617` and is `try applyConfig(overrides, to: &settings)`.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `swift build` | `Build complete!` |
| All tests | `timeout 300 swift test` | all pass |

There is no test target for `App`; verification is by build, the grep checks below, and a manual run.

## Scope

**In scope**: `Sources/App/WindowManager.swift` only.

**Out of scope**: `applyWorkspaceOverrides`, `Settings`, every caller of `settings(forWorkspace:)` (do not change call sites), the animation code.

## Git workflow

- Branch `advisor/006-workspace-settings-cache`. Commit: `perf(workspace): resolve the settings of a workspace once until the config changes`. Explicit paths. Never run `git config`. Do NOT push.

## Steps

### Step 1: Add the cache and its invalidation

In `WindowManager`, add `private var workspaceSettingsCache: [String: Settings] = [:]`. Change the two stored properties so that any change clears it:

```swift
    var settings = Settings() { didSet { workspaceSettingsCache.removeAll() } }
    private(set) var workspaceRules: [String: WorkspaceRule] = [:] { didSet { workspaceSettingsCache.removeAll() } }
```

(Keep the doc comments that are above these lines.) In `settings(forWorkspace:)`, after the early return, return `workspaceSettingsCache[name]` when it exists; otherwise compute as today, store the result, and return it.

**Verify**: `swift build` → `Build complete!` (a `didSet` on a property with an initial value is fine in Swift 6.2).

### Step 2: Check nothing else can change the inputs without going through those two properties

Run `grep -n 'workspaceRules\b' Sources/App/*.swift` and `grep -n 'settings\.' Sources/App/*.swift | grep -E '=\s' | head -40`. Every write to a field of `settings` is a write to the `settings` property and triggers `didSet`. If you find a write to `workspaceRules[...]` (a subscript set) that does not go through the property, that also triggers `didSet`; no action. If you find `Settings` values copied into another long-lived variable that `settings(forWorkspace:)` reads from, STOP.

**Verify**: the grep output shows no other source of the two inputs. Put the findings in your report.

### Step 3: Manual check (needs the app; skip and say so if you cannot run it)

With a config that has `wm.workspace("2", { border = { enabled = true } })` style overrides (see `docs/src/content/docs/rules.md` or `config.md` for the exact `wm.workspace` form), run `wm set border.enabled false`, switch to workspace 2, and check that the global change still applies where there is no override and the override still wins on workspace 2. Then `wm daemon reload` and check it still behaves the same.

## Test plan

No unit test is possible without an `App` test target (see plan 014). The cache logic is three lines; the review should check invalidation, not the lookup.

## Done criteria

- [ ] `swift build` and `timeout 300 swift test` pass.
- [ ] `grep -n 'workspaceSettingsCache' Sources/App/WindowManager.swift` shows the declaration, two `didSet` clears and one lookup/store.
- [ ] Only `Sources/App/WindowManager.swift` changed.
- [ ] `plans/README.md` status row updated.

## STOP conditions

- `settings` or `workspaceRules` are no longer the stored properties shown above.
- Step 2 finds another place where a workspace's settings could change without the two properties changing (for example a per-workspace mutable override that is edited in place).

## Maintenance notes

- If a per-workspace setting is ever changed at runtime (a new `wm set` scope), it must go through `workspaceRules` or `settings`, or call `workspaceSettingsCache.removeAll()`.
- Reviewer: `didSet` on a struct property fires on any nested mutation. That is wanted here, but it also means a hot loop that writes `settings.x` repeatedly would clear the cache each time; none exists today.
