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

    /// The area of a shown special workspace: 5% of the work area stays free on each side, so it does not look like
    /// a normal workspace.
    public static func viewport(in workArea: CGRect) -> CGRect {
        workArea.insetBy(dx: workArea.width * 0.05, dy: workArea.height * 0.05)
    }
}
