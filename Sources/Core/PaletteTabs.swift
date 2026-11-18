import Foundation

/// A tab that the palette can switch to: a tab of a browser, a tab of Rex, or a window of tmux.
public struct PaletteTab: Sendable, Equatable {
    /// Where the tab lives, with what its program needs to select it.
    public enum Source: Sendable, Equatable {
        /// The bundle identifier of the browser, and the identifiers that the browser gives to the window and to the tab.
        case browser(bundleID: String, window: String, tab: String)
        case rex(session: String, window: String)
        /// The identifiers of tmux: `$1` and `@3`.
        case tmux(session: String, window: String)
    }

    public var source: Source
    public var title: String
    /// The address of a page, or the session of a terminal tab.
    public var detail: String

    public init(source: Source, title: String, detail: String) {
        self.source = source
        self.title = title
        self.detail = detail
    }
}

/// A terminal that shows a tmux session.
public struct TmuxClient: Sendable, Equatable {
    public var tty: String
    public var pid: Int32
    /// The identifier of the session that the client shows.
    public var session: String

    public init(tty: String, pid: Int32, session: String) {
        self.tty = tty
        self.pid = pid
        self.session = session
    }
}

/// The tabs in what the browser script prints: `[{"id":"1","tabs":[{"id":"2","title":"…","url":"…"}]}]`, one object for each
/// window. Text that is not this JSON gives no tabs.
public func browserTabs(json: String, bundleID: String) -> [PaletteTab] {
    struct Window: Decodable {
        struct Tab: Decodable {
            var id: String
            var title: String
            var url: String
        }

        var id: String
        var tabs: [Tab]
    }
    guard let windows = try? JSONDecoder().decode([Window].self, from: Data(json.utf8)) else { return [] }
    return windows.flatMap { window in
        window.tabs.map {
            PaletteTab(source: .browser(bundleID: bundleID, window: window.id, tab: $0.id), title: $0.title.isEmpty ? $0.url : $0.title, detail: $0.url)
        }
    }
}

/// The identifiers of the sessions in the output of `rex ls --json`.
public func rexSessions(json: String) -> [String] {
    struct Listing: Decodable {
        struct Session: Decodable {
            var session_id: String
        }

        var sessions: [Session]
    }
    return ((try? JSONDecoder().decode(Listing.self, from: Data(json.utf8)))?.sessions ?? []).map(\.session_id)
}

/// The tabs of one session in the output of `rex window ls -s SESSION --json`. The detail is the name of the session.
public func rexTabs(json: String) -> [PaletteTab] {
    struct Session: Decodable {
        struct Window: Decodable {
            var window_id: String
            var label: String
        }

        var session_id: String
        var label: String
        var windows: [Window]
    }
    guard let session = try? JSONDecoder().decode(Session.self, from: Data(json.utf8)) else { return [] }
    return session.windows.map { PaletteTab(source: .rex(session: session.session_id, window: $0.window_id), title: $0.label, detail: session.label) }
}

/// The format for `tmux list-windows -a -F`. The fields have a tab between them, which no name of tmux can hold but a path.
public let tmuxWindowFormat = ["session_id", "window_id", "session_name", "window_index", "window_name", "pane_current_command", "pane_current_path"]
    .map { "#{" + $0 + "}" }.joined(separator: "\t")

/// The windows in the output of `tmux list-windows -a -F` with `tmuxWindowFormat`. The detail is the session with the number
/// of the window, then the program and the directory of its active pane. A line with fewer fields is left out.
public func tmuxWindows(_ output: String) -> [PaletteTab] {
    output.split(separator: "\n").compactMap { line in
        let fields = line.split(separator: "\t", maxSplits: 6, omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 7 else { return nil }
        let detail = [fields[2] + ":" + fields[3], fields[5], fields[6]].filter { !$0.isEmpty }.joined(separator: " · ")
        return PaletteTab(source: .tmux(session: fields[0], window: fields[1]), title: fields[4], detail: detail)
    }
}

/// The format for `tmux list-clients -F`.
public let tmuxClientFormat = "#{client_tty}\t#{client_pid}\t#{session_id}"

/// The clients in the output of `tmux list-clients -F` with `tmuxClientFormat`.
public func tmuxClients(_ output: String) -> [TmuxClient] {
    output.split(separator: "\n").compactMap { line in
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 3, let pid = Int32(fields[1]) else { return nil }
        return TmuxClient(tty: fields[0], pid: pid, session: fields[2])
    }
}

/// The client that will show a window of `session`: the one that shows that session already, else the first one.
public func tmuxClient(for session: String, among clients: [TmuxClient]) -> TmuxClient? {
    clients.first { $0.session == session } ?? clients.first
}
