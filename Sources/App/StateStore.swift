import Common
import Core
import Foundation

struct SavedWindow: Codable {
    var id: WindowID
    var bundleID: String
    var workspace: String
    var floating: Bool
    var floatFrame: CGRect?
    var marks: [String]?
    var title: String?
    var order: Int?
    var sticky: Bool?
    var stickyMonitor: UInt32?
    /// The program window that swallowed this terminal. Kept only within one boot, where window ids stay the same.
    var swallowedBy: WindowID?
}

struct SavedWorkspace: Codable {
    var layout: LayoutState
    var history: [WindowID]
    var maximized: [WindowID]
    var fullscreen: WindowID?
}

struct SavedState: Codable {
    static let currentVersion = 1

    var version = currentVersion
    var mode: String
    var windows: [SavedWindow]
    var workspaces: [String: SavedWorkspace]
    var monitors: [String: String]
    var configLayouts: [String: LayoutKind]
    var bootTime: Double?
    var monitorNames: [String: String]?
}

enum StateStore {
    static var url: URL {
        let base = ProcessInfo.processInfo.environment["XDG_STATE_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state")
        return base.appendingPathComponent("wm/state.json")
    }

    static var templatesURL: URL { url.deletingLastPathComponent().appendingPathComponent("custom-templates.json") }

    static func load(from url: URL = url) -> SavedState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let state = try JSONDecoder().decode(SavedState.self, from: data)
            guard state.version == SavedState.currentVersion else {
                Log.write(.warn, "ignoring \(url.path): version \(state.version)\(keptAs(url))", source: "state", prefix: "wmd")
                return nil
            }
            return state
        } catch {
            Log.write(.warn, "ignoring \(url.path): \(error)\(keptAs(url))", source: "state", prefix: "wmd")
            return nil
        }
    }

    static func bootTime() -> Double? {
        var mib = [CTL_KERN, KERN_BOOTTIME]
        var value = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctl(&mib, 2, &value, &size, nil, 0) == 0 else { return nil }
        return Double(value.tv_sec)
    }

    static func isSameBoot(_ saved: Double?) -> Bool {
        guard let saved, let now = bootTime() else { return true }
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
        // Window titles and places: readable by this user only. An atomic write makes a new file each time.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
