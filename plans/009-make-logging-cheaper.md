# Plan 009: Write log records through one open file handle, with an optional minimum level

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md` — unless a reviewer dispatched you and told you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat cabd7ca..HEAD -- Sources/Common/Log.swift Tests/CommonTests/LogTests.swift Sources/Common/CommandSpec.swift`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: perf
- **Planned at**: commit `cabd7ca`, 2026-11-22

## Why this matters

Every `Log.write` (42 call sites in `Sources`) creates the log directory, stats the file, checks it exists, opens a `FileHandle`, seeks, writes and closes it, all under one global lock, and also writes to stderr. Threads that log (the AX threads, the main thread, the socket queue) therefore queue behind a burst of syscalls per line. There is no level filter, so debug lines cost the same as errors.

## Current state

`Sources/Common/Log.swift:100-124` (`LogFile.append`):

```swift
    private static let lock = NSLock()
    static func rotatedURL(of url: URL) -> URL { url.appendingPathExtension("1") }

    public static func append(_ record: LogRecord, to url: URL = defaultLogURL(), maxBytes: Int = maxBytes) {
        lock.lock()
        defer { lock.unlock() }
        let files = FileManager.default
        do {
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = try? files.attributesOfItem(atPath: url.path)[.size] as? Int, size >= maxBytes {
                try? files.removeItem(at: rotatedURL(of: url))
                try files.moveItem(at: url, to: rotatedURL(of: url))
            }
            if !files.fileExists(atPath: url.path) {
                files.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((record.jsonLine + "\n").utf8))
        } catch { /* a log that cannot be written must not stop the daemon */ }
    }
```

`Sources/Common/Log.swift:160-167`:

```swift
public enum Log {
    public static func write(_ level: LogLevel, _ message: String, source: String? = nil, prefix: String = "wm") {
        FileHandle.standardError.write(Data("\(prefix): \(message)\n".utf8))
        LogFile.append(LogRecord(level: level, message: message, source: source))
    }
}
```

`LogLevel` (`Log.swift:4`): `case debug, info, warn, error`, `CaseIterable`. The log is `$XDG_STATE_HOME/wm/wm.log` (else `~/.local/state/wm/wm.log`), rotated to `wm.log.1` at 5 MiB; `wm logs` reads it and must keep working while the daemon runs and when it does not. `Tests/CommonTests/LogTests.swift` already tests append, rotation and reading with a temporary directory (`tempLog()`); extend that file.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Focused tests | `timeout 300 swift test --filter LogTests` | all pass |
| All tests | `timeout 300 swift test` | all pass |
| Build | `swift build` | `Build complete!` |

## Scope

**In scope**: `Sources/Common/Log.swift`, `Tests/CommonTests/LogTests.swift`, `Sources/Common/CommandSpec.swift` (the `environmentRows` and the `logs` details, only for the new variable), `docs/src/content/docs/cli.md` (the environment section, if there is one).

**Out of scope**: the record format, rotation size, the `wm logs` reader, the 42 call sites, stderr output.

## Git workflow

- Branch `advisor/009-cheaper-logging`. Commits: `perf(log): keep the log file open between records`, `feat(log): WM_LOG_LEVEL sets the lowest level written to the file`. Explicit paths. Never run `git config`. Do NOT push.

## Steps

### Step 1: Characterization tests

In `LogTests.swift`, make sure tests exist for: a record appended to a new path creates the file with mode 0600; a second append adds a line; a file at `maxBytes` rotates to `.1` and the new record goes to a fresh file; deleting the file between two appends makes the next append recreate it (this is the behaviour a long-lived handle can break). Add the ones that are missing.

**Verify**: `timeout 300 swift test --filter LogTests` → all pass on the unchanged code.

### Step 2: Keep a handle per path

Under the existing lock, keep `private static var open: (url: URL, handle: FileHandle)?`. On `append`: if the cached URL differs, close and reopen. Otherwise check that the file at the path is still the one the handle writes to (compare `stat` inode of the path with `fstat` of the handle's descriptor; a missing path or different inode means reopen), and rotate when the size is at the limit (use `handle.offsetInFile` after writes instead of stat-ing the path every time; stat only when the cached offset passes `maxBytes`). Create the directory only when opening. Keep the permissions 0600 and the swallow-all-errors behaviour.

**Verify**: `timeout 300 swift test --filter LogTests` → all pass, including the delete-and-recreate test.

### Step 3: `WM_LOG_LEVEL`

Read `WM_LOG_LEVEL` (`debug|info|warn|error`, case-insensitive) once, lazily, into a static. `Log.write` skips `LogFile.append` for records below it. The default stays `debug` (nothing is dropped, so existing behaviour is unchanged). stderr output is unchanged. Add a test of the parsing function (make it a small pure function taking the environment dictionary) with valid, invalid (falls back to `debug`) and empty values.

Add `WM_LOG_LEVEL` to `environmentRows` in `CommandSpec.swift` ("The lowest level that the daemon writes to the log file: debug (default), info, warn or error.") and to the environment list in `cli.md` if it lists the other variables.

**Verify**: `timeout 300 swift test` → all pass; `swift run wm help | grep WM_LOG_LEVEL` → shows the row.

## Test plan

Steps 1-3. The unit tests use temporary directories like the existing ones.

## Done criteria

- [ ] `timeout 300 swift test` exits 0.
- [ ] `grep -n 'FileHandle(forWritingTo' Sources/Common/Log.swift` shows one site, in the open path only.
- [ ] `wm help` lists `WM_LOG_LEVEL`.
- [ ] Only in-scope files changed; `plans/README.md` updated.

## STOP conditions

- The handle approach cannot pass the delete-and-recreate or rotation test after two attempts: stop and report; keep step 3 (it is independent).
- `LogFile.append` is used from other targets with a custom `url` in a way that breaks a single cached handle (grep `LogFile.append`).

## Maintenance notes

- A cached handle holds the file open while `wm logs` reads it: fine on macOS. Rotation moves the file while the handle is open; the code must close it first.
- Deferred: building the JSON line without a new `JSONEncoder` per field (`Log.swift:60-68`).
