import Foundation

/// The first-run gate. wm moves no window until the user has pressed Start in the setup window, and that press leaves a marker
/// file in the state folder. A marker from any version is enough: the setup is not shown again after an upgrade.
public enum Onboarding {
    /// `$XDG_STATE_HOME/wm/onboarded`, else `~/.local/state/wm/onboarded`: next to the log and the saved state.
    public static func markerURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        defaultLogURL(environment: environment, home: home).deletingLastPathComponent().appendingPathComponent("onboarded")
    }

    public static func isDone(marker: URL = markerURL()) -> Bool {
        FileManager.default.fileExists(atPath: marker.path)
    }

    /// Writes the marker with the version that wrote it. Delete the file to see the setup window again.
    public static func markDone(marker: URL = markerURL()) throws {
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((wmVersion + "\n").utf8).write(to: marker, options: .atomic)
    }
}
