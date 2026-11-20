import Foundation

/// Window swallowing: a program that you start in a terminal (mpv, an editor with a window of its own) takes the place of the
/// terminal window, and the terminal window comes back when the program's window closes.
///
/// This type only decides which terminal window is the host of a new window. A terminal runs its shells as children of one
/// process for all its windows, so the process tree says which terminal *app* started the program, not which window. wm takes the
/// window that had the focus when the program's window opened (the one you typed the command in), or else the terminal window
/// that was focused last.
public enum Swallow {
    public struct Candidate: Sendable, Equatable {
        public var id: WindowID
        public var pid: Int32
        public var bundleID: String
        public var appName: String

        public init(id: WindowID, pid: Int32, bundleID: String, appName: String) {
            self.id = id
            self.pid = pid
            self.bundleID = bundleID
            self.appName = appName
        }
    }

    /// Whether `bundleID` or `appName` is in `list`, ignoring case.
    public static func listed(_ list: [String], bundleID: String, appName: String) -> Bool {
        list.contains { $0.caseInsensitiveCompare(bundleID) == .orderedSame || $0.caseInsensitiveCompare(appName) == .orderedSame }
    }

    /// The terminal window that a new window of this app takes the place of, or `nil` for a window that is not swallowed.
    /// `ancestors` (lazy: it reads the process table) are the parent, grandparent and so on of the new window's process.
    /// `candidates` are the windows that can be swallowed (the caller leaves out windows that are swallowed already, minimized
    /// or in fullscreen), the most recently used first. A terminal, or an app in `exceptions`, never swallows.
    public static func host(
        bundleID: String, appName: String, ancestors: () -> [Int32], candidates: [Candidate], focused: WindowID?,
        settings: SwallowSettings
    ) -> WindowID? {
        guard settings.enabled else { return nil }
        if listed(settings.terminals, bundleID: bundleID, appName: appName) || listed(settings.exceptions, bundleID: bundleID, appName: appName) {
            return nil
        }
        let terminals = candidates.filter { listed(settings.terminals, bundleID: $0.bundleID, appName: $0.appName) }
        guard !terminals.isEmpty else { return nil }
        let chain = Set(ancestors())
        let parents = terminals.filter { chain.contains($0.pid) }
        if let focused, parents.contains(where: { $0.id == focused }) { return focused }
        return parents.first?.id
    }
}
