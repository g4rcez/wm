# Plan 012: Update the vendored Lua to the latest 5.4.x patch, and write down how

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md` — unless a reviewer dispatched you and told you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat cabd7ca..HEAD -- Sources/CLua legal/THIRD_PARTY.md Package.swift`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW (a patch release has no API change; the Scripting tests exercise the interpreter)
- **Depends on**: 001 (so CI runs the Scripting tests)
- **Category**: migration
- **Planned at**: commit `cabd7ca`, 2026-11-22

## Why this matters

wm embeds Lua 5.4.7 and runs the user's whole config in it. Patch releases fix interpreter bugs. The auditor believes 5.4.8 exists, but that is from memory and was not checked: the first step is to find the real latest 5.4.x. Nothing in the repo records the update procedure, so each update is rediscovered.

## Current state

- `Package.swift`: `.target(name: "CLua", cSettings: [.define("LUA_USE_MACOSX")])`, with the comment "Vendored Lua 5.4.7 (MIT). Library sources only: lua.c and luac.c are left out."
- `Sources/CLua/` holds the `.c` and `.h` files of the Lua `src/` directory; the public headers are in `Sources/CLua/include/` (4 files, including `lua.h` and `luaconf.h`). Version macros in `Sources/CLua/include/lua.h:20-24`: `LUA_VERSION_RELEASE "7"` and `LUA_VERSION_RELEASE_NUM (LUA_VERSION_NUM * 100 + 7)`, copyright line `1994-2024`.
- `legal/THIRD_PARTY.md` says: "Lua 5.4.7 (vendored in `Sources/CLua`) ... Source: https://www.lua.org/ftp/lua-5.4.7.tar.gz (SHA-256 `9fbf5e28ef86c69858f6d3d34eccc32e911c1a28b4120ff3e84aaa70cfbf1e30`). `lua.c` and `luac.c` are not included. Other files are unchanged."
- The Lua host is `Sources/Scripting/LuaState.swift` (`luaL_openlibs`, an instruction-count hook) and is tested in `Tests/ScriptingTests`.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `swift build` | `Build complete!` |
| Scripting tests | `timeout 300 swift test --filter ScriptingTests` | all pass |
| All tests | `timeout 300 swift test` | all pass |

## Scope

**In scope**: `Sources/CLua/**`, `legal/THIRD_PARTY.md`, the vendoring comment in `Package.swift`.

**Out of scope**: `Sources/Scripting`, any change to the Lua sources other than replacing them with the upstream files, switching to a system Lua.

## Git workflow

- Branch `advisor/012-lua-patch`. Commit: `build(lua): update the vendored Lua to <version>` with the old and new version in the body. Explicit paths. Never run `git config`. Do NOT push.

## Steps

### Step 1: Find the real latest 5.4.x

Open https://www.lua.org/ftp/ (or `curl -sI` on candidate tarballs). Note the highest `lua-5.4.N.tar.gz` and the SHA-256 that lua.org publishes for it on its download page. If the highest is 5.4.7 (the current one), the plan is done: report "already latest" and mark it DONE.

### Step 2: Fetch and verify, in a new empty directory

Download the tarball into a NEW EMPTY directory (for example from `mktemp -d`), not into the repo, and never run anything from inside it. `shasum -a 256 lua-5.4.N.tar.gz` must equal the published hash; if it does not, STOP. Extract there with `tar -xzf`.

### Step 3: Replace the files

Compare the file lists: `ls <extracted>/lua-5.4.N/src` against `ls Sources/CLua Sources/CLua/include`. Rules: copy every `.c` and `.h` file from upstream `src/`, except `lua.c` and `luac.c`, to `Sources/CLua/`, and put the headers that are in `Sources/CLua/include/` now (the same four names) into `include/` instead (and remove the duplicates from `Sources/CLua/` if the current layout does that; check with `git ls-files Sources/CLua | head -80` first and keep the same layout). Before overwriting, run `git diff --no-index` between the old and new file for `luaconf.h`: if the vendored one has local changes beyond upstream 5.4.7, STOP and report them.

**Verify**: `grep -n 'LUA_VERSION_RELEASE\b' Sources/CLua/include/lua.h` → the new number; `swift build` → `Build complete!`; `timeout 300 swift test` → all pass.

### Step 4: Record it

Update `legal/THIRD_PARTY.md` (version, URL, SHA-256, copyright years if they changed) and the comment in `Package.swift`. Add a short "Updating Lua" section to `legal/THIRD_PARTY.md` with the steps above (find the version, check the hash, copy `src` without `lua.c`/`luac.c`, headers to `include/`, rebuild, run the tests).

**Verify**: `grep -rn '5.4.7' Sources Package.swift legal` → no matches except history you deliberately kept.

## Test plan

The existing Scripting tests are the regression net. No new tests.

## Done criteria

- [ ] `timeout 300 swift test` exits 0.
- [ ] `lua.h` shows the new release; `THIRD_PARTY.md` has the new version and hash.
- [ ] `git status` shows only `Sources/CLua`, `legal/THIRD_PARTY.md` and `Package.swift`.
- [ ] `plans/README.md` status row updated.

## STOP conditions

- The published hash does not match the download.
- Network access is not available (report; the plan stays TODO).
- `luaconf.h` or another vendored file has local modifications.
- Any test that passed before fails after the update.

## Maintenance notes

- The downloaded tarball is untrusted data: it stays outside the repo and only its `.c`/`.h` files are copied.
- Reviewer: skim the upstream release notes for behaviour changes that could affect user configs.
