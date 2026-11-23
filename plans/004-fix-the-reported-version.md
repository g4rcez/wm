# Plan 004: `wm version` reports the released version, and a check keeps it in line with the tags

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md` — unless a reviewer dispatched you and told you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat cabd7ca..HEAD -- Sources/Common/Version.swift Makefile Tests/CommonTests`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx
- **Planned at**: commit `cabd7ca`, 2026-11-22

## Why this matters

`Sources/Common/Version.swift` says `0.1.0`, but the tags `v0.1.1` and `v0.2.0` exist, and both tagged commits still contain `0.1.0` (verified with `git show v0.2.0:Sources/Common/Version.swift`). Bug reports from a 0.2.0 build say 0.1.0, and `wm doctor` compares a running daemon with this constant. Nothing stops it from drifting again.

## Current state

- `Sources/Common/Version.swift`: `public let wmVersion = "0.1.0"`, one line.
- Used by `wm version` (`Sources/Cli/main.swift`, prints `wm \(wmVersion)`), by `wm doctor` (compares the running daemon's version, and warns "runs version X, and this wm is Y" with the hint to restart the daemon), and by `Onboarding.markDone` (writes it to the marker file; `Onboarding.isDone` only checks that the file exists, so a version change does NOT show the setup window again — see the comment at the top of `Sources/Common/Onboarding.swift`).
- Tags: `git tag` → `v0.1.0`, `v0.1.1`, `v0.2.0`. HEAD is 8+ commits after `v0.2.0`.
- Makefile style: `.PHONY` list at line 14, targets documented in `help`.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Tests | `timeout 300 swift test --filter OnboardingTests` and then `timeout 300 swift test` | pass |
| Version | `swift run wm version` | `wm 0.2.0` |
| New check | `make version-check` | exit 0 when the constant equals the latest tag |

## Scope

**In scope**: `Sources/Common/Version.swift`, `Makefile`, `Tests/CommonTests/VersionTests.swift` (create).

**Out of scope**: release automation, the Homebrew formula (another repository), changelogs, `build-app.sh`.

## Git workflow

- Branch `advisor/004-version`. Commit: `fix(version): report 0.2.0, and add a check against the git tag`. Explicit paths. Never run `git config`. Do NOT push or tag.

## Steps

### Step 1: Set the constant

Change `Version.swift` to `public let wmVersion = "0.2.0"` (HEAD is a development build after the `v0.2.0` tag; the next release bumps it). Keep the file one line.

**Verify**: `swift run wm version` → `wm 0.2.0`.

### Step 2: A format test

Create `Tests/CommonTests/VersionTests.swift` (Swift Testing, same imports as `Tests/CommonTests/OnboardingTests.swift`): a test that `wmVersion` matches the regex `^\d+\.\d+\.\d+$`.

**Verify**: `timeout 300 swift test --filter VersionTests` → pass.

### Step 3: A tag check in the Makefile

Add `version-check` to `.PHONY`, to `help`, and as a target:

```make
version-check:
	@declared="$$(sed -n 's/.*wmVersion = "\(.*\)".*/\1/p' Sources/Common/Version.swift)"; \
	tag="$$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')"; \
	[ "$$declared" = "$$tag" ] || { echo "error: Version.swift says $$declared, the latest tag is $$tag"; exit 1; }; \
	echo "version $$declared: ok"
```

(Tabs for the recipe lines, as the rest of the Makefile.)

**Verify**: `make version-check` → `version 0.2.0: ok`, exit 0. Then temporarily test the failure path without committing: `sed -i '' 's/0.2.0/0.9.9/' Sources/Common/Version.swift && make version-check; echo $?` → prints the error and `1`; restore with `git checkout Sources/Common/Version.swift` only if you have not yet staged the real change, otherwise re-apply step 1.

## Test plan

`VersionTests` (format). The tag comparison is a Makefile check, verified in step 3.

## Done criteria

- [ ] `swift run wm version` prints `wm 0.2.0`.
- [ ] `make version-check` exits 0, and exits 1 when the constant is wrong.
- [ ] `timeout 300 swift test` exits 0.
- [ ] Only the three in-scope files changed; the failure-path edit is reverted.
- [ ] `plans/README.md` status row updated.

## STOP conditions

- `git tag` shows a newer tag than `v0.2.0`: use that version instead and say so.
- `OnboardingTests` or `DoctorTests` fail after the change (they may hard-code `0.1.0`): fix only that string in those tests, and report it.

## Maintenance notes

- Run `make version-check` right after bumping and tagging; plan 001's CI can call it on tag pushes later.
- After the first release built from this change, a user with an old daemon running will see the `doctor` warning "runs version 0.1.0, and this wm is 0.2.0". That is correct and is the intended use of that check.
