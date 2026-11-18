import CoreGraphics
import Foundation

public struct PickedFrame: Sendable, Equatable {
    public var x: Double, y: Double, width: Double, height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }
}

/// What `wm pick` knows about the window that was clicked. A window that wm does not manage (a dialog, a popup, a window
/// that a rule ignores) has no workspace, no state and no `--window` selectors.
public struct PickedWindow: Sendable, Equatable {
    public var id: UInt32
    public var pid: Int32
    public var bundleID: String
    public var appName: String
    public var title: String
    public var role: String
    public var subrole: String
    public var frame: PickedFrame
    public var managed: Bool
    public var workspace: String?
    public var state: [String]

    public init(
        id: UInt32, pid: Int32, bundleID: String, appName: String, title: String, role: String, subrole: String,
        frame: PickedFrame, managed: Bool, workspace: String?, state: [String]
    ) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.role = role
        self.subrole = subrole
        self.frame = frame
        self.managed = managed
        self.workspace = workspace
        self.state = state
    }
}

/// The text of `wm pick`: one `key  value` line per fact, then the `--window` selectors and a `wm.rule` table to copy.
public func renderPick(_ window: PickedWindow) -> String {
    var rows: [(String, String)] = [
        ("id", String(window.id)),
        ("app", "\(window.appName) (\(window.bundleID))"),
        ("pid", String(window.pid)),
        ("title", window.title.isEmpty ? "-" : window.title),
        ("role", "\(window.role.isEmpty ? "-" : window.role) / \(window.subrole.isEmpty ? "-" : window.subrole)"),
        ("managed", window.managed ? "yes" : "no"),
    ]
    if let workspace = window.workspace { rows.append(("workspace", workspace)) }
    if !window.state.isEmpty { rows.append(("state", window.state.joined(separator: ", "))) }
    let frame = window.frame
    rows.append(("frame", "\(Int(frame.x.rounded())),\(Int(frame.y.rounded())) \(Int(frame.width.rounded()))x\(Int(frame.height.rounded()))"))
    if window.managed {
        rows.append(("window", ["\(window.id)", "app:\(window.bundleID)", "pid:\(window.pid)"].map { "--window \($0)" }.joined(separator: " · ")))
    }
    rows.append(("rule", rule(for: window)))
    return rows.map { $0.0.padded(to: 11) + $0.1 }.joined(separator: "\n") + "\n"
}

/// `{ app = "...", title = "^...$" }`: a table for `wm.rule`. The title is a regular expression, so its characters are escaped.
private func rule(for window: PickedWindow) -> String {
    var fields = ["app = \(luaString(window.bundleID))"]
    if !window.title.isEmpty { fields.append("title = \(luaString("^" + NSRegularExpression.escapedPattern(for: window.title) + "$"))") }
    return "{ " + fields.joined(separator: ", ") + " }"
}

private func luaString(_ text: String) -> String {
    "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}
