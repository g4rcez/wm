import Core
import Foundation

public struct ConfigError: Error, Sendable, Equatable, CustomStringConvertible, LocalizedError {
    public let message: String
    public init(message: String) { self.message = message }
    public var description: String { message }
    public var errorDescription: String? { message }
}

public enum BindAction: Sendable, Equatable {
    case command(String)
    case function(Int)
    case remap(Chord)
}

public enum BindTrigger: String, Sendable, Equatable {
    case press, release
    case longPress = "long_press"
    case hold = "repeat"
}

public struct BindOptions: Sendable, Equatable {
    public var description: String?
    public var repeating: Bool?
    public var universal: Bool
    public var hidden: Bool

    public init(description: String? = nil, repeating: Bool? = nil, universal: Bool = false, hidden: Bool = false) {
        self.description = description
        self.repeating = repeating
        self.universal = universal
        self.hidden = hidden
    }
}

public struct ModeOptions: Sendable, Equatable {
    public var once: Bool
    public var swallow: Bool
    public var timeout: Double?

    public init(once: Bool = false, swallow: Bool = false, timeout: Double? = nil) {
        self.once = once
        self.swallow = swallow
        self.timeout = timeout
    }
}

public enum BindSource: String, Sendable, Equatable {
    case lua, shortcuts
}

public struct BindOverride: Sendable, Equatable, CustomStringConvertible {
    public var mode: String
    public var keys: String
    public var trigger: BindTrigger
    public var kept: BindSource
    public var replacedAction: String

    public init(mode: String, keys: String, trigger: BindTrigger, kept: BindSource, replacedAction: String) {
        self.mode = mode
        self.keys = keys
        self.trigger = trigger
        self.kept = kept
        self.replacedAction = replacedAction
    }

    public var identity: String { "\(mode)|\(keys)|\(trigger.rawValue)" }

    public var description: String {
        let winner = kept == .lua ? "init.lua" : shortcutsFileName
        let loser = kept == .lua ? shortcutsFileName : "init.lua"
        return "\(mode): \(keys) (\(winner) replaces \(loser): \(replacedAction))"
    }
}

public struct BindRecord: Sendable, Equatable {
    public var mode: String
    public var keys: String
    public var trigger: BindTrigger
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

public let universalMode = "*"

public struct WorkspaceRule: Sendable, Equatable {
    public var layout: LayoutKind?
    public var monitor: String?
    public var isDefault = false
    public var overrides: LuaValue?
    public var onEmpty: ExecRequest?
    public var persistent = false
    public var wallpaper: String?
    public var space: Int?

    public init(
        layout: LayoutKind? = nil, monitor: String? = nil, isDefault: Bool = false, overrides: LuaValue? = nil,
        onEmpty: ExecRequest? = nil, persistent: Bool = false, wallpaper: String? = nil, space: Int? = nil
    ) {
        self.space = space
        self.wallpaper = wallpaper
        self.layout = layout
        self.monitor = monitor
        self.isDefault = isDefault
        self.overrides = overrides
        self.onEmpty = onEmpty
        self.persistent = persistent
    }
}

public struct RuleSize: Sendable, Equatable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct WindowRule: Sendable, Equatable {
    public var name: String?
    public var app: String?
    public var title: String?
    public var role: String?
    public var subrole: String?
    public var identifier: String?
    public var float: Bool?
    public var workspace: String?
    public var layout: LayoutKind?
    public var size: RuleSize?
    public var center: Bool
    public var maximize: Bool?
    public var width: Double?
    public var monitor: String?
    public var focus: Bool?
    public var border: [Color]?
    /// `false` keeps the window bright, `true` dims it even when `dim.enabled` is off.
    public var dim: Bool?
    public var commands: [String]
    public var stop: Bool
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
        result.dim = later.dim ?? result.dim
        result.commands += later.commands
        return result
    }
}

public struct LoadedConfig: Sendable {
    public var settings: Settings
    public var binds: [String: [Chord: BindAction]]
    public var sequences: [String: [[Chord]: BindAction]]
    public var releaseBinds: [String: [Chord: BindAction]]
    public var longPressBinds: [String: [Chord: BindAction]]
    public var holdBinds: [String: [Chord: BindAction]]
    public var noRepeat: [String: Set<Chord>]
    public var bindRecords: [BindRecord]
    public var overrides: [BindOverride]
    public var shortcutsImported: Bool
    public var gestures: [Gesture]
    public var modeOptions: [String: ModeOptions]
    public var longPressTimeouts: [String: [Chord: Double]]
    public var rules: [WindowRule]
    public var workspaceLayouts: [String: LayoutKind]
    public var workspaceRules: [String: WorkspaceRule]
    public var idleThresholds: [Double]

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
        shortcutsImported: Bool = false,
        idleThresholds: [Double] = []
    ) {
        self.idleThresholds = idleThresholds
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

public struct ExecOptions: Equatable, Sendable {
    public static let defaultTimeout = 15.0
    public static let minTimeout = 1.0
    public static let maxTimeout = 600.0

    public var rule: WindowRule
    public var timeout: Double
    public var app: String?

    public init(rule: WindowRule, timeout: Double = ExecOptions.defaultTimeout, app: String? = nil) {
        self.rule = rule
        self.timeout = timeout
        self.app = app
    }
}

public struct ExecRequest: Equatable, Sendable {
    public var command: String
    public var options: ExecOptions?
    public var rule: WindowRule? { options?.rule }

    public init(command: String, options: ExecOptions? = nil) {
        self.command = command
        self.options = options
    }
}

public protocol HostBridge: AnyObject, Sendable {
    func dispatch(_ command: String, window: UInt32?) -> (exitCode: Int32, stdout: String, stderr: String)
    func query(_ what: String) -> LuaValue
    func exec(_ command: String)
    func exec(_ command: String, options: ExecOptions)
    func log(_ message: String)
    func logError(_ message: String)
    /// `false` when the config only loads to be checked or read (`wm config check`, `wm doctor`, the cheatsheet without a
    /// daemon): the Lua functions that run programs, change files or load native code do nothing then, so a check is safe
    /// on a file from someone else.
    var runsConfigEffects: Bool { get }
}

public extension HostBridge {
    var runsConfigEffects: Bool { true }
    func logError(_ message: String) { log(message) }
    func exec(_ command: String, options: ExecOptions) { exec(command) }
}
