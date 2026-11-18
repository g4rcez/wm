import Core
import Foundation

/// Runs a program and gives what it printed.
public enum Subprocess {
    /// The standard output of the program, or `nil` when it cannot start, ends with an error, or is not done after `timeout`
    /// seconds (it is stopped then). The daemon has the short `PATH` of launchd, so `path` is absolute.
    public static func output(_ path: String, _ arguments: [String], timeout: TimeInterval = 2) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                guard (try? process.run()) != nil else { return continuation.resume(returning: nil) }
                let pid = process.processIdentifier
                let stop = DispatchWorkItem { kill(pid, SIGTERM) }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: stop)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                stop.cancel()
                continuation.resume(returning: process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil)
            }
        }
    }
}

/// Reads the tabs of browsers, of Rex and of tmux for the palette, and selects one. A source that is not installed, not
/// running or not allowed gives no tabs. Nothing here starts an app or a server.
public struct TabReader: Sendable {
    /// The browsers that have the scripting dictionary of Chromium (windows with tabs that have a title and a URL).
    public static let browsers = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.brave.Browser", "com.microsoft.edgemac", "net.imput.helium",
        "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "org.chromium.Chromium", "dev.serafim.fast",
    ]
    public static let rexBundleID = "com.superlogical.rex"

    /// What happened to the tab that the palette asked for.
    public enum Activation: Sendable, Equatable {
        case done
        /// tmux shows the window in the client with this process.
        case client(pid: Int32)
        case failed(String)
    }

    private static let osascript = "/usr/bin/osascript"

    /// One Apple event for each property, for all the tabs of all the windows.
    private static let listScript = """
        function run(argv) {
          const app = Application(argv[0]);
          const ids = app.windows.id(), tabs = app.windows.tabs.id(), titles = app.windows.tabs.title(), urls = app.windows.tabs.url();
          return JSON.stringify(ids.map((id, w) => ({ id: String(id), tabs: tabs[w].map((tab, t) =>
            ({ id: String(tab), title: String(titles[w][t] || ""), url: String(urls[w][t] || "") })) })));
        }
        """

    /// Selects the tab in its window and puts the window in front of the other windows of the browser.
    private static let selectScript = """
        function run(argv) {
          const app = Application(argv[0]);
          const w = app.windows.id().findIndex(id => String(id) === argv[1]);
          if (w < 0) throw new Error("the window is gone");
          const win = app.windows[w];
          const t = win.tabs.id().findIndex(id => String(id) === argv[2]);
          if (t < 0) throw new Error("the tab is gone");
          win.activeTabIndex = t + 1;
          win.index = 1;
        }
        """

    public init() {}

    private var rex: String? {
        let path = NSHomeDirectory() + "/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex"
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    private var tmux: String? {
        ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The tabs of the browsers in `bundleIDs` (running apps), in the order of the list. The first time, macOS asks whether
    /// wm may control each browser.
    public func browserTabs(_ bundleIDs: [String]) async -> [PaletteTab] {
        await withTaskGroup(of: (Int, [PaletteTab]).self) { group in
            for (index, bundleID) in bundleIDs.enumerated() {
                group.addTask {
                    let json = await Subprocess.output(Self.osascript, ["-l", "JavaScript", "-e", Self.listScript, bundleID], timeout: 4)
                    return (index, Core.browserTabs(json: json ?? "", bundleID: bundleID))
                }
            }
            var found: [(Int, [PaletteTab])] = []
            for await result in group { found.append(result) }
            return found.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
    }

    /// The tabs of every session of Rex.
    public func rexTabs() async -> [PaletteTab] {
        guard let rex, let listing = await Subprocess.output(rex, ["--autostart=false", "ls", "--json"]) else { return [] }
        var tabs: [PaletteTab] = []
        for session in rexSessions(json: listing) {
            tabs += Core.rexTabs(json: await Subprocess.output(rex, ["--autostart=false", "window", "ls", "-s", session, "--json"]) ?? "")
        }
        return tabs
    }

    /// Every window of tmux.
    public func tmuxTabs() async -> [PaletteTab] {
        guard let tmux, let output = await Subprocess.output(tmux, ["list-windows", "-a", "-F", tmuxWindowFormat]) else { return [] }
        return tmuxWindows(output)
    }

    /// The terminals that show a session of tmux.
    public func clients() async -> [TmuxClient] {
        guard let tmux else { return [] }
        return tmuxClients(await Subprocess.output(tmux, ["list-clients", "-F", tmuxClientFormat]) ?? "")
    }

    /// Selects the tab in its program. The window of the program is not raised here: the caller focuses it.
    public func activate(_ tab: PaletteTab) async -> Activation {
        switch tab.source {
        case let .browser(bundleID, window, id):
            let done = await Subprocess.output(Self.osascript, ["-l", "JavaScript", "-e", Self.selectScript, bundleID, window, id], timeout: 4)
            return done == nil ? .failed("wm: the tab is gone, or wm may not control the browser") : .done
        case let .rex(session, window):
            guard let rex else { return .failed("wm: Rex is not installed") }
            // Rex comes to the front and shows the session. Its scripting gives a session the identifier of its host before
            // the one of the server, so the session is found by the end of its identifier.
            let tell = "tell application id \"\(Self.rexBundleID)\" to show (first session whose id ends with (item 1 of argv))"
            _ = await Subprocess.output(Self.osascript, ["-e", "on run argv", "-e", tell, "-e", "end run", session], timeout: 4)
            // The app has its own selected tab, so the app is asked to go to the tab (it does when its Remote Control is
            // on). Without that, the tab becomes the active one of the session on the server, which the app can follow.
            if await Subprocess.output(rex, ["--autostart=false", "do", "session.select", "session_id=" + session, "window_id=" + window]) != nil { return .done }
            guard await Subprocess.output(rex, ["--autostart=false", "focus", "-s", session, window]) != nil else {
                return .failed("wm: Rex did not select the tab")
            }
            return .done
        case let .tmux(session, window):
            guard let tmux else { return .failed("wm: tmux is not installed") }
            guard let client = tmuxClient(for: session, among: await clients()) else { return .failed("wm: no terminal shows tmux (no attached client)") }
            guard await Subprocess.output(tmux, ["switch-client", "-c", client.tty, "-t", session + ":" + window]) != nil else {
                return .failed("wm: tmux did not switch to the window")
            }
            return .client(pid: client.pid)
        }
    }
}
