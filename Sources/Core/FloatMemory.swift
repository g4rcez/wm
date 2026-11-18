import Foundation

/// Where a floating window was when it closed.
public struct LastFloatFrame: Codable, Equatable, Sendable {
    /// The bundle id of the app.
    public var app: String
    public var title: String
    /// In the work area of the monitor that showed the window.
    public var frame: RelativeFrame
    /// The name of that monitor. The window opens on the monitor where it was, when that monitor is still there.
    public var monitor: String?

    public init(app: String, title: String, frame: RelativeFrame, monitor: String? = nil) {
        self.app = app
        self.title = title
        self.frame = frame
        self.monitor = monitor
    }
}

/// The last place of the floating windows that closed, so that the next window of the app opens there. Unlike `WindowMemory`
/// (`window remember`) nobody has to ask for it: every floating window that closes is kept.
public struct FloatMemory: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    /// The oldest places are dropped after this many.
    public static let limit = 200

    public var version = currentVersion
    /// The oldest first.
    public var frames: [LastFloatFrame] = []

    public init(frames: [LastFloatFrame] = []) {
        self.frames = frames
    }

    /// Keeps the place of a window that closed, in place of the one of the same app and title.
    public mutating func record(_ entry: LastFloatFrame) {
        frames.removeAll { $0.app == entry.app && $0.title == entry.title }
        frames.append(entry)
        if frames.count > Self.limit { frames.removeFirst(frames.count - Self.limit) }
    }

    /// The place for a window that opens: the one of a window with the same app and exactly the same title, else the last one
    /// of the app (a Finder window that opens at the place where the last Finder window closed).
    public func last(app: String, title: String) -> LastFloatFrame? {
        let ofApp = frames.filter { $0.app == app }
        return ofApp.first { $0.title == title } ?? ofApp.last
    }
}
