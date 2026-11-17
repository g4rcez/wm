import Foundation

public struct OverviewMonitor: Sendable, Equatable {
    public var id: UInt32
    public var name: String
    /// The workspace shown on this monitor.
    public var workspace: String

    public init(id: UInt32, name: String, workspace: String) {
        self.id = id
        self.name = name
        self.workspace = workspace
    }
}

public struct OverviewWindow: Sendable, Equatable {
    public var id: UInt32
    public var app: String
    public var title: String
    public var focused = false
    public var floating = false
    public var maximized = false
    public var minimized = false
    /// `"vertical"` for a window in the vertical strip of a scrolling workspace.
    public var strip: String?

    public init(
        id: UInt32, app: String, title: String, focused: Bool = false, floating: Bool = false,
        maximized: Bool = false, minimized: Bool = false, strip: String? = nil
    ) {
        self.id = id
        self.app = app
        self.title = title
        self.focused = focused
        self.floating = floating
        self.maximized = maximized
        self.minimized = minimized
        self.strip = strip
    }
}

public struct OverviewWorkspace: Sendable, Equatable {
    public var name: String
    public var layout: String
    /// The monitor that shows this workspace now, if any.
    public var monitor: UInt32?
    public var windows: [OverviewWindow]

    public init(name: String, layout: String, monitor: UInt32?, windows: [OverviewWindow]) {
        self.name = name
        self.layout = layout
        self.monitor = monitor
        self.windows = windows
    }
}

/// The text that `wm list` prints: the monitors, then every workspace with its windows, aligned in columns.
public func renderOverview(monitors: [OverviewMonitor], workspaces: [OverviewWorkspace]) -> String {
    var lines: [String] = monitors.map { "monitor \($0.id)  \($0.name)  shows workspace \($0.workspace)" }
    if !monitors.isEmpty, !workspaces.isEmpty { lines.append("") }

    let all = workspaces.flatMap(\.windows)
    let idWidth = all.map { String($0.id).count }.max() ?? 0
    let appWidth = all.map(\.app.count).max() ?? 0

    for workspace in workspaces {
        var header = "workspace \(workspace.name)  \(workspace.layout)"
        if let monitor = workspace.monitor { header += "  [visible, monitor \(monitor)]" }
        lines.append(header)
        for window in workspace.windows {
            var row = "  " + (window.focused ? "* " : "  ")
            row += String(window.id).padded(to: idWidth)
            row += "  " + window.app.padded(to: appWidth)
            if !window.title.isEmpty { row += "  " + window.title }
            var marks: [String] = []
            if window.floating { marks.append("(floating)") }
            if window.maximized { marks.append("(maximized)") }
            if window.minimized { marks.append("(minimized)") }
            if let strip = window.strip { marks.append("[\(strip)]") }
            if !marks.isEmpty { row += "  " + marks.joined(separator: " ") }
            // An app column pads short names; do not leave blanks at the end of the line.
            lines.append(row.withoutTrailingBlanks)
        }
    }
    return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
}
