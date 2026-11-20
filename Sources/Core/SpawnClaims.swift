import Foundation

/// Options that wait for the window of a command that `wm exec` started. A new window takes the first claim that fits it:
/// the window belongs to the process that was started (or one of its children), or to the app that the claim names. The
/// second way is for `open -a Notes` and for an app that hands the work to a copy that already runs, whose windows are not
/// children of the shell. A claim that nobody takes in time expires.
public struct SpawnClaims<Value: Sendable>: Sendable {
    /// What a claim waits for. `app` is a bundle id or an app name, compared ignoring case.
    public struct Claim: Sendable {
        public var id: Int
        public var pid: Int32
        public var app: String?
        public var expires: TimeInterval
        public var value: Value
    }

    private var pending: [Claim] = []
    private var nextID = 0

    public init() {}

    public var count: Int { pending.count }

    /// Adds a claim that lasts `timeout` seconds from `now`. The result is its id, for `expire(id:)`.
    @discardableResult
    public mutating func add(pid: Int32, app: String?, value: Value, timeout: TimeInterval, now: TimeInterval) -> Int {
        nextID += 1
        pending.append(Claim(id: nextID, pid: pid, app: app, expires: now + timeout, value: value))
        return nextID
    }

    /// Takes the first claim that fits a window of the process `pid` of this app, and drops the claims that ran out. A claim
    /// that fits by process wins over an older one that fits by app only.
    public mutating func take(
        pid: Int32, bundleID: String, appName: String, now: TimeInterval, isDescendant: (_ pid: Int32, _ of: Int32) -> Bool
    ) -> Value? {
        pending.removeAll { $0.expires < now }
        let index = pending.firstIndex { isDescendant(pid, $0.pid) }
            ?? pending.firstIndex { claim in
                claim.app.map { $0.caseInsensitiveCompare(bundleID) == .orderedSame || $0.caseInsensitiveCompare(appName) == .orderedSame } ?? false
            }
        return index.map { pending.remove(at: $0).value }
    }

    /// Drops the claim `id` if it is still waiting. The result tells whether it was.
    @discardableResult
    public mutating func expire(id: Int) -> Bool {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return false }
        pending.remove(at: index)
        return true
    }
}
