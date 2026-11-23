# Plan 011: `make install` and `build-app.sh` replace the app only after the new one is built and signed

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md` — unless a reviewer dispatched you and told you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat cabd7ca..HEAD -- Makefile build-app.sh`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: MED (signing and install paths; a mistake can leave the user without the app)
- **Depends on**: none
- **Category**: dx
- **Planned at**: commit `cabd7ca`, 2026-11-22

## Why this matters

Both scripts delete the working app before the replacement exists. `build-app.sh` stops the running daemon and runs `rm -rf .build/wm.app`, then copies the pieces in and signs them; if a `cp` or `codesign` fails, wm is stopped and there is no bundle. `make install` runs `rm -rf /Applications/wm.app` before `ditto` and `codesign --verify`; a failed copy or verification leaves the user with no wm at all. Staging the new app first and swapping it in at the end makes a failed install harmless.

## Current state

`build-app.sh` (the whole script is about 70 lines): it runs `swift build -c "$configuration"` twice (the second call only to print `--show-bin-path`), stops a running `wmd` (`wm daemon stop`, then `pkill -x wmd` after 5 seconds), then:

```bash
app=".build/wm.app"
...
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp bundle/Info.plist "$app/Contents/Info.plist"
...
codesign --force --sign "$identity" "$app/Contents/MacOS/wm"
codesign --force --sign "$identity" "$app"
...
if [ -z "${NO_START:-}" ]; then "$app/Contents/MacOS/wm" daemon start; fi
```

`Makefile:58-65` (`install`):

```make
	NO_START=1 CODESIGN_IDENTITY="$(IDENTITY)" ./build-app.sh $(CONFIG)
	rm -rf "$(APP_DIR)/wm.app"
	ditto .build/wm.app "$(APP_DIR)/wm.app"
	codesign --verify --deep --strict "$(APP_DIR)/wm.app"
	@codesign -dr - "$(APP_DIR)/wm.app" 2>&1 | grep 'designated =>' || true
	mkdir -p "$(BIN_DIR)"
	ln -sf "$(APP_DIR)/wm.app/Contents/MacOS/wm" "$(BIN_DIR)/wm"
	"$(APP_DIR)/wm.app/Contents/MacOS/wm" daemon start
```

The Accessibility grant depends on the bundle id plus the signing identity (see the comment block in `build-app.sh`), not on the path, so moving a signed bundle into place keeps it. The Homebrew formula (another repository) calls `build-app.sh` with `NO_STOP=1` and `SWIFT_BUILD_FLAGS`; those variables must keep working.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build the app | `NO_START=1 NO_STOP=1 ./build-app.sh debug` | prints `Built .build/wm.app` |
| Verify the bundle | `codesign --verify --deep --strict .build/wm.app` | exit 0 |
| Dry run | `make -n install` | prints the steps in the new order |

## Scope

**In scope**: `build-app.sh`, `Makefile`.

**Out of scope**: signing identity selection, the Homebrew formula, notarization, adding `clean` or `lint` targets, the icon script.

## Git workflow

- Branch `advisor/011-safe-install`. Commits: `build(app): build the bundle in a staging folder and swap it in at the end`, `build(install): replace the installed app only after the new one is verified`. Explicit paths. Never run `git config`. Do NOT push, and do NOT run `make install` on the user's machine (it replaces `/Applications/wm.app`).

## Steps

### Step 1: Stage in `build-app.sh`

Build into `app=".build/wm.app.new"` (remove only that path at the start), fill and sign it exactly as now. After the last `codesign` and the signature printout succeed, do the swap: stop the daemon only now (move the existing stop block here, after the build and signing), then `rm -rf .build/wm.app && mv .build/wm.app.new .build/wm.app`, then print `Built .build/wm.app` and optionally start. Remove the duplicated `swift build` call by capturing the bin path from `swift build ... --show-bin-path` after the single build (keep `${SWIFT_BUILD_FLAGS:-}`). Keep `NO_START` and `NO_STOP` working.

**Verify**: `NO_START=1 NO_STOP=1 ./build-app.sh debug` → ends with `Built .build/wm.app`; `ls .build/wm.app/Contents/MacOS` → `wm wmd`; `ls -d .build/wm.app.new` → no such file; `codesign --verify --deep --strict .build/wm.app` → exit 0. Failure path: run the script with `CODESIGN_IDENTITY=nonexistent-identity NO_START=1 NO_STOP=1 ./build-app.sh debug` → it fails, and the previous `.build/wm.app` from the line above is still there and still verifies.

### Step 2: Stage in `make install`

Change the recipe to: `ditto .build/wm.app "$(APP_DIR)/wm.app.new"`, `codesign --verify --deep --strict "$(APP_DIR)/wm.app.new"`, then `rm -rf "$(APP_DIR)/wm.app" && mv "$(APP_DIR)/wm.app.new" "$(APP_DIR)/wm.app"`, then the same `codesign -dr`, link and daemon start lines. If the verify fails, `make` stops and the installed app is untouched (and remove the `.new` copy in that case with a `|| { rm -rf ...; exit 1; }` guard).

**Verify**: `make -n install APP_DIR=/tmp/wm-install-test CODESIGN_IDENTITY=x` → shows `ditto ... wm.app.new` before any `rm -rf ".../wm.app"`.

## Test plan

No unit tests for shell. The failure-path run in step 1 is the test: a failed build leaves the old bundle.

## Done criteria

- [ ] Step 1 and step 2 verifications pass.
- [ ] `grep -n 'rm -rf' build-app.sh Makefile` shows the removal of the old app only after the verify steps.
- [ ] `NO_STOP` and `NO_START` still work (`grep -n 'NO_STOP\|NO_START' build-app.sh`).
- [ ] Only `build-app.sh` and `Makefile` changed; `plans/README.md` updated.

## STOP conditions

- You cannot run `build-app.sh` (no Swift toolchain, no signing tool): report, do not guess.
- A step needs a change to the formula's environment variables.
- Moving the signed bundle makes `codesign --verify` fail (then staging in place is not viable; report).

## Maintenance notes

- The swap is not atomic (`rm` then `mv`); a crash between the two leaves no app. `mv` of a directory onto an existing one is not safe, so this is the smallest improvement. Say so in the commit body.
- Reviewer: the daemon must be stopped as late as possible and restarted only on success.
