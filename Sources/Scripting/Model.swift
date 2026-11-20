import Core
import Foundation

public struct ConfigError: Error, Sendable, Equatable, CustomStringConvertible, LocalizedError {
    public let message: String
    public init(message: String) { self.message = message }
    public var description: String { message }
    public var errorDescription: String? { message }
}

public enum BindAction: Sendable, Equatable {
    /// A wm command line such as `workspace 1`. A bind with an empty string stores `noop`.
    case command(String)
    /// A Lua function; pass the id to `LuaHost.call(function:)`.
    case function(Int)
    /// Types this key instead of the bound one (`wm.remap`): the key goes down, repeats and comes up with it.
    case remap(Chord)
}

/// When a bind runs: when the key goes down (the default), when it comes up, when it is held for a while, or for each
/// repeat of a held key (`repeating = true`; the name in `wm list binds` is `repeat`).
public enum BindTrigger: String, Sendable, Equatable {
    case press, release
    case longPress = "long_press"
    case hold = "repeat"
}

/// The options of one bind, from the third argument of `wm.bind`.
public struct BindOptions: Sendable, Equatable {
    /// Shown by `wm list binds`.
    public var description: String?
    /// `false`: the action runs once per press and not again while the key is held (`nil`: it repeats, as it always did).
    public var repeating: Bool?
    /// The bind works in every mode, not only in the mode where it is made.
    public var universal: Bool
    /// The key is left out of the key list that the label shows (`wm list binds` still has it).
    public var hidden: Bool

    public init(description: String? = nil, repeating: Bool? = nil, universal: Bool = false, hidden: Bool = false) {
        self.description = description
        self.repeating = repeating
        self.universal = universal
        self.hidden = hidden
    }
}

/// The options of a mode, from the third argument of `wm.mode`.
public struct ModeOptions: Sendable, Equatable {
    /// After one bind of the mode has run, the mode ends and the mode before it is back (as `mode back`).
    public var once: Bool
    /// A key that the mode does not bind is not typed into the app.
    public var swallow: Bool

    public init(once: Bool = false, swallow: Bool = false) {
        self.once = once
        self.swallow = swallow
    }
}

/// Where a bind was made: a `wm.bind` call in the Lua config, or a `[[shortcut]]` of `shortcuts.toml`.
public enum BindSource: String, Sendable, Equatable {
    case lua, shortcuts
}

/// A bind that replaced another one with the same mode, keys and trigger. When `shortcuts.toml` loads before the
/// `wm.bind` calls of `init.lua` (the default), the Lua bind is the one that stays.
public struct BindOverride: Sendable, Equatable, CustomStringConvertible {
    public var mode: String
    public var keys: String
    public var trigger: BindTrigger
    /// The source of the bind that stays, and the command text of the bind that it replaced.
    public var kept: BindSource
    public var replacedAction: String

    public init(mode: String, keys: String, trigger: BindTrigger, kept: BindSource, replacedAction: String) {
        self.mode = mode
        self.keys = keys
        self.trigger = trigger
        self.kept = kept
        self.replacedAction = replacedAction
    }

    /// The same text as `Shortcut.identity`: it tells which shortcut of the file this is about.
    public var identity: String { "\(mode)|\(keys)|\(trigger.rawValue)" }

    /// For `wm doctor`: `main: alt-h (init.lua replaces shortcuts.toml: focus left)`.
    public var description: String {
        let winner = kept == .lua ? "init.lua" : shortcutsFileName
        let loser = kept == .lua ? shortcutsFileName : "init.lua"
        return "\(mode): \(keys) (\(winner) replaces \(loser): \(replacedAction))"
    }
}

/// One bind as `wm list binds` shows it.
public struct BindRecord: Sendable, Equatable {
    /// The mode name; `*` for a bind that works in every mode.
    public var mode: String
    /// The chord or sequence as it was written, for example `alt-h` or `ctrl-p>h`.
    public var keys: String
    public var trigger: BindTrigger
    /// The command text, or `function` for a Lua function.
    public var action: String
    public var options: BindOptions
    public var source: BindSource

    public init(mode: String, keys: String, trigger: BindTrigger, action: String, options: BindOptions, source: BindSource = .lua) {
        self.mode = mode
        self.keys = keys
        self.trigger = trigger
        self.action = action
        self.options = options
        self.source = source
    }
}

/// The mode name that holds the binds that work in every mode.
public let universalMode = "*"

/// What `wm.workspace` says about one workspace.
public struct WorkspaceRule: Sendable, Equatable {
    public var layout: LayoutKind?
    /// The workspace belongs to this monitor (a number, 1 is the leftmost, or part of its name): showing it shows it there.
    public var monitor: String?
    /// With `monitor`: the monitor starts with this workspace.
    public var isDefault = false
    /// Settings that this workspace changes, as a table shaped like `wm.config` (`gaps`, `border`, `tiling`,
    /// `scrolling`). Apply it with `applyWorkspaceOverrides`.
    public var overrides: LuaValue?

    public init(layout: LayoutKind? = nil, monitor: String? = nil, isDefault: Bool = false, overrides: LuaValue? = nil) {
        self.layout = layout
        self.monitor = monitor
        self.isDefault = isDefault
        self.overrides = overrides
    }
}

/// Window size of a rule. A value <= 1 is a fraction of the monitor work area, a larger value is in points.
public struct RuleSize: Sendable, Equatable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct WindowRule: Sendable, Equatable {
    /// A label for the log and for `wm.floating.disable` (the default rules have one). It does not match anything.
    public var name: String?
    /// Bundle id or app name, compared case-insensitively and exactly.
    public var app: String?
    /// Regular expression matched anywhere in the window title.
    public var title: String?
    /// Accessibility role of the window (`AXWindow`), compared case-insensitively and exactly.
    public var role: String?
    /// Accessibility subrole of the window (`AXStandardWindow`, `AXDialog`), compared case-insensitively and exactly.
    public var subrole: String?
    /// Regular expression matched anywhere in the `AXIdentifier` of the window.
    public var identifier: String?
    public var float: Bool?
    public var workspace: String?
    public var layout: LayoutKind?
    public var size: RuleSize?
    public var center: Bool
    /// The window opens maximized.
    public var maximize: Bool?
    /// Column width of a new window in the scrolling layout, as a fraction of the screen.
    public var width: Double?
    /// The window opens on the workspace that this monitor shows: a number (1 is the leftmost) or part of its name.
    public var monitor: String?
    /// `false`: the window opens without taking the focus.
    public var focus: Bool?
    /// The color of the focus border of the window: one color, or two or more for a gradient.
    public var border: [Color]?
    /// Commands that run after the other actions.
    public var commands: [String]
    /// `true`: no later rule applies to a window that matched this one.
    public var stop: Bool
    /// `true`: the rule is checked again when the title of the window changes (see `DynamicRuleTracker`).
    public var dynamic: Bool

    public init(
        app: String? = nil, title: String? = nil, role: String? = nil, subrole: String? = nil,
        identifier: String? = nil, float: Bool? = nil, workspace: String? = nil,
        layout: LayoutKind? = nil, size: RuleSize? = nil, center: Bool = false,
        maximize: Bool? = nil, width: Double? = nil, monitor: String? = nil, focus: Bool? = nil,
        commands: [String] = [], stop: Bool = true, name: String? = nil, dynamic: Bool = false, border: [Color]? = nil
    ) {
        self.name = name
        self.app = app
        self.title = title
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.float = float
        self.workspace = workspace
        self.layout = layout
        self.size = size
        self.center = center
        self.maximize = maximize
        self.width = width
        self.monitor = monitor
        self.focus = focus
        self.commands = commands
        self.stop = stop
        self.dynamic = dynamic
        self.border = border
    }
}

public extension WindowRule {
    /// True when the window has every match field of this rule. `app`, `role` and `subrole` are exact and ignore case;
    /// `title` and `identifier` are regular expressions that match anywhere.
    func matches(bundleID: String, appName: String, title windowTitle: String, role windowRole: String,
                 subrole windowSubrole: String, identifier windowIdentifier: String) -> Bool {
        if let app, app.caseInsensitiveCompare(bundleID) != .orderedSame,
           app.caseInsensitiveCompare(appName) != .orderedSame { return false }
        if let title, windowTitle.range(of: title, options: .regularExpression) == nil { return false }
        if let role, role.caseInsensitiveCompare(windowRole) != .orderedSame { return false }
        if let subrole, subrole.caseInsensitiveCompare(windowSubrole) != .orderedSame { return false }
        if let identifier, windowIdentifier.range(of: identifier, options: .regularExpression) == nil { return false }
        return true
    }

    /// This rule with `later` on top: what `later` sets wins, commands add up, and a window is centered if either says so.
    func merging(_ later: WindowRule) -> WindowRule {
        var result = self
        result.float = later.float ?? result.float
        result.workspace = later.workspace ?? result.workspace
        result.layout = later.layout ?? result.layout
        result.size = later.size ?? result.size
        result.center = later.center || result.center
        result.maximize = later.maximize ?? result.maximize
        result.width = later.width ?? result.width
        result.monitor = later.monitor ?? result.monitor
        result.focus = later.focus ?? result.focus
        result.border = later.border ?? result.border
        result.commands += later.commands
        return result
    }
}

public struct LoadedConfig: Sendable {
    public var settings: Settings
    /// Key: mode name. `main` is the default mode and is always present.
    public var binds: [String: [Chord: BindAction]]
    /// Key sequences of 2 or more chords, by mode name. A single chord is in `binds`. In one mode no chord is both
    /// a bind and the first step of a sequence, and no sequence is the start of a longer one.
    public var sequences: [String: [[Chord]: BindAction]]
    /// Binds that run when the key comes up, and binds that run when it is held (`wm.bind` with `release` or
    /// `long_press`). Only single chords, by mode name.
    public var releaseBinds: [String: [Chord: BindAction]]
    public var longPressBinds: [String: [Chord: BindAction]]
    /// Binds with `repeating = true`: they run for each repeat of a held key. The chord is also in `binds` (the same action,
    /// or the plain bind that was made for it), which runs when the key goes down.
    public var holdBinds: [String: [Chord: BindAction]]
    /// The press binds that must not repeat while the key is held, by mode name.
    public var noRepeat: [String: Set<Chord>]
    /// Every bind, in the order they were made.
    public var bindRecords: [BindRecord]
    /// The binds that replaced a bind from the other source (`wm doctor` reports them).
    public var overrides: [BindOverride]
    /// `wm.shortcuts()` ran: `init.lua` loads `shortcuts.toml`.
    public var shortcutsImported: Bool
    /// Swipes with a modifier (`wm.gesture`).
    public var gestures: [Gesture]
    /// The options of the modes that have some (`wm.mode`), by mode name.
    public var modeOptions: [String: ModeOptions]
    /// Seconds of the `long_press` binds that name their own, by mode name.
    public var longPressTimeouts: [String: [Chord: Double]]
    public var rules: [WindowRule]
    /// Layout chosen per workspace with `wm.workspace`; other workspaces use `settings.layout`.
    public var workspaceLayouts: [String: LayoutKind]
    /// Everything `wm.workspace` set, by workspace name.
    public var workspaceRules: [String: WorkspaceRule]

    public init(
        settings: Settings = Settings(),
        binds: [String: [Chord: BindAction]] = ["main": [:]],
        rules: [WindowRule] = [],
        workspaceLayouts: [String: LayoutKind] = [:],
        workspaceRules: [String: WorkspaceRule] = [:],
        sequences: [String: [[Chord]: BindAction]] = [:],
        releaseBinds: [String: [Chord: BindAction]] = [:],
        longPressBinds: [String: [Chord: BindAction]] = [:],
        holdBinds: [String: [Chord: BindAction]] = [:],
        noRepeat: [String: Set<Chord>] = [:],
        bindRecords: [BindRecord] = [],
        gestures: [Gesture] = [],
        modeOptions: [String: ModeOptions] = [:],
        longPressTimeouts: [String: [Chord: Double]] = [:],
        overrides: [BindOverride] = [],
        shortcutsImported: Bool = false
    ) {
        self.overrides = overrides
        self.shortcutsImported = shortcutsImported
        self.modeOptions = modeOptions
        self.longPressTimeouts = longPressTimeouts
        self.settings = settings
        self.binds = binds
        self.rules = rules
        self.workspaceLayouts = workspaceLayouts
        self.workspaceRules = workspaceRules
        self.sequences = sequences
        self.releaseBinds = releaseBinds
        self.longPressBinds = longPressBinds
        self.holdBinds = holdBinds
        self.noRepeat = noRepeat
        self.bindRecords = bindRecords
        self.gestures = gestures
    }
}

public enum LuaValue: Sendable, Equatable {
    case `nil`
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([LuaValue])
    case table([String: LuaValue])
}

/// What `wm exec` and `wm.exec` ask for the window that a command opens: the rule to apply, how long to wait for the window,
/// and an app that may claim it when it is not a child of the command (`open -a Notes`).
public struct ExecOptions: Equatable, Sendable {
    public static let defaultTimeout = 15.0
    public static let minTimeout = 1.0
    public static let maxTimeout = 600.0

    public var rule: WindowRule
    /// Seconds to wait for the window.
    public var timeout: Double
    /// A bundle id or an app name. A new window of this app takes the rule when no child of the command claimed it first.
    public var app: String?

    public init(rule: WindowRule, timeout: Double = ExecOptions.defaultTimeout, app: String? = nil) {
        self.rule = rule
        self.timeout = timeout
        self.app = app
    }
}

/// A `wm exec` command line: the shell command, and the options that came before it.
public struct ExecRequest: Equatable, Sendable {
    public var command: String
    public var options: ExecOptions?
    public var rule: WindowRule? { options?.rule }

    public init(command: String, options: ExecOptions? = nil) {
        self.command = command
        self.options = options
    }
}

/// The app boundary. Every method is called on the Lua thread: do not block on `LuaHost.load` from inside,
/// and avoid waiting for a thread that waits for the Lua thread.
public protocol HostBridge: AnyObject, Sendable {
    /// `window`: the command acts on this window id (`wm.dispatch(cmd, { window = id })`).
    func dispatch(_ command: String, window: UInt32?) -> (exitCode: Int32, stdout: String, stderr: String)
    func query(_ what: String) -> LuaValue
    func exec(_ command: String)
    /// `wm.exec(command, options)`: run the command, and apply the options to the window it opens.
    func exec(_ command: String, options: ExecOptions)
    func log(_ message: String)
    /// A script or a handler that failed. The default is a plain `log`.
    func logError(_ message: String)
}

public extension HostBridge {
    func logError(_ message: String) { log(message) }
    /// Default: run the command and ignore the options.
    func exec(_ command: String, options: ExecOptions) { exec(command) }
}
