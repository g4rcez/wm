import Foundation

/// Which apps ask for attention. macOS has no public way to see another app's request for attention (the Dock bounce), but the Dock
/// shows a badge for the apps that have something new (Mail, Slack, Messages), and wm can read it. An app is urgent when its badge
/// appears or grows while you are in another app, and is not urgent any more when you go to it or its badge goes away.
///
/// The first reading only sets the starting point: the unread count that an app had before wm started is not new.
public struct UrgentTracker: Sendable {
    public struct Alert: Equatable, Sendable {
        public var app: String
        public var badge: String

        public init(app: String, badge: String) {
            self.app = app
            self.badge = badge
        }
    }

    private var counts: [String: Int] = [:]
    private var urgent: [String] = []
    private var primed = false

    public init() {}

    /// The apps that ask for attention, the one that asked last first.
    public var urgentApps: [String] { urgent }

    public func isUrgent(_ app: String) -> Bool { urgent.contains { $0.caseInsensitiveCompare(app) == .orderedSame } }

    /// The value of a badge: its number, or 1 for a text without one (a dot).
    public static func count(of badge: String) -> Int {
        Int(badge.trimmingCharacters(in: .whitespaces)) ?? 1
    }

    /// Takes a reading of the Dock: the badge text of each app that has one. `frontmost` is the app that you are in now: its badge
    /// is not new to you. Returns the apps that became urgent with this reading.
    public mutating func update(badges: [String: String], frontmost: String?) -> [Alert] {
        var alerts: [Alert] = []
        var next: [String: Int] = [:]
        for (app, badge) in badges.sorted(by: { $0.key < $1.key }) {
            let now = Self.count(of: badge)
            next[app] = now
            let before = counts[app] ?? 0
            let inFront = frontmost.map { $0.caseInsensitiveCompare(app) == .orderedSame } ?? false
            if primed, now > before, !inFront {
                urgent.removeAll { $0.caseInsensitiveCompare(app) == .orderedSame }
                urgent.insert(app, at: 0)
                alerts.append(Alert(app: app, badge: badge))
            }
        }
        // A badge that went away: the app has nothing new, so it does not ask for attention.
        urgent.removeAll { app in !next.keys.contains { $0.caseInsensitiveCompare(app) == .orderedSame } }
        counts = next
        primed = true
        return alerts
    }

    /// You went to the app: it does not ask for attention any more. `names` are the ways to call it (its bundle id and its name).
    public mutating func focused(_ names: String...) {
        urgent.removeAll { app in names.contains { $0.caseInsensitiveCompare(app) == .orderedSame } }
    }
}
