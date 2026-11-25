import CoreGraphics
import Foundation

public enum LayoutKind: String, Sendable, CaseIterable, Codable {
    case tiling, scrolling, master
    case monocle
    case floating
}

public enum MasterOrientation: String, Sendable, CaseIterable, Codable {
    case left, right, top, bottom
    case center

    public var next: MasterOrientation {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

public struct MasterSettings: Sendable, Equatable {
    public enum NewWindow: String, Sendable, CaseIterable {
        case stack
        case master
    }

    public static let minRatio = 0.1
    public static let maxRatio = 0.9

    public var ratio: Double = 0.55
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

public enum NewWindowSide: String, Sendable, CaseIterable {
    case second, first
}

public struct TilingSettings: Sendable, Equatable {
    public var forceSplit: NewWindowSide = .second
    public var splitWidthMultiplier: Double = 1
    public var splitRatio: Double = 0.5
    public var preserveSplit: Bool = true
    public var smartSplit: Bool = false
    public var splitUnderPointer: Bool = false
    public var templates: [SplitTemplate] = SplitTemplate.tilingCases
    public init() {}
}

public struct VerticalStripSettings: Sendable, Equatable {
    public var side: Direction = .right
    public var width: Double = 0.25
    public var rowHeight: Double = 0.5
    public init() {}
}

public enum ColumnDisplay: String, Sendable, CaseIterable {
    case normal, tabbed
}

public enum ScrollOrientation: String, Sendable, CaseIterable {
    case horizontal
    case vertical
    case auto
}

public enum SingleWindowFit: String, Sendable, CaseIterable {
    case keep
    case fill
}

public struct ScrollingSettings: Sendable, Equatable {
    public var presets: [Double] = [0.33, 0.5, 0.66, 1.0]
    public var defaultWidth: Double = 0.5
    public var center: CenterMode = .onOverflow
    public var alwaysCenterSingleColumn = false
    public var orientation: ScrollOrientation = .horizontal
    public var singleWindowFit: SingleWindowFit = .fill
    public var visibleColumns = 0
    public var defaultColumnDisplay: ColumnDisplay = .normal
    public var presetHeights: [Double] = [0.33, 0.5, 0.66]
    public var sliverWidth: CGFloat = 8
    public var sliverHeight: Double = 0.9
    public var vertical = VerticalStripSettings()
    public var templates: [SplitTemplate] = SplitTemplate.allCases
    public init() {}
}

public struct AnimationKind: Sendable, Equatable {
    public var enabled = true
    public var rate: Double?
    public var style: WorkspaceSlide.Style = .none
    public init() {}
}

/// The fades of the overlays (switcher, overview, cheatsheet). `duration` is in seconds; absent, `appearance.animation` decides.
public struct OverlayAnimation: Sendable, Equatable {
    public var enabled = true
    public var duration: Double?
    public init() {}
}

public struct AnimationSettings: Sendable, Equatable {
    /// The master switch: off, no animation runs, whatever the kinds say.
    public var enabled: Bool = true
    public var overlays = OverlayAnimation()
    public var windows = AnimationKind()
    public var workspaces = AnimationKind()
    public var special = AnimationKind()
    public var fps: Double = 120
    public var rate: Double = 16
    public init() {}
}

public struct BorderSettings: Sendable, Equatable {
    public var enabled: Bool = false
    public var width: CGFloat = 2
    public var radius: CGFloat = 10
    public var active = Color(red: 0.537, green: 0.706, blue: 0.980)
    public var inactive = Color.clear
    public var gradient: [Color] = []
    public var angle: Double = 45
    public init() {}
}

/// The layer over the windows that do not have the focus. Off until the config asks for it.
public struct DimSettings: Sendable, Equatable {
    public static let maxAmount = 0.9
    public var enabled = false
    /// How dark: 0 is not at all, `maxAmount` is nearly the color alone.
    public var amount = 0.25
    public var color = Color(red: 0, green: 0, blue: 0)
    public init() {}
}

public struct SwallowSettings: Sendable, Equatable {
    public var enabled = false
    public var terminals: [String] = SwallowSettings.defaultTerminals
    public var exceptions: [String] = []
    public static let defaultTerminals = [
        "com.mitchellh.ghostty", "com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty", "io.alacritty",
        "com.github.wez.wezterm",
    ]
    public init() {}
}

public struct UrgentSettings: Sendable, Equatable {
    public var enabled = true
    public var interval: Double = 2
    public init() {}
}

public enum TabIndicatorPosition: String, Sendable, CaseIterable {
    case left, right, top, bottom
}

public struct TabIndicatorSettings: Sendable, Equatable {
    public var enabled = true
    public var position: TabIndicatorPosition = .left
    public var size: CGFloat = 6
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

    public var isSide: Bool {
        switch self {
        case .topLeft, .topRight, .left, .right, .bottomLeft, .bottomRight: true
        case .topCenter, .center, .bottomCenter: false
        }
    }

    public static let aliases = ["top": "top-center", "bottom": "bottom-center"]
}

public struct PrefixLabelSettings: Sendable, Equatable {
    public var enabled = true
    public var position: LabelPosition = .bottomCenter
    public var offsetX: CGFloat = 0
    public var offsetY: CGFloat = 0
    public var showKeys = true
    public init() {}
}

public struct PrefixSettings: Sendable, Equatable {
    public var menuBar = true
    public var label = PrefixLabelSettings()
    public init() {}
}

public struct CommandSettings: Sendable, Equatable {
    public enum Mode: String, Sendable, CaseIterable {
        case normal
        case persistent
    }
    public var mode = Mode.normal
    public var timeout = 0.8
    public var layers: [String: Layer] = [:]

    public struct Layer: Sendable, Equatable {
        public var mode: Mode?
        public var timeout: Double?
        public init(mode: Mode? = nil, timeout: Double? = nil) {
            self.mode = mode
            self.timeout = timeout
        }
    }

    public func resolved(forPrefix prefix: String) -> (mode: Mode, timeout: Double) {
        let layer = layers[prefix]
        return (layer?.mode ?? mode, layer?.timeout ?? timeout)
    }

    public init() {}
}

public struct ZenSettings: Sendable, Equatable {
    public static let minWidth = 0.3
    public var width: Double = 0.7
    public init() {}
}

public struct OverviewSettings: Sendable, Equatable {
    public static let zoomRange = 0.2...0.75
    public static let maxGap = 200.0
    public var zoom: Double = 0.5
    public var gap: Double = 48
    public init() {}
}

public struct HintSettings: Sendable, Equatable {
    public var background = Color(red: 1, green: 214.0 / 255, blue: 10.0 / 255, alpha: 0.96)
    public var text = Color(red: 20.0 / 255, green: 20.0 / 255, blue: 20.0 / 255)
    public var focus = Color(red: 48.0 / 255, green: 209.0 / 255, blue: 88.0 / 255)
    public var area = Color(red: 10.0 / 255, green: 132.0 / 255, blue: 1)
    public var letters = ElementSearch.alphabet
    public var scrollStep = ScrollKeys.step
    public var scrollDashFactor = ScrollKeys.dashFactor
    public static let letterCount = 4...26
    public static let stepRange = 10.0...500.0
    public static let dashFactorRange = 1.0...20.0
    public init() {}
}

public enum SelectAction: String, Sendable, CaseIterable {
    case copy, rightClick = "right_click", extend, search, expand
    case left, right, down, up
    case nextWord = "next_word", previousWord = "previous_word", wordEnd = "word_end"
    case lineStart = "line_start", lineEnd = "line_end"
}

public struct SelectSettings: Sendable, Equatable {
    public static let defaultKeys: [SelectAction: [String]] = [
        .copy: ["y", "cmd-c", "enter"], .rightClick: ["shift-enter"], .extend: ["v"], .search: ["slash", "backspace"], .expand: ["space"],
        .left: ["h", "left"], .right: ["l", "right"], .down: ["j", "down"], .up: ["k", "up"],
        .nextWord: ["w"], .previousWord: ["b"], .wordEnd: ["e"],
        .lineStart: ["0", "cmd-left"], .lineEnd: ["4", "shift-4", "cmd-right"],
    ]

    public var keys = SelectSettings.defaultKeys
    public init() {}

    public static func chordName(key: String, control: Bool, option: Bool, shift: Bool, command: Bool) -> String {
        ((control ? ["ctrl"] : []) + (option ? ["alt"] : []) + (shift ? ["shift"] : []) + (command ? ["cmd"] : []) + [key]).joined(separator: "-")
    }

    public var actions: [String: SelectAction] {
        var result: [String: SelectAction] = [:]
        for (action, chords) in keys { for chord in chords { result[chord] = action } }
        return result
    }

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

    public var reservedLetters: Set<Character> {
        Set(keys.values.joined().compactMap { $0.count == 1 ? $0.first : nil })
    }
}

public struct FloatingSettings: Sendable, Equatable {
    public var rememberPosition = true
    public init() {}
}

public struct SpecialSettings: Sendable, Equatable {
    public static let minSize = 0.5
    public var size: Double = 0.9
    public var backdrop = Color.clear
    public var hideOnOtherMonitor = false
    public init() {}
}

/// Where wm listens for keys and what its own key events look like (`binds.event_level`).
public enum EventLevel: String, Sendable, CaseIterable {
    /// A session event tap, and events with no source: what an app does.
    case session
    /// A HID event tap (before the session one), and events that come from the HID system state, as if a keyboard sent them.
    case hid
}

public struct BindSettings: Sendable, Equatable {
    public var eventLevel: EventLevel = .session
    public var longPressTimeout: Double = 0.4
    public var disableSystemCmdTab = false
    public var capsLockHyper = false
    public init() {}
}

public struct SwitcherSettings: Sendable, Equatable {
    public var thumbnails = true
    public var delay: Double = 0.12
    public var maxScale: Double = 0.85
    public init() {}
}

public struct FocusFollowsMouse: Sendable, Equatable {
    public var enabled = false
    public var onlyFullyVisible = false
    public init(enabled: Bool = false, onlyFullyVisible: Bool = false) {
        self.enabled = enabled
        self.onlyFullyVisible = onlyFullyVisible
    }
}

public struct TrackpadSettings: Sendable, Equatable {
    public var enabled = true
    public var fingers = 4
    public var scrollFingers = 4
    public var speed = 1.0
    public var titleBar = false
    public var titleBarHeight = 40.0
    public var pinch = true
    public var warnsWhenMissing = false
    public init(enabled: Bool = true, fingers: Int = 4, scrollFingers: Int = 4, speed: Double = 1, warnsWhenMissing: Bool = false) {
        self.enabled = enabled
        self.fingers = fingers
        self.scrollFingers = scrollFingers
        self.speed = speed
        self.warnsWhenMissing = warnsWhenMissing
    }
}

public struct MouseSettings: Sendable, Equatable {
    public var moveModifier: String?
    public var resizeModifier: String?
    public init(moveModifier: String? = nil, resizeModifier: String? = nil) {
        self.moveModifier = moveModifier
        self.resizeModifier = resizeModifier
    }
}

public struct MenuBarSettings: Sendable, Equatable {
    public enum Workspaces: String, Sendable, CaseIterable {
        case occupied
        case current
    }

    public var workspaces: Workspaces = .occupied
    public var current = "{mode}:{name}"
    public var other = "{name}"
    public var separator = " "
    public var modes: [LayoutKind: String] = [:]
    public init() {}
}

public struct Settings: Sendable, Equatable {
    public var layout: LayoutKind = .tiling
    public var gaps = Gaps(inner: 8, outer: 8)
    public var animations = AnimationSettings()
    public var border = BorderSettings()
    public var dim = DimSettings()
    public var pip = PipSettings()
    public var swallow = SwallowSettings()
    public var urgent = UrgentSettings()
    public var tabIndicator = TabIndicatorSettings()
    public var focusFollowsMouse = FocusFollowsMouse()
    public var mouseFollowsFocus = false
    public var startAtLogin = false
    public var wrapFocus = false
    public var mouse = MouseSettings()
    public var trackpad = TrackpadSettings()
    public var workspaceBackAndForth = false
    public var workspaceMode: WorkspaceMode = .emulated
    public var workspaceLimit: Int?
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
    public var urlAllow: [String] = []
    public init() {}

    public func templates(for layout: LayoutKind) -> [SplitTemplate] {
        switch layout {
        case .tiling, .floating: tiling.templates
        case .scrolling: scrolling.templates
        case .master, .monocle: []
        }
    }
}
