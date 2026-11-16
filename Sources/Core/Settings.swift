import CoreGraphics
import Foundation

public enum LayoutKind: String, Sendable, CaseIterable, Codable {
    case tiling, scrolling
}

public enum WorkspaceMode: String, Sendable {
    case emulated, native
}

public enum CenterMode: String, Sendable {
    case never, always
    case onOverflow = "on-overflow"
}

public struct Color: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let clear = Color(red: 0, green: 0, blue: 0, alpha: 0)
}

/// Which child of a split a new window becomes: the second (right or bottom) or the first (left or top).
public enum NewWindowSide: String, Sendable, CaseIterable {
    case second, first
}

public struct TilingSettings: Sendable, Equatable {
    /// Where a new window goes in the split of the window that it splits.
    public var forceSplit: NewWindowSide = .second
    /// Multiplies the width of a cell when the split direction is chosen: with 2 a cell has to be twice as wide as
    /// tall to split side by side, so an ultrawide screen shows more columns before the first stacked split.
    public var splitWidthMultiplier: Double = 1
    /// Share of the cell that the first child gets, 0.1...0.9.
    public var splitRatio: Double = 0.5
    /// Keep a split's orientation when its sibling is closed or the window is re-inserted.
    public var preserveSplit: Bool = true
    public init() {}
}

/// The vertical strip of the scrolling layout: a zone at one side of the screen where windows are rows.
public struct VerticalStripSettings: Sendable, Equatable {
    /// `.left` or `.right`.
    public var side: Direction = .right
    /// Width of the zone as a fraction of the tiling area, 0.1...0.9.
    public var width: Double = 0.25
    /// Height of a new row as a fraction of the zone height.
    public var rowHeight: Double = 0.5
    public init() {}
}

/// How the windows of a column show: all stacked at their own heights, or one at a time with tabs.
public enum ColumnDisplay: String, Sendable, CaseIterable {
    case normal, tabbed
}

public struct ScrollingSettings: Sendable, Equatable {
    /// Column widths as fractions of the viewport width; `columnWidth(.cycle)` walks this list.
    public var presets: [Double] = [0.33, 0.5, 0.66, 1.0]
    /// Width fraction of a new column.
    public var defaultWidth: Double = 0.5
    public var center: CenterMode = .onOverflow
    /// A lone column is centred on the screen even when `center` is `never`.
    public var alwaysCenterSingleColumn = false
    /// What a new column shows: `.tabbed` makes every new column a tab stack.
    public var defaultColumnDisplay: ColumnDisplay = .normal
    /// Window heights as fractions of the column height; `windowHeight(.cycle)` walks this list.
    public var presetHeights: [Double] = [0.33, 0.5, 0.66]
    /// Points of an off-screen column that stay visible at the screen edge (macOS refuses fully off-screen windows).
    public var sliverWidth: CGFloat = 8
    /// Height fraction of a parked column, centred vertically.
    public var sliverHeight: Double = 0.9
    public var vertical = VerticalStripSettings()
    public init() {}
}

public struct AnimationSettings: Sendable, Equatable {
    public var enabled: Bool = true
    /// Exponential ease-out rate per second (`1 - exp(-rate * dt)` of the remaining distance per frame).
    public var rate: Double = 14
    public init() {}
}

public struct BorderSettings: Sendable, Equatable {
    public var enabled: Bool = false
    public var width: CGFloat = 2
    public var radius: CGFloat = 10
    public var active = Color(red: 0.537, green: 0.706, blue: 0.980)
    public var inactive = Color.clear
    public init() {}
}

public enum TabIndicatorPosition: String, Sendable, CaseIterable {
    case left, right, top, bottom
}

/// The small bar that shows the tabs of a tabbed column: one segment per window, the focused one highlighted.
public struct TabIndicatorSettings: Sendable, Equatable {
    public var enabled = true
    /// The edge of the column where the bar is drawn, inside the window.
    public var position: TabIndicatorPosition = .left
    /// Thickness of the bar, in points.
    public var size: CGFloat = 6
    /// Space between two segments, in points.
    public var spacing: CGFloat = 3
    public var radius: CGFloat = 3
    public var active = Color(red: 0.537, green: 0.706, blue: 0.980)
    public var inactive = Color(red: 0.6, green: 0.6, blue: 0.65, alpha: 0.6)
    public init() {}
}

public enum LabelPosition: String, Sendable, CaseIterable {
    case topLeft = "top-left", topCenter = "top-center", topRight = "top-right"
    case left, center, right
    case bottomLeft = "bottom-left", bottomCenter = "bottom-center", bottomRight = "bottom-right"

    /// The positions at a side of the screen: the key panel is a list there, one key per line. The centered positions
    /// (`top-center`, `center`, `bottom-center`) lay the keys out in a row grid.
    public var isSide: Bool {
        switch self {
        case .topLeft, .topRight, .left, .right, .bottomLeft, .bottomRight: true
        case .topCenter, .center, .bottomCenter: false
        }
    }

    /// Names that older configs use for the two centered positions.
    public static let aliases = ["top": "top-center", "bottom": "bottom-center"]
}

/// The small floating label that shows a key sequence waiting for its next key (for example `ctrl-p ...`).
public struct PrefixLabelSettings: Sendable, Equatable {
    public var enabled = true
    /// Where on the focused monitor's work area the label sits, 10 points from the edges it touches.
    public var position: LabelPosition = .bottomCenter
    /// Moves the label from `position`, in points: positive x goes right, positive y goes down.
    public var offsetX: CGFloat = 0
    public var offsetY: CGFloat = 0
    public var fontSize: CGFloat = 11
    /// The name of a font (`Menlo`, `SF Pro Rounded`...). `nil`: the system font, which has weights.
    public var fontName: String?
    /// Lists the keys that can be pressed next (inside a binding mode, or after a prefix chord), like a which-key plugin.
    public var showKeys = true
    /// Fill of the mode name chip.
    public var accent = Color(red: 0.537, green: 0.706, blue: 0.980)
    public var background = Color(red: 0.118, green: 0.118, blue: 0.180, alpha: 0.8)
    public var foreground = Color(red: 0.84, green: 0.87, blue: 0.96)
    public init() {}
}

/// Key sequences such as `ctrl-p>h` (press the prefix, then the next key), like a tmux or Rex prefix.
public struct PrefixSettings: Sendable, Equatable {
    /// Show a "..." state in the menu bar icon while waiting.
    public var menuBar = true
    public var label = PrefixLabelSettings()
    public init() {}
}

public struct BindSettings: Sendable, Equatable {
    /// Seconds a key is held before a `long_press` bind runs.
    public var longPressTimeout: Double = 0.4
    public init() {}
}

public struct SwitcherSettings: Sendable, Equatable {
    /// Draw a picture of each window (needs the Screen Recording permission); otherwise app icon and title.
    public var thumbnails = true
    /// Seconds before the overlay appears, so a quick Alt+Tab does not flash it.
    public var delay: Double = 0.12
    public var background = Color(red: 0, green: 0, blue: 0, alpha: 0.55)
    public var selected = Color(red: 0.537, green: 0.706, blue: 0.980)
    /// Largest scale of the miniature relative to the screen, 0.3...1.
    public var maxScale: Double = 0.85
    public init() {}
}

public struct Settings: Sendable, Equatable {
    public var layout: LayoutKind = .tiling
    public var workspaces: WorkspaceMode = .emulated
    public var gaps = Gaps(inner: 8, outer: 8)
    public var animations = AnimationSettings()
    public var border = BorderSettings()
    public var tabIndicator = TabIndicatorSettings()
    public var focusFollowsMouse = false
    public var mouseFollowsFocus = false
    public var startAtLogin = false
    /// `focus <dir>` wraps around at the edge of the workspace.
    public var wrapFocus = false
    public var tiling = TilingSettings()
    public var scrolling = ScrollingSettings()
    public var switcher = SwitcherSettings()
    public var prefix = PrefixSettings()
    public var binds = BindSettings()
    /// Commands a `wm://` URL may run besides the always-allowed ones. `exec` and `reload` are denied by default.
    public var urlAllow: [String] = []
    public init() {}
}
