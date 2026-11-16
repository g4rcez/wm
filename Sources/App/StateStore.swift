import Core
import Foundation

struct SavedWindow: Codable {
    var id: WindowID
    var bundleID: String
    var workspace: String
    var floating: Bool
    var floatFrame: CGRect?
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

    var version = currentVersion
    /// `WorkspaceMode` raw value. A state saved in the other mode is not used.
    var mode: String
    var windows: [SavedWindow]
    var workspaces: [String: SavedWorkspace]
    /// Display id to the workspace it showed.
    var monitors: [String: String]
    var activeRows: [String: Int]
    /// The layouts that `wm.workspace` gave when the state was saved. A layout that the config changes since then wins
    /// over the saved one.
    var configLayouts: [String: LayoutKind]
}

enum StateStore {
    /// `$XDG_STATE_HOME/wm/state.json`, else `~/.local/state/wm/state.json`.
    static var url: URL {
        let base = ProcessInfo.processInfo.environment["XDG_STATE_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state")
        return base.appendingPathComponent("wm/state.json")
    }

    /// `nil` when there is no file, or when it cannot be used (another version, damaged).
    static func load(from url: URL = url) -> SavedState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let state = try JSONDecoder().decode(SavedState.self, from: data)
            guard state.version == SavedState.currentVersion else {
                fputs("wmd: ignoring \(url.path): version \(state.version)\n", stderr)
                return nil
            }
            return state
        } catch {
            fputs("wmd: ignoring \(url.path): \(error)\n", stderr)
            return nil
        }
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
