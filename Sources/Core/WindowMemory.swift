import CoreGraphics
import Foundation

/// A frame as fractions of an area (the work area of a monitor), so it fits a monitor of another size.
public struct RelativeFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// What `window remember` keeps about a window, to give it to the next window of the same app (and title).
public struct MemorizedWindow: Codable, Equatable, Sendable {
    /// The bundle id of the app.
    public var app: String
    /// The name of the app, for `wm list memory`.
    public var appName: String
    /// Set with `--title`: the window has to have exactly this title.
    public var title: String?
    public var workspace: String
    /// The name of the monitor that showed the workspace. The workspace is used when that monitor is gone.
    public var monitor: String?
    public var floating: Bool
    /// A floating window: where it was, in the work area of its monitor.
    public var frame: RelativeFrame?
    public var maximized: Bool
    /// A pseudotiled window: the size that it keeps, in points.
    public var pseudo: CGSize?
    /// The scrolling layout: the width of the column, as a fraction of the zone.
    public var columnWidth: Double?
    /// The scrolling layout: the strip of the window.
    public var strip: Orientation?
    public var marks: [String]
    /// The window shows on every workspace of its monitor (`window sticky`). Missing in an entry that an older wm saved.
    public var sticky: Bool?

    public init(
        app: String, appName: String, title: String? = nil, workspace: String, monitor: String? = nil, floating: Bool = false,
        frame: RelativeFrame? = nil, maximized: Bool = false, pseudo: CGSize? = nil, columnWidth: Double? = nil,
        strip: Orientation? = nil, marks: [String] = [], sticky: Bool? = nil
    ) {
        self.app = app
        self.appName = appName
        self.title = title
        self.workspace = workspace
        self.monitor = monitor
        self.floating = floating
        self.frame = frame
        self.maximized = maximized
        self.pseudo = pseudo
        self.columnWidth = columnWidth
        self.strip = strip
        self.marks = marks
        self.sticky = sticky
    }
}

extension MemorizedWindow {
    /// How the window is kept: `floating`, `maximized`, `pseudo` or `tiled`.
    public var mode: String {
        if floating { return "floating" }
        if maximized { return "maximized" }
        return pseudo == nil ? "tiled" : "pseudo"
    }

    /// The text of `wm list memory` for the place: `62% x 68% at 10%, 12%` for a floating window, else `-`.
    public var frameText: String {
        guard let frame else { return "-" }
        func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
        return "\(percent(frame.width)) x \(percent(frame.height)) at \(percent(frame.x)), \(percent(frame.y))"
    }

    /// One line for `wm window remember`: `Kitty: workspace 3 on LG UltraFine, floating 62% x 68%`.
    public var summary: String {
        var parts = ["workspace \(workspace)" + (monitor.map { " on \($0)" } ?? "")]
        parts.append(frame.map { "floating \(Int(($0.width * 100).rounded()))% x \(Int(($0.height * 100).rounded()))%" } ?? mode)
        if let columnWidth { parts.append("column \(Int((columnWidth * 100).rounded()))%") }
        if strip == .vertical { parts.append("vertical strip") }
        if sticky == true { parts.append("sticky") }
        if !marks.isEmpty { parts.append("marks: " + marks.joined(separator: ", ")) }
        return "\(appName): " + parts.joined(separator: ", ")
    }
}

/// The windows that the user asked wm to remember. One entry per app, or per app and title.
public struct WindowMemory: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version = currentVersion
    public var windows: [MemorizedWindow] = []

    public init(windows: [MemorizedWindow] = []) {
        self.windows = windows
    }

    /// Keeps `entry`, in place of the entry of the same app and title.
    public mutating func remember(_ entry: MemorizedWindow) {
        windows.removeAll { $0.app == entry.app && $0.title == entry.title }
        windows.append(entry)
    }

    /// Removes the entry of this app (`title` is `nil`) or of this app and title. `false` when there was none.
    @discardableResult
    public mutating func forget(app: String, title: String?) -> Bool {
        let before = windows.count
        windows.removeAll { $0.app == app && $0.title == title }
        return windows.count != before
    }

    /// The entry for a window that opens: the one with the same app and exactly the same title, else the one of the app
    /// without a title. An entry with another title never matches.
    public func match(app: String, title: String) -> MemorizedWindow? {
        let ofApp = windows.filter { $0.app == app }
        return ofApp.first { $0.title != nil && $0.title == title } ?? ofApp.first { $0.title == nil }
    }

    /// `frame` as fractions of `area`.
    public static func relative(_ frame: CGRect, in area: CGRect) -> RelativeFrame {
        guard area.width > 0, area.height > 0 else { return RelativeFrame(x: 0, y: 0, width: 1, height: 1) }
        return RelativeFrame(
            x: Double((frame.minX - area.minX) / area.width), y: Double((frame.minY - area.minY) / area.height),
            width: Double(frame.width / area.width), height: Double(frame.height / area.height))
    }

    /// The frame in `area` again. A frame that would leave the area is made smaller and moved back inside it.
    public static func absolute(_ frame: RelativeFrame, in area: CGRect) -> CGRect {
        let width = min(max(CGFloat(frame.width), 0.05), 1) * area.width
        let height = min(max(CGFloat(frame.height), 0.05), 1) * area.height
        let x = min(max(area.minX + CGFloat(frame.x) * area.width, area.minX), area.maxX - width)
        let y = min(max(area.minY + CGFloat(frame.y) * area.height, area.minY), area.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
