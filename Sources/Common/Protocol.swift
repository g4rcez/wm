import Foundation

/// One command line, as typed after `wm` (or taken from a `wm://` URL or a Lua `wm.dispatch` call).
public struct ClientRequest: Codable, Sendable, Equatable {
    public var args: [String]
    /// The window the command is about (`wm --window <id> <command>`). Without it the focused window is used.
    public var windowId: UInt32?
    /// The window as a selector instead of an id: `focused`, `app:<name>`, `title:<regex>` or `pid:<n>`. The daemon
    /// turns it into an id. Not used together with `windowId`.
    public var windowSelector: String?

    public init(args: [String], windowId: UInt32? = nil, windowSelector: String? = nil) {
        self.args = args
        self.windowId = windowId
        self.windowSelector = windowSelector
    }
}

public struct ServerAnswer: Codable, Sendable, Equatable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32, stdout: String = "", stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// The socket lives in the per-user temporary directory (mode 0700), so other users cannot reach or squat it.
public func defaultSocketPath() -> String {
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    let length = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
    let directory = length > 0
        ? String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        : "/tmp/"
    return directory + "wm.sock"
}

/// The events that `wm subscribe` and `wm.on` can name, as they appear in the `event` field of a line.
public let subscribableEvents = [
    "window_open", "window_close", "window_focus", "window_title", "window_floating", "window_fullscreen", "window_moved",
    "workspace_changed", "special_changed", "monitor_changed", "displays_changed", "layout_changed", "mode_changed", "config_reloaded",
    "window_swallow", "window_unswallow", "window_urgent",
]
