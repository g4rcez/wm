import Foundation

/// A window of the saved state that has not found its window yet.
public struct RestoreCandidate: Sendable, Equatable {
    /// Names the candidate to the caller.
    public var key: Int
    public var bundleID: String
    public var title: String
    /// Its place in the saved layout: the smaller it is, the earlier it goes.
    public var order: Int

    public init(key: Int, bundleID: String, title: String, order: Int) {
        self.key = key
        self.bundleID = bundleID
        self.title = title
        self.order = order
    }
}

/// After a reboot the window ids of the saved state mean nothing, so a window that opens finds its old place by its app and
/// its title. Among the candidates of the same app, one with the same title wins; else the one that was first in the saved
/// layout. `nil` when no candidate has the app.
public func bestRestoreMatch(bundleID: String, title: String, among candidates: [RestoreCandidate]) -> RestoreCandidate? {
    let ofApp = candidates.filter { $0.bundleID == bundleID }
    let sameTitle = ofApp.filter { !title.isEmpty && $0.title == title }
    return (sameTitle.isEmpty ? ofApp : sameTitle).min { ($0.order, $0.key) < ($1.order, $1.key) }
}

/// The id that stands for a saved window until the real window opens. It lies above every id that macOS hands out, so it
/// never meets the id of another window.
public enum Placeholder {
    private static let base: WindowID = 0xF000_0000

    public static func id(for saved: WindowID) -> WindowID { base | (saved & 0x0FFF_FFFF) }

    public static func isPlaceholder(_ id: WindowID) -> Bool { id >= base }
}
