import Foundation

/// The process that listens on the daemon socket, or nil when none does. The kernel says it, so it works with a daemon of
/// any version.
public func daemonProcessID(socketPath: String = defaultSocketPath()) -> pid_t? {
    guard let connection = try? connectToServer(path: socketPath) else { return nil }
    defer { close(connection) }
    var pid: pid_t = 0
    var size = socklen_t(MemoryLayout<pid_t>.size)
    guard getsockopt(connection, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0, pid > 0 else { return nil }
    return pid
}

/// Runs `attempt` until it returns true. False when the time is up first.
public func retry(timeoutSeconds: Double, intervalSeconds: Double = 0.1, _ attempt: () -> Bool) -> Bool {
    let deadline = Date(timeIntervalSinceNow: timeoutSeconds)
    while !attempt() {
        if Date() >= deadline { return false }
        Thread.sleep(forTimeInterval: intervalSeconds)
    }
    return true
}

/// Waits until the process is gone. False when it still runs after the timeout.
public func waitForExit(_ pid: pid_t, timeoutSeconds: Double) -> Bool {
    // Signal 0 sends nothing: it only asks whether the process exists.
    retry(timeoutSeconds: timeoutSeconds) { kill(pid, 0) != 0 && errno == ESRCH }
}

public enum DaemonStop: Equatable, Sendable {
    case notRunning
    case stopped
    case stillRunning(pid_t)
}

/// Asks the daemon to quit and waits until its process has ended. The daemon removes its socket first and then puts the
/// windows back, so a socket that no longer answers does not mean that wm has quit, and macOS cannot open wm again until
/// it has.
public func stopDaemon(socketPath: String = defaultSocketPath(), timeoutSeconds: Double = 10) -> DaemonStop {
    guard let pid = daemonProcessID(socketPath: socketPath) else { return .notRunning }
    // No answer is not the end of it: the wait below says whether the process went away.
    _ = try? sendRequest(ClientRequest(args: ["daemon", "stop"]), socketPath: socketPath)
    return waitForExit(pid, timeoutSeconds: timeoutSeconds) ? .stopped : .stillRunning(pid)
}
