# Plan 001: Run the build, the tests and the docs build in CI on every push and pull request

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md` — unless a reviewer dispatched you and told you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat cabd7ca..HEAD -- Makefile docs/package.json .github`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx
- **Planned at**: commit `cabd7ca`, 2026-11-22

## Why this matters

`wm` has about 940 fast unit tests (Core, Common, Scripting, Cheatsheet) and a docs site, but nothing runs them except the maintainer's machine. A red test, a command missing from the docs, or a broken docs build can land on `main` unnoticed. CI is also the gate that every later plan in this directory relies on.

## Current state

- There is no `.github/` directory (verify: `ls .github` fails).
- `Makefile:33-34`: `make test` runs `$(if $(TIMEOUT),$(TIMEOUT) 300 )swift test`.
- `Package.swift:1` is `// swift-tools-version: 6.2` and `platforms: [.macOS(.v14)]`. `make deps` fails when `swift --version` is older than 6.2.
- Test targets: `CheatsheetTests`, `CommonTests`, `CoreTests`, `ScriptingTests` (Swift Testing). `App` and `Platform` have no tests, but they must still compile: `swift build` builds them.
- Docs: `docs/package.json` scripts are `dev`, `build` (`astro build`), `preview`. It has a `pnpm-lock.yaml`. Dependencies are exact pins (`astro 7.4.5`, `motion 14.14.0`). There is no `packageManager` or `engines` field.
- Commit style: conventional commits (`build(manifest): declare Common as a dependency of Scripting`, `docs(keys): ...`).

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Build | `swift build` | `Build complete!` |
| Tests | `timeout 300 swift test` | all suites pass |
| Docs | `cd docs && pnpm install --frozen-lockfile && pnpm build` | exit 0 |
| Workflow syntax | `gh workflow list` (after push) or read the file | file parses as YAML |

## Scope

**In scope**: `.github/workflows/ci.yml` (create).

**Out of scope**: any Swift source, `Makefile`, `build-app.sh`, the docs content, release or notarization automation (a different, larger piece of work), Dependabot or Renovate config.

## Git workflow

- Branch `advisor/001-add-ci`. One commit: `build(ci): run the build, the tests and the docs build on every push`.
- Use the git identity that is already configured. Never run `git config` to change it.
- Do NOT push or open a PR unless the operator told you to.

## Steps

### Step 1: Write the workflow

Create `.github/workflows/ci.yml` with two jobs, triggered on `push` to `main` and on `pull_request`:

1. `swift`: `runs-on` a macOS runner that has Swift 6.2 or newer (Xcode 26). Steps: `actions/checkout@v4`, select the Xcode that ships Swift 6.2 (for example with `sudo xcode-select -s /Applications/Xcode_26.app`; look at the runner image's installed Xcode list to pick the exact name), print `swift --version`, then `swift build`, then `timeout 300 swift test`. Note: macOS runners have no `timeout`; use `gtimeout` from coreutils (`brew install coreutils`) or `make test`, which already falls back to no timeout. Prefer `make test` and set a job-level `timeout-minutes: 15`.
2. `docs`: `runs-on: ubuntu-latest`. Steps: `actions/checkout@v4`, `pnpm/action-setup@v4` (version 9 or the version that wrote `pnpm-lock.yaml`: read the first line of `docs/pnpm-lock.yaml`, `lockfileVersion`), `actions/setup-node@v4` with `node-version: 22`, then in `docs/`: `pnpm install --frozen-lockfile` and `pnpm build`.

Pin third-party actions to a major version tag as above. Set `permissions: contents: read` at the top.

**Verify**: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml'))"` → exit 0. If `yamllint` or `actionlint` is installed, run it too.

### Step 2: Confirm the commands the workflow runs also pass locally

**Verify**: `swift build` → `Build complete!`; `timeout 300 swift test` → all pass; `cd docs && pnpm build` → exit 0 (skip the docs one if `docs/node_modules` is missing and there is no network; say so in your report).

## Test plan

There is no unit test for a workflow. The proof is the first CI run. If the operator allows a push to a branch, check `gh run list --branch advisor/001-add-ci` shows both jobs green.

## Done criteria

- [ ] `.github/workflows/ci.yml` exists, parses as YAML, and has the jobs `swift` and `docs`.
- [ ] `swift build` and `timeout 300 swift test` pass locally.
- [ ] No file other than `.github/workflows/ci.yml` (and the status row) changed (`git status`).
- [ ] `plans/README.md` status row updated.

## STOP conditions

- No available GitHub-hosted macOS runner image has Swift 6.2 or newer. Report which images you checked; do not lower `swift-tools-version`.
- The local `swift build` or `swift test` already fails before you change anything. Report the failure; do not fix source in this plan.
- The workflow would need a secret or a signing certificate.

## Maintenance notes

- When the repository starts to ship release builds, add a tag-triggered job later (see the direction item "release pipeline" in the audit).
- Review: the Xcode path pin is the fragile part; runner images rename Xcode folders.
- Deferred: a formatter or linter job (there is no config yet), and Dependabot for `docs/` and the actions.
