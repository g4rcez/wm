import Common
import Core
import Foundation

struct SavedWindow: Codable {
    var id: WindowID
    var bundleID: String
    var workspace: String
    var floating: Bool
    var floatFrame: CGRect?
    /// Missing in a state that an older wm saved.
    var marks: [String]?
    /// The title and the place in the layout, to find the window again after a reboot (when the ids are new). Missing in a
    /// state that an older wm saved.
    var title: String?
    var order: Int?
    /// A sticky window (`window sticky`) and the monitor that it follows. Missing in a state that an older wm saved.
    var sticky: Bool?
    var stickyMonitor: UInt32?
}

struct SavedWorkspace: Codable {
    var layout: LayoutState
    var history: [WindowID]
    var maximized: [WindowID]
    var fullscreen: WindowID?
}

/// What the next daemon needs to put the windows that are still open back where they were.
struct SavedState: Codable {
    static let currentVersion = 1
    static let workspaceMode = "emulated"

    var version = currentVersion
    /// A state saved by the removed native mode has another value, and is not used.
    var mode: String
    var windows: [SavedWindow]
    var workspaces: [String: SavedWorkspace]
    /// Display id to the workspace it showed.
    var monitors: [String: String]
    /// The layouts that `wm.workspace` gave when the state was saved. A layout that the config changes since then wins
    /// over the saved one.
    var configLayouts: [String: LayoutKind]
    /// When the Mac started. A state from another start has window ids that mean nothing. Missing in a state that an older
    /// wm saved: it counts as the same start.
    var bootTime: Double?
    /// Display id to the name of the display, to find a display again after a reboot (its id can change).
    var monitorNames: [String: String]?
}

enum StateStore {
    /// `$XDG_STATE_HOME/wm/state.json`, else `~/.local/state/wm/state.json`.
    static var url: URL {
        let base = ProcessInfo.processInfo.environment["XDG_STATE_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state")
        return base.appendingPathComponent("wm/state.json")
    }

    /// The frames that the user drew on the picker grid, next to the state file.
    static var templatesURL: URL { url.deletingLastPathComponent().appendingPathComponent("custom-templates.json") }

    /// `nil` when there is no file, or when it cannot be used (another version, damaged).
    static func load(from url: URL = url) -> SavedState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let state = try JSONDecoder().decode(SavedState.self, from: data)
            guard state.version == SavedState.currentVersion else {
                Log.write(.warn, "ignoring \(url.path): version \(state.version)", source: "state", prefix: "wmd")
                return nil
            }
            return state
        } catch {
            Log.write(.warn, "ignoring \(url.path): \(error)", source: "state", prefix: "wmd")
            return nil
        }
    }

    /// The time of the last start of the Mac, in seconds.
    static func bootTime() -> Double? {
        var mib = [CTL_KERN, KERN_BOOTTIME]
        var value = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctl(&mib, 2, &value, &size, nil, 0) == 0 else { return nil }
        return Double(value.tv_sec)
    }

    /// Whether the window ids of a state are still the ones of the running system.
    static func isSameBoot(_ saved: Double?) -> Bool {
        guard let saved, let now = bootTime() else { return true }
        // The clock can be adjusted by a few seconds without a reboot.
        return abs(saved - now) < 30
    }

    static func encode(_ state: SavedState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(state)
    }

    static func write(_ data: Data, to url: URL = url) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
    }
}
