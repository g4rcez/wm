import CoreGraphics
import Foundation

public enum LayoutKind: String, Sendable, CaseIterable, Codable {
    case tiling, scrolling, master
    /// One window fills the workspace; `focus next` and `focus prev` walk through the others.
    case monocle
    /// Every window floats. A window that opens first gets the frame that `tiling` would give it. It keeps a tiling engine
    /// for the windows that the user tiles by hand.
    case floating
}

/// Where the master area of the `master` layout is.
public enum MasterOrientation: String, Sendable, CaseIterable, Codable {
    case left, right, top, bottom
    /// The master is in the middle and the stack is on both sides of it.
    case center

    /// The next one in the order left, right, top, bottom, center.
    public var next: MasterOrientation {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// The `master` layout: one or more master windows in a big area, the other windows in a stack beside it.
public struct MasterSettings: Sendable, Equatable {
    public enum NewWindow: String, Sendable, CaseIterable {
        /// A new window goes to the top of the stack.
        case stack
        /// A new window becomes the master; the old master goes to the top of the stack.
        case master
    }

    public static let minRatio = 0.1
    public static let maxRatio = 0.9

    /// The share of the screen that the master area takes along the axis of the split.
    public var ratio: Double = 0.55
    /// How many windows are masters.
    public var count: Int = 1
    public var orientation: MasterOrientation = .left
    public var newWindow: NewWindow = .stack
    public init() {}
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
    /// A new window splits the tile on the side that the mouse pointer is nearest to (Hyprland's `smart_split`).
    public var smartSplit: Bool = false
    /// A new window splits the tile that the mouse pointer is over, not the focused one, on the side that the pointer is
    /// nearest to. Without a tile under the pointer it falls back to the focused tile.
    public var splitUnderPointer: Bool = false
    /// The patterns that the picker and the menu bar list for this layout (`layout tile`).
    public var templates: [SplitTemplate] = SplitTemplate.tilingCases
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

/// The way the main strip of the scrolling layout runs on the screen.
public enum ScrollOrientation: String, Sendable, CaseIterable {
    /// Columns side by side, scrolling sideways.
    case horizontal
    /// Rows one under the other, scrolling up and down.
    case vertical
    /// `vertical` on a screen that is taller than it is wide, else `horizontal`.
    case auto
}

/// What a lone column of the scrolling layout does with the screen. `fill` is the default: a window that is alone on its
/// workspace is maximized, as it is in the tiling layout.
public enum SingleWindowFit: String, Sendable, CaseIterable {
    /// It keeps its own width.
    case keep
    /// It fills the whole width.
    case fill
}

public struct ScrollingSettings: Sendable, Equatable {
    /// Column widths as fractions of the viewport width; `columnWidth(.cycle)` walks this list.
    public var presets: [Double] = [0.33, 0.5, 0.66, 1.0]
    /// Width fraction of a new column.
    public var defaultWidth: Double = 0.5
    public var center: CenterMode = .onOverflow
    /// A lone column is centred on the screen even when `center` is `never`.
    public var alwaysCenterSingleColumn = false
    public var orientation: ScrollOrientation = .horizontal
    public var singleWindowFit: SingleWindowFit = .fill
    /// With 2 or more columns, but fewer than this number, the columns grow in proportion to fill the screen. 0 is off.
    public var visibleColumns = 0
    /// What a new column shows: `.tabbed` makes every new column a tab stack.
    public var defaultColumnDisplay: ColumnDisplay = .normal
    /// Window heights as fractions of the column height; `windowHeight(.cycle)` walks this list.
    public var presetHeights: [Double] = [0.33, 0.5, 0.66]
    /// Points of an off-screen column that stay visible at the screen edge (macOS refuses fully off-screen windows).
    public var sliverWidth: CGFloat = 8
    /// Height fraction of a parked column, centred vertically.
    public var sliverHeight: Double = 0.9
    public var vertical = VerticalStripSettings()
    /// The patterns that the picker and the menu bar list for this layout (`layout tile`).
    public var templates: [SplitTemplate] = SplitTemplate.allCases
    public init() {}
}

/// The animation of one kind of motion. `rate` is `nil` for the rate of `animations`.
public struct AnimationKind: Sendable, Equatable {
    public var enabled = true
    public var rate: Double?
    /// How the windows of a workspace come in (`workspaces` and `special`); `windows` has no style.
    public var style: WorkspaceSlide.Style = .none
    public init() {}
}

public struct AnimationSettings: Sendable, Equatable {
    public var enabled: Bool = true
    /// Moves inside a layout: a window that opens, closes, or changes size.
    public var windows = AnimationKind()
    /// Windows of the workspace that a switch shows.
    public var workspaces = AnimationKind()
    /// Windows of a special workspace that a toggle shows.
    public var special = AnimationKind()
    /// Frames per second of the window animation. The display caps it (a 60 Hz screen ticks at 60).
    public var fps: Double = 120
    /// Spring stiffness of the window animation (16 = an Apple spring with a response of 0.4 s): higher is faster.
    public var rate: Double = 16
    public init() {}
}

public struct BorderSettings: Sendable, Equatable {
    public var enabled: Bool = false
    public var width: CGFloat = 2
    public var radius: CGFloat = 10
    public var active = Color(red: 0.537, green: 0.706, blue: 0.980)
    public var inactive = Color.clear
    /// Two or more colors for a gradient border; empty for the solid `active` color. `active` is the first one.
    public var gradient: [Color] = []
    /// Direction of the gradient in degrees, as in CSS (see `BorderGradient`).
    public var angle: Double = 45
    public init() {}
}

/// A window that a program starts from a terminal takes the place of that terminal window (see `Swallow`).
public struct SwallowSettings: Sendable, Equatable {
    public var enabled = false
    /// The terminals whose windows can be swallowed: bundle ids or app names, compared ignoring case.
    public var terminals: [String] = SwallowSettings.defaultTerminals
    /// Apps that never swallow a terminal: bundle ids or app names.
    public var exceptions: [String] = []
    public static let defaultTerminals = [
        "com.mitchellh.ghostty", "com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty", "io.alacritty",
        "com.github.wez.wezterm",
    ]
    public init() {}
}

/// Which apps ask for attention (`focus urgent`): wm reads the badges of the Dock now and then.
public struct UrgentSettings: Sendable, Equatable {
    public var enabled = true
    /// Seconds between two readings of the Dock.
    public var interval: Double = 2
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
    /// Lists the keys that can be pressed next (inside a binding mode, or after a prefix chord), like a which-key plugin.
    public var showKeys = true
    public init() {}
}

/// Key sequences such as `ctrl-p>h` (press the prefix, then the next key), like a tmux or Rex prefix.
public struct PrefixSettings: Sendable, Equatable {
    /// Show a "..." state in the menu bar icon while waiting.
    public var menuBar = true
    public var label = PrefixLabelSettings()
    public init() {}
}

/// What happens after a key sequence has run (`wm.commands`).
public struct CommandSettings: Sendable, Equatable {
    public enum Mode: String, Sendable, CaseIterable {
        /// The sequence ends after one command.
        case normal
        /// The keys after the prefix stay active until `timeout` seconds pass without a command.
        case persistent
    }
    public var mode = Mode.normal
    /// Seconds without a command after which a persistent sequence ends.
    public var timeout = 0.8
    public init() {}
}

/// The zen mode (`wm zen`): the focused window alone, centered, and the others hidden.
public struct ZenSettings: Sendable, Equatable {
    public static let minWidth = 0.3
    /// Width of the window as a fraction of the work area, `minWidth`...1.
    public var width: Double = 0.7
    public init() {}
}

/// The overview (`wm overview`): all workspaces as small screens, one under the other.
public struct OverviewSettings: Sendable, Equatable {
    public static let zoomRange = 0.2...0.75
    public static let maxGap = 200.0
    /// A workspace is its screen times this.
    public var zoom: Double = 0.5
    /// Points between two workspaces.
    public var gap: Double = 48
    public init() {}
}

/// The labels of hint mode and the rings of scroll mode (`wm.config { hints = { ... } }`).
public struct HintSettings: Sendable, Equatable {
    /// The background of a label, and the color of its text.
    public var background = Color(red: 1, green: 214.0 / 255, blue: 10.0 / 255, alpha: 0.96)
    public var text = Color(red: 20.0 / 255, green: 20.0 / 255, blue: 20.0 / 255)
    /// The label of the focused element, and the ring around that element.
    public var focus = Color(red: 48.0 / 255, green: 209.0 / 255, blue: 88.0 / 255)
    /// The rings and the numbers of the scroll areas.
    public var area = Color(red: 10.0 / 255, green: 132.0 / 255, blue: 1)
    /// The letters of the labels of hint mode, the points that `h j k l` scroll, and the factor of Shift.
    public var letters = ElementSearch.alphabet
    public var scrollStep = ScrollKeys.step
    public var scrollDashFactor = ScrollKeys.dashFactor
    public static let letterCount = 4...26
    public static let stepRange = 10.0...500.0
    public static let dashFactorRange = 1.0...20.0
    public init() {}
}

/// What a key does in the select step of `wm select`. The raw value is the name in `wm.config { select = { keys = { ... } } }`.
public enum SelectAction: String, Sendable, CaseIterable {
    case copy, rightClick = "right_click", extend, search
    case left, right, down, up
    case nextWord = "next_word", previousWord = "previous_word", wordEnd = "word_end"
    case lineStart = "line_start", lineEnd = "line_end"
}

/// The keys of the select step (`wm.config { select = { keys = { ... } } }`). A key is a chord name made by `chordName`.
/// Escape always closes the mode: it cannot be changed.
public struct SelectSettings: Sendable, Equatable {
    public static let defaultKeys: [SelectAction: [String]] = [
        .copy: ["y", "cmd-c", "enter"], .rightClick: ["shift-enter"], .extend: ["v"], .search: ["slash", "backspace"],
        .left: ["h", "left"], .right: ["l", "right"], .down: ["j", "down"], .up: ["k", "up"],
        .nextWord: ["w"], .previousWord: ["b"], .wordEnd: ["e"],
        .lineStart: ["0", "cmd-left"], .lineEnd: ["4", "shift-4", "cmd-right"],
    ]

    public var keys = SelectSettings.defaultKeys
    public init() {}

    /// The name of a chord, as the keys of the settings are written: the modifiers in the order ctrl, alt, shift, cmd, then the key.
    public static func chordName(key: String, control: Bool, option: Bool, shift: Bool, command: Bool) -> String {
        ((control ? ["ctrl"] : []) + (option ? ["alt"] : []) + (shift ? ["shift"] : []) + (command ? ["cmd"] : []) + [key]).joined(separator: "-")
    }

    /// The action of each chord.
    public var actions: [String: SelectAction] {
        var result: [String: SelectAction] = [:]
        for (action, chords) in keys { for chord in chords { result[chord] = action } }
        return result
    }

    /// The first chord that two actions share, with both actions.
    public var conflict: (chord: String, first: SelectAction, second: SelectAction)? {
        var seen: [String: SelectAction] = [:]
        for action in SelectAction.allCases {
            for chord in keys[action] ?? [] {
                if let other = seen[chord], other != action { return (chord, other, action) }
                seen[chord] = action
            }
        }
        return nil
    }

    /// The letters that no label may start with: a plain letter or digit that is a key of an action.
    public var reservedLetters: Set<Character> {
        Set(keys.values.joined().compactMap { $0.count == 1 ? $0.first : nil })
    }
}

/// Floating windows (`wm.config { floating = { ... } }`).
public struct FloatingSettings: Sendable, Equatable {
    /// A window that opens floating because of a rule (`wm.floating.defaultRules` too) opens where the last floating window of its
    /// app was when it closed, with that size, instead of the place and the size that the rule or the app gives.
    public var rememberPosition = true
    public init() {}
}

/// Special workspaces (`wm workspace special`).
public struct SpecialSettings: Sendable, Equatable {
    public static let minSize = 0.5
    /// Size of a shown special workspace as a fraction of the work area, `minSize`...1.
    public var size: Double = 0.9
    /// A dim layer on the monitor behind a shown special workspace. Clear (the default) is no layer.
    public var backdrop = Color.clear
    /// A window of a normal workspace on another monitor that gets the focus hides the special workspace too. By default only
    /// the special workspace of the monitor of that window hides.
    public var hideOnOtherMonitor = false
    public init() {}
}

public struct BindSettings: Sendable, Equatable {
    /// Seconds a key is held before a `long_press` bind runs.
    public var longPressTimeout: Double = 0.4
    /// Turn off the Cmd+Tab and Cmd+Shift+Tab of macOS while wm runs, so a wm bind on them is the only switcher.
    public var disableSystemCmdTab = false
    /// CapsLock is the `hyper` modifier (`binds.capslock = "hyper"`): held with a key it makes a chord that starts with `hyper-`, and a tap alone is Esc.
    public var capsLockHyper = false
    public init() {}
}

public struct SwitcherSettings: Sendable, Equatable {
    /// Draw a picture of each window (needs the Screen Recording permission); otherwise app icon and title.
    public var thumbnails = true
    /// Seconds before the overlay appears, so a quick Alt+Tab does not flash it.
    public var delay: Double = 0.12
    /// Largest scale of the miniature relative to the screen, 0.3...1.
    public var maxScale: Double = 0.85
    public init() {}
}

public struct FocusFollowsMouse: Sendable, Equatable {
    public var enabled = false
    /// The pointer focuses only windows that are fully on screen, so it does not scroll a column into view by accident.
    public var onlyFullyVisible = false
    public init(enabled: Bool = false, onlyFullyVisible: Bool = false) {
        self.enabled = enabled
        self.onlyFullyVisible = onlyFullyVisible
    }
}

/// Swipes with 3 or 4 fingers, read from the private MultitouchSupport framework.
public struct TrackpadSettings: Sendable, Equatable {
    public var enabled = true
    /// The number of fingers (3 or 4) of the built-in swipes: the workspaces and the overview.
    public var fingers = 4
    /// The number of fingers (3 or 4) whose swipe scrolls the scrolling strip. 0: none.
    public var scrollFingers = 4
    /// Strip points per pad width are multiplied by this.
    public var speed = 1.0
    /// Two-finger swipes and pinches on the title bar of a window (`wm.gesture` with `zone = "title_bar"`, and the built-in ones).
    public var titleBar = false
    /// How many points from the top of a window count as its title bar.
    public var titleBarHeight = 40.0
    /// Pinch gestures in the title bar, when `titleBar` is on.
    public var pinch = true
    /// Tell the user in a notification when the framework or a trackpad is missing. Only when the config turned the
    /// trackpad on itself: on by default, a Mac without a trackpad only gets a line in the log.
    public var warnsWhenMissing = false
    public init(enabled: Bool = true, fingers: Int = 4, scrollFingers: Int = 4, speed: Double = 1, warnsWhenMissing: Bool = false) {
        self.enabled = enabled
        self.fingers = fingers
        self.scrollFingers = scrollFingers
        self.speed = speed
        self.warnsWhenMissing = warnsWhenMissing
    }
}

/// Hold the modifier and drag anywhere in a window to move it (left button) or resize it (right button). `nil` is off.
/// The modifiers are chord text such as `alt` or `alt+shift`.
public struct MouseSettings: Sendable, Equatable {
    public var moveModifier: String?
    public var resizeModifier: String?
    public init(moveModifier: String? = nil, resizeModifier: String? = nil) {
        self.moveModifier = moveModifier
        self.resizeModifier = resizeModifier
    }
}

/// What the menu bar icon shows (`wm.config { menubar = { ... } }`).
public struct MenuBarSettings: Sendable, Equatable {
    public enum Workspaces: String, Sendable, CaseIterable {
        /// Every workspace that has windows, and the one in focus.
        case occupied
        /// Only the workspace in focus.
        case current
    }

    public var workspaces: Workspaces = .occupied
    /// The text of the workspace in focus. `{mode}`, `{name}`, `{count}` and `{layout}` are replaced.
    public var current = "{mode}:{name}"
    /// The text of every other workspace in the list.
    public var other = "{name}"
    public var separator = " "
    /// What `{mode}` says for a layout, by layout. A layout that is missing has its letter (`T`, `S`, `M`, `O`, `F`). `floating` is
    /// also what `{mode}` says while the focused window floats.
    public var modes: [LayoutKind: String] = [:]
    public init() {}
}

public struct Settings: Sendable, Equatable {
    public var layout: LayoutKind = .tiling
    public var gaps = Gaps(inner: 8, outer: 8)
    public var animations = AnimationSettings()
    public var border = BorderSettings()
    public var swallow = SwallowSettings()
    public var urgent = UrgentSettings()
    public var tabIndicator = TabIndicatorSettings()
    public var focusFollowsMouse = FocusFollowsMouse()
    public var mouseFollowsFocus = false
    public var startAtLogin = false
    /// `focus <dir>` wraps around at the edge of the workspace.
    public var wrapFocus = false
    public var mouse = MouseSettings()
    public var trackpad = TrackpadSettings()
    /// `workspace N` while N is shown goes back to the previous workspace.
    public var workspaceBackAndForth = false
    public var tiling = TilingSettings()
    public var scrolling = ScrollingSettings()
    public var switcher = SwitcherSettings()
    public var prefix = PrefixSettings()
    public var menuBar = MenuBarSettings()
    public var commands = CommandSettings()
    public var binds = BindSettings()
    public var zen = ZenSettings()
    public var special = SpecialSettings()
    public var floating = FloatingSettings()
    public var keyboards = KeyboardSettings()
    public var overview = OverviewSettings()
    public var hints = HintSettings()
    public var select = SelectSettings()
    public var master = MasterSettings()
    public var appearance = AppearanceSettings()
    /// Commands a `wm://` URL may run besides the always-allowed ones. `exec` and `reload` are denied by default.
    public var urlAllow: [String] = []
    public init() {}

    /// The tile templates of a layout, in the order of the picker.
    public func templates(for layout: LayoutKind) -> [SplitTemplate] {
        switch layout {
        case .tiling, .floating: tiling.templates
        case .scrolling: scrolling.templates
        case .master, .monocle: []
        }
    }
}
