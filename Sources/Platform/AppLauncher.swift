import AppKit

/// Starts an app by its bundle id or its name, for `wm focus app <name> --launch`.
public enum AppLauncher {
    private static var folders: [URL] {
        ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities"]
            .map { URL(fileURLWithPath: $0) } + [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
    }

    /// The `.app` for a bundle id (a name with a dot is tried as one first), or the one called `name` in the usual folders,
    /// compared in lower case.
    public static func locate(_ name: String) -> URL? {
        if name.contains("."), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) { return url }
        for folder in folders {
            let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            if let found = items.first(where: { $0.pathExtension == "app" && $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(name) == .orderedSame }) {
                return found
            }
        }
        return nil
    }

    /// Opens the app (an app that runs without a window gets a new one or the focus). `false` when there is no such app.
    @MainActor public static func launch(_ name: String) -> Bool {
        guard let url = locate(name) else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return true
    }
}
