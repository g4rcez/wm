import CoreGraphics

/// Hyprland-style special workspaces: a workspace named `special` or `special:<name>` that one command shows on a
/// monitor in place of its normal workspace, and hides again.
public enum SpecialWorkspace {
    private static let prefix = "special"

    /// The workspace name for a command argument: no argument gives `special`, `term` gives `special:term`.
    /// `nil` when the name is empty.
    public static func name(_ argument: String?) -> String? {
        guard let argument, argument != prefix else { return prefix }
        let short = argument.hasPrefix(prefix + ":") ? String(argument.dropFirst(prefix.count + 1)) : argument
        return short.isEmpty ? nil : prefix + ":" + short
    }

    public static func isSpecial(_ workspace: String) -> Bool {
        workspace == prefix || workspace.hasPrefix(prefix + ":")
    }

    /// The special workspace shown on each monitor after `name` is toggled on `monitor`. A special workspace is shown
    /// on one monitor at most, and a monitor shows one at most.
    public static func toggle(_ name: String, on monitor: UInt32, shown: [UInt32: String]) -> [UInt32: String] {
        var next = shown.filter { $0.value != name }
        if shown[monitor] != name { next[monitor] = name }
        return next
    }

    /// The area of a shown special workspace: a `size` fraction (0.9 by default) of the work area, in the middle, so it does
    /// not look like a normal workspace.
    public static func viewport(in workArea: CGRect, size: Double = 0.9) -> CGRect {
        let width = workArea.width * size, height = workArea.height * size
        return CGRect(x: workArea.midX - width / 2, y: workArea.midY - height / 2, width: width, height: height)
    }

    /// The monitors whose shown special workspace hides when a window of a normal workspace gets the focus. That window
    /// is on `windowMonitor`. An empty special workspace stays: the user opened it to start an app in it.
    public static func monitorsHiding(
        onFocusOf windowMonitor: UInt32, shown: [UInt32: String], otherMonitors: Bool, hasWindows: (String) -> Bool
    ) -> [UInt32] {
        shown.filter { (otherMonitors || $0.key == windowMonitor) && hasWindows($0.value) }.keys.sorted()
    }
}
