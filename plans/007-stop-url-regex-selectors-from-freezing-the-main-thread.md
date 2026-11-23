# Plan 007: A `wm://` URL may not use a `title:` regex window selector, and the regex is compiled once

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md` — unless a reviewer dispatched you and told you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat cabd7ca..HEAD -- Sources/Common/CommandText.swift Sources/App/WindowManager.swift Tests/CommonTests/CommandTextTests.swift docs/src/content/docs/url-scheme.md`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2 (security, hardening)
- **Effort**: S
- **Risk**: LOW
- **Depends on**: 002 (both change the URL path; do 002 first to avoid conflicts in `CommandText.swift`)
- **Category**: security
- **Planned at**: commit `cabd7ca`, 2026-11-22

## Why this matters

`wm://...?window=title:<regex>` is allowed from any web page. The pattern is matched with ICU on the main thread against the title of every window (`title.range(of: pattern, options: .regularExpression)`). A pattern with catastrophic backtracking, against a long title, freezes the UI and the key tap until it ends. ICU through Foundation gives no time limit. The practical fix is to not accept this selector from URLs, and to compile the regex once instead of once per window.

## Current state

`Sources/App/WindowManager.swift:1925-1930` (`window(matching:)`):

```swift
        } else if selector.hasPrefix("title:") {
            let pattern = String(selector.dropFirst(6))
            matches = windows.filter { $0.value.info.title.range(of: pattern, options: .regularExpression) != nil }.map(\.key)
```

`Sources/Common/CommandText.swift:127-134` (`commandRequest(fromURL:)`):

```swift
    guard let value = items.first(where: { $0.name == "window" })?.value else { return ClientRequest(args: words) }
    if let id = UInt32(value) { return ClientRequest(args: words, windowId: id) }
    guard isWindowSelector(value) else { return nil }
    return ClientRequest(args: words, windowSelector: value)
```

`docs/src/content/docs/url-scheme.md` does not mention `title:` (checked with grep). `isWindowSelector` lives in `Sources/Common/WindowPick.swift` or `Sources/Common/Protocol.swift` (find it with `grep -rn 'func isWindowSelector' Sources/Common`).

The same selector is also valid from the CLI (`wm --window title:<re> ...`) and must keep working there.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `swift build` | `Build complete!` |
| Focused tests | `timeout 300 swift test --filter CommandTextTests` | all pass |
| All tests | `timeout 300 swift test` | all pass |

## Scope

**In scope**: `Sources/Common/CommandText.swift`, `Tests/CommonTests/CommandTextTests.swift`, `Sources/App/WindowManager.swift` (only `window(matching:)`), `docs/src/content/docs/url-scheme.md`.

**Out of scope**: the CLI path, other selectors, `url.allow` semantics, a time limit for ICU (not available).

## Git workflow

- Branch `advisor/007-url-title-selector`. Commits: `fix(url): refuse the title: window selector in a wm:// URL`, `perf(selector): compile the title pattern once`. Explicit paths. Never run `git config`. Do NOT push.

## Steps

### Step 1: Failing tests

In `CommandTextTests.swift` (copy the style of the existing `commandRequest` tests, if any; otherwise of `urlBlockedCommand` tests) add: a `wm://focus/left?window=title:.*` URL gives `commandRequest(fromURL:) == nil`; a `wm://focus/left?window=app:Safari` URL still gives a request with `windowSelector == "app:Safari"`; a numeric `window=42` still gives `windowId == 42`.

**Verify**: `timeout 300 swift test --filter CommandTextTests` → the title test fails.

### Step 2: Refuse it

In `commandRequest(fromURL:)`, after the `guard isWindowSelector(value)`, add `guard !value.hasPrefix("title:") else { return nil }`, with a one-line comment that a URL may come from any web page and ICU has no time limit. (`handle(url:)` already returns silently on a `nil` request; check that it does, and if it does not log anything, add one `Log.write(.warn, "ignored a wm:// URL with a title: selector", source: "url")` in `Controller.handle(url:)` — that is the only change allowed outside the files listed, and only if it is a one-liner.)

**Verify**: `timeout 300 swift test --filter CommandTextTests` → all pass.

### Step 3: Compile once

In `window(matching:)`, build the regex once: `guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }`, then filter with `regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil`. Invalid patterns return `nil` (before: `range(of:)` also finds nothing for an invalid pattern). Keep the rest of the function.

**Verify**: `swift build` → ok; `timeout 300 swift test` → all pass.

### Step 4: Docs

In `url-scheme.md`, where the `window` query parameter is described, say that `title:` is not accepted in a URL (use `app:`, `mark:`, `pid:` or an id). If the page does not describe `window=` at all, add one sentence to the nearest list of query parameters.

**Verify**: `grep -n 'title' docs/src/content/docs/url-scheme.md` → shows the new sentence.

## Test plan

Steps 1 and 2. The `NSRegularExpression` change has no unit test (the function is in `App`); verify manually with `wm --window 'title:^Doc' focus mark x` style commands if the app runs, and say so if you could not.

## Done criteria

- [ ] `timeout 300 swift test` exits 0 with the new tests.
- [ ] `grep -n 'regularExpression' Sources/App/WindowManager.swift` finds nothing in `window(matching:)`.
- [ ] Only in-scope files changed.
- [ ] `plans/README.md` status row updated.

## STOP conditions

- Docs or tests show that `window=title:` over URLs is a documented, supported feature (then the maintainer must decide; report instead of removing it).
- `commandRequest(fromURL:)` or `window(matching:)` differ from the excerpts.

## Maintenance notes

- Users who relied on `title:` in URLs now get a silent no-op. Mention it in the release notes.
- Reviewer: the CLI and Lua paths still accept `title:`; a hostile pattern there is the user's own doing.
