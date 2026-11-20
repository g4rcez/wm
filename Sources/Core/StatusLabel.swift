/// A workspace as the menu bar icon sees it.
public struct WorkspaceStatus: Sendable, Equatable {
    public var name: String
    public var layout: LayoutKind?
    /// The windows that belong to the workspace.
    public var count: Int
    /// The workspace shows even with no window (`persistent` in `wm.workspace`).
    public var persistent: Bool

    public init(name: String, layout: LayoutKind?, count: Int, persistent: Bool = false) {
        self.name = name
        self.layout = layout
        self.count = count
        self.persistent = persistent
    }
}

/// One piece of the menu bar text. The piece of the workspace in focus is drawn on a filled background, so that it stands out.
public struct StatusSegment: Sendable, Equatable {
    public var text: String
    public var isCurrent: Bool

    public init(_ text: String, isCurrent: Bool = false) {
        self.text = text
        self.isCurrent = isCurrent
    }
}

/// The text of the menu bar icon (`wm.config { menubar = { ... } }`). By default it lists the workspaces that have windows, in order,
/// and the workspace in focus as `<mode>:<name>`: `T:1 2 5`. The mode is the layout of the workspace (`T` tiling, `S` scrolling,
/// `M` master), or `F` when the focused window floats.
public enum StatusLabel {
    /// The longest workspace name that the icon shows; a longer one is cut. Seven, so that `special` shows in full.
    public static let maxNameLength = 7

    /// The words that a template may use in braces.
    public static let placeholders = ["mode", "name", "count", "layout"]

    public static func letter(layout: LayoutKind?, floating: Bool) -> String {
        if floating { return "F" }
        switch layout {
        case .tiling: return "T"
        case .scrolling: return "S"
        case .master: return "M"
        case .monocle: return "O"
        case .floating: return "F"
        case nil: return "?"
        }
    }

    /// The first word in braces that is not a placeholder, or `nil` when the template is fine.
    public static func unknownPlaceholder(in template: String) -> String? {
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            guard let close = rest[open...].firstIndex(of: "}") else { return nil }
            let word = String(rest[rest.index(after: open)..<close])
            if !placeholders.contains(word) { return word }
            rest = rest[rest.index(after: close)...]
        }
        return nil
    }

    /// Workspace names in the order of the icon: numbers first, from the lowest, then the other names by their bytes (ASCII).
    public static func precedes(_ a: String, _ b: String) -> Bool {
        switch (Int(a), Int(b)) {
        case let (x?, y?): return x != y ? x < y : a.utf8.lexicographicallyPrecedes(b.utf8)
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return a.utf8.lexicographicallyPrecedes(b.utf8)
        }
    }

    /// The text for the workspace in focus (`current`) and, with `settings.workspaces == .occupied`, the workspaces that have windows.
    /// The workspace in focus is always listed, even when it is empty. `floating`: the focused window floats.
    public static func text(workspaces: [WorkspaceStatus], current: WorkspaceStatus, floating: Bool, settings: MenuBarSettings) -> String {
        segments(workspaces: workspaces, current: current, floating: floating, settings: settings).map(\.text).joined()
    }

    /// The same text in pieces, the separators included, so that the icon can draw the workspace in focus on a background.
    public static func segments(workspaces: [WorkspaceStatus], current: WorkspaceStatus, floating: Bool, settings: MenuBarSettings) -> [StatusSegment] {
        guard !current.name.isEmpty else { return [] }
        var listed = settings.workspaces == .current ? [] : workspaces.filter { ($0.count > 0 || $0.persistent) && $0.name != current.name }
        listed.append(current)
        listed.sort { precedes($0.name, $1.name) }
        var pieces: [StatusSegment] = []
        for status in listed {
            if !pieces.isEmpty, !settings.separator.isEmpty { pieces.append(StatusSegment(settings.separator)) }
            let focused = status.name == current.name
            pieces.append(StatusSegment(render(focused ? settings.current : settings.other, status, floating: focused && floating), isCurrent: focused))
        }
        return pieces
    }

    private static func render(_ template: String, _ status: WorkspaceStatus, floating: Bool) -> String {
        template
            .replacingOccurrences(of: "{mode}", with: letter(layout: status.layout, floating: floating))
            .replacingOccurrences(of: "{name}", with: String(status.name.prefix(maxNameLength)))
            .replacingOccurrences(of: "{count}", with: String(status.count))
            .replacingOccurrences(of: "{layout}", with: status.layout?.rawValue ?? "")
    }
}
