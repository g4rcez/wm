import CoreGraphics
import Foundation

/// Where the windows of an app were when the app quit, for a while. An app that comes back (an update, a crash, a quit and an
/// open) restores its windows as new windows, with new ids: without this they would open on the workspace that shows then,
/// which looks like wm moved them. A window of the same app that opens again takes the place of the closed one with its title,
/// else the first closed one.
///
/// Only a window from a new process of the app counts: a window that the same process opens (Cmd-N after closing a document)
/// is a new window, and opens where the user is.
public struct RecentlyClosed: Sendable {
    public struct Place: Sendable, Equatable {
        public var bundleID: String
        public var pid: pid_t
        public var title: String
        public var workspace: String
        public var floating: Bool
        public var floatFrame: CGRect?

        public init(bundleID: String, pid: pid_t, title: String, workspace: String, floating: Bool, floatFrame: CGRect?) {
            self.bundleID = bundleID
            self.pid = pid
            self.title = title
            self.workspace = workspace
            self.floating = floating
            self.floatFrame = floatFrame
        }
    }

    /// How long a place waits for its app to come back, in seconds: an update can take minutes.
    public static let keep: TimeInterval = 300

    private var places: [(place: Place, closed: TimeInterval, order: Int)] = []
    private var counter = 0

    public init() {}

    public mutating func add(_ place: Place, now: TimeInterval) {
        prune(now)
        counter += 1
        places.append((place, now, counter))
    }

    /// The place of a closed window that a new window of `bundleID` from process `pid` takes, and that place is used up.
    public mutating func take(bundleID: String, pid: pid_t, title: String, now: TimeInterval) -> Place? {
        prune(now)
        let candidates = places.enumerated().compactMap { index, entry -> RestoreCandidate? in
            guard entry.place.bundleID == bundleID, entry.place.pid != pid else { return nil }
            return RestoreCandidate(key: index, bundleID: bundleID, title: entry.place.title, order: entry.order)
        }
        guard let best = bestRestoreMatch(bundleID: bundleID, title: title, among: candidates) else { return nil }
        return places.remove(at: best.key).place
    }

    private mutating func prune(_ now: TimeInterval) {
        places.removeAll { now - $0.closed > Self.keep }
    }
}
