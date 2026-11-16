import Core
import Foundation
import Testing
@testable import Scripting

/// The app boundary. Records what the Lua side sends and answers from fixed tables.
final class FakeBridge: HostBridge, @unchecked Sendable {
    private let lock = NSLock()
    private var _logs: [String] = []
    private var _execs: [String] = []
    private var _dispatched: [String] = []
    private var _dispatchedWindows: [UInt32?] = []

    var dispatchResults: [String: (exitCode: Int32, stdout: String, stderr: String)] = [:]
    var queryResults: [String: LuaValue] = [:]

    var logs: [String] { lock.withLock { _logs } }
    var execs: [String] { lock.withLock { _execs } }
    var dispatched: [String] { lock.withLock { _dispatched } }
    var dispatchedWindows: [UInt32?] { lock.withLock { _dispatchedWindows } }

    func dispatch(_ command: String, window: UInt32?) -> (exitCode: Int32, stdout: String, stderr: String) {
        lock.withLock {
            _dispatched.append(command)
            _dispatchedWindows.append(window)
        }
        return dispatchResults[command] ?? (0, "", "")
    }

    func query(_ what: String) -> LuaValue { queryResults[what] ?? .nil }
    func exec(_ command: String) { lock.withLock { _execs.append(command) } }
    func log(_ message: String) { lock.withLock { _logs.append(message) } }
}

/// A temporary config directory. Files are written next to each other so `require` can find them.
struct ConfigDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("wm-lua-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    @discardableResult
    func write(_ name: String, _ text: String) throws -> URL {
        let file = url.appendingPathComponent(name)
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}

private let sampleConfig = """
local mod = "alt"

wm.config {
  layout = "scrolling",
  gaps = { inner = 10, outer = { top = 12, right = 8, bottom = 6, left = 4 } },
  animations = { enabled = true, rate = 20 },
  border = { enabled = true, width = 3, radius = 12, active = "#89b4fa", inactive = "#00000000" },
  focus_follows_mouse = true,
  tab_indicator = { enabled = false, position = "right", size = 8, spacing = 2, radius = 4, active = "#ff0000", inactive = "#00000080" },
  tiling = { split_ratio = 0.6, preserve_split = false, force_split = "first", split_width_multiplier = 1.5 },
  scrolling = { presets = { 0.33, 0.5, 0.66 }, default_width = 0.5, center = "always",
                always_center_single_column = true, default_column_display = "tabbed", preset_heights = { 0.25, 0.5 },
                vertical = { side = "left", width = 0.3, row_height = 0.4 } },
  switcher = { thumbnails = false, delay = 0, background = "#00000080", selected = "#ff0000", max_scale = 0.5 },
  url = { allow = { "exec" } },
}

wm.bind(mod .. "-h", "focus left")
wm.bind(mod .. "-j", "focus down")
wm.bind(mod .. "-k", "focus up")
wm.bind(mod .. "-l", "focus right")
wm.bind(mod .. "-shift-h", "move left")
wm.bind(mod .. "-1", "workspace 1")
wm.bind("cmd + ctrl - 2", "workspace 2")
wm.bind(mod .. "-space", "")
wm.bind(mod .. "-w", "mode windows")
wm.bind(mod .. "-r", "mode resize")
wm.bind(mod .. "-t", function() wm.exec("open -a Terminal") end)

wm.mode("windows", {
  ["h"] = "move left",
  ["l"] = "move right",
  ["f"] = "toggle-float",
  ["x"] = "close",
  ["esc"] = "mode main",
})

wm.mode("resize", {
  ["h"] = "resize width -40",
  ["l"] = "resize width 40",
  ["j"] = "resize height 40",
  ["esc"] = "mode main",
})

wm.rule { app = "com.apple.finder", float = true, center = true, size = { 0.62, 0.68 } }
wm.rule { app = "Spotify", workspace = "9", layout = "tiling", run = "focus left", stop = false }
wm.rule { title = "^Picture in Picture$", float = true, run = { "layout tiling", "focus right" } }
wm.rule { app = "Notes", maximize = true, width = 0.4, monitor = 2, focus = false }
wm.rule { app = "Mail", monitor = "Studio" }
"""

@Suite("LuaHost", .serialized)
struct LuaHostTests {
    let bridge = FakeBridge()
    let host: LuaHost
    let dir: ConfigDir

    init() throws {
        host = LuaHost(bridge: bridge)
        dir = try ConfigDir()
    }

    @Test func sampleConfigLoadsSettings() throws {
        let config = try host.load(configURL: dir.write("init.lua", sampleConfig))
        let settings = config.settings

        #expect(settings.layout == .scrolling)
        #expect(settings.gaps == Gaps(inner: 10, top: 12, right: 8, bottom: 6, left: 4))
        #expect(settings.animations.rate == 20)
        #expect(settings.border.enabled == true)
        #expect(settings.border.width == 3)
        #expect(settings.border.radius == 12)
        #expect(settings.border.active == Color(red: 137.0 / 255, green: 180.0 / 255, blue: 250.0 / 255))
        #expect(settings.border.inactive == Color(red: 0, green: 0, blue: 0, alpha: 0))
        #expect(settings.focusFollowsMouse == true)
        #expect(settings.tabIndicator.enabled == false)
        #expect(settings.tabIndicator.position == .right)
        #expect(settings.tabIndicator.size == 8)
        #expect(settings.tabIndicator.spacing == 2)
        #expect(settings.tabIndicator.radius == 4)
        #expect(settings.tabIndicator.active == Color(red: 1, green: 0, blue: 0))
        #expect(settings.tabIndicator.inactive == Color(red: 0, green: 0, blue: 0, alpha: 128.0 / 255))
        #expect(settings.mouseFollowsFocus == false)
        #expect(settings.tiling.splitRatio == 0.6)
        #expect(settings.tiling.preserveSplit == false)
        #expect(settings.tiling.forceSplit == .first)
        #expect(settings.tiling.splitWidthMultiplier == 1.5)
        #expect(settings.scrolling.presets == [0.33, 0.5, 0.66])
        #expect(settings.scrolling.center == .always)
        #expect(settings.scrolling.alwaysCenterSingleColumn == true)
        #expect(settings.scrolling.defaultColumnDisplay == .tabbed)
        #expect(settings.scrolling.presetHeights == [0.25, 0.5])
        #expect(settings.scrolling.vertical.side == .left)
        #expect(settings.scrolling.vertical.width == 0.3)
        #expect(settings.scrolling.vertical.rowHeight == 0.4)
        #expect(settings.switcher.thumbnails == false)
        #expect(settings.switcher.delay == 0)
        #expect(settings.switcher.background == Color(red: 0, green: 0, blue: 0, alpha: 128.0 / 255))
        #expect(settings.switcher.selected == Color(red: 1, green: 0, blue: 0))
        #expect(settings.switcher.maxScale == 0.5)
        #expect(settings.urlAllow == ["exec"])
    }

    @Test func sampleConfigLoadsBinds() throws {
        let config = try host.load(configURL: dir.write("init.lua", sampleConfig))

        #expect(config.binds["main"]?.count == 11)
        #expect(config.binds["windows"]?.count == 5)
        #expect(config.binds["resize"]?.count == 4)
        #expect(config.binds["main"]?[try parseChord("alt-h")] == .command("focus left"))
        #expect(config.binds["main"]?[try parseChord("alt-2")] == nil)
        #expect(config.binds["main"]?[try parseChord("ctrl+cmd+2")] == .command("workspace 2"))
        #expect(config.binds["main"]?[try parseChord("alt-space")] == .command("noop"))
        #expect(config.binds["resize"]?[try parseChord("h")] == .command("resize width -40"))
        #expect(config.binds["windows"]?[try parseChord("esc")] == .command("mode main"))
    }

    @Test func sampleConfigLoadsRules() throws {
        let config = try host.load(configURL: dir.write("init.lua", sampleConfig))

        #expect(config.rules == [
            WindowRule(app: "com.apple.finder", float: true, size: RuleSize(width: 0.62, height: 0.68), center: true),
            WindowRule(app: "Spotify", workspace: "9", layout: .tiling, commands: ["focus left"], stop: false),
            WindowRule(title: "^Picture in Picture$", float: true, commands: ["layout tiling", "focus right"]),
            WindowRule(app: "Notes", maximize: true, width: 0.4, monitor: "2", focus: false),
            WindowRule(app: "Mail", monitor: "Studio"),
        ])
    }

    @Test func bindOptionsSetTheTriggerTheDescriptionAndTheMode() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.bind("alt-a", "focus left", { description = "Left", repeating = false })
        wm.bind("alt-b", "focus right", { release = true })
        wm.bind("alt-c", "focus up", { long_press = true, description = "Up when held" })
        wm.bind("alt-d", "focus down", { universal = true })
        wm.mode("resize", { h = { "resize width +50", description = "Wider" }, esc = "mode main" })
        """))
        let a = try parseChord("alt-a"), b = try parseChord("alt-b"), c = try parseChord("alt-c"), d = try parseChord("alt-d")

        #expect(config.binds["main"]?[a] == .command("focus left"))
        #expect(config.noRepeat["main"] == [a])
        #expect(config.releaseBinds["main"]?[b] == .command("focus right"))
        #expect(config.binds["main"]?[b] == nil)
        #expect(config.longPressBinds["main"]?[c] == .command("focus up"))
        #expect(config.binds[universalMode]?[d] == .command("focus down"))
        #expect(config.binds["resize"]?[try parseChord("h")] == .command("resize width +50"))
        #expect(config.bindRecords.filter { $0.mode != "resize" } == [
            BindRecord(mode: "main", keys: "alt-a", trigger: .press, action: "focus left", options: BindOptions(description: "Left", repeating: false)),
            BindRecord(mode: "main", keys: "alt-b", trigger: .release, action: "focus right", options: BindOptions()),
            BindRecord(mode: "main", keys: "alt-c", trigger: .longPress, action: "focus up", options: BindOptions(description: "Up when held")),
            BindRecord(mode: "*", keys: "alt-d", trigger: .press, action: "focus down", options: BindOptions(universal: true)),
        ])
        #expect(config.bindRecords.contains {
            $0.mode == "resize" && $0.keys == "h" && $0.options.description == "Wider" && $0.action == "resize width +50"
        })
    }

    @Test func aPressBindAndALongPressBindCanShareAChord() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.bind("alt-a", "focus left")
        wm.bind("alt-a", "focus right", { long_press = true })
        """))
        let a = try parseChord("alt-a")
        #expect(config.binds["main"]?[a] == .command("focus left"))
        #expect(config.longPressBinds["main"]?[a] == .command("focus right"))
        #expect(config.bindRecords.count == 2)
    }

    @Test func bindingTheSameKeyAgainReplacesItsRecord() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.bind("alt-a", "focus left")
        wm.bind("alt-a", "focus right")
        """))
        #expect(config.bindRecords == [BindRecord(mode: "main", keys: "alt-a", trigger: .press, action: "focus right", options: BindOptions())])
    }

    @Test(arguments: [
        ("wm.bind('alt-a', 'x', { release = true, long_press = true })", "cannot be both 'release' and 'long_press'"),
        ("wm.bind('alt-a>b', 'x', { release = true })", "'release' and 'long_press' need a single chord"),
        ("wm.bind('alt-a', 'x', { release = true, repeating = false })", "'repeating' applies to binds that run when the key goes down"),
        ("wm.bind('alt-a', 'x', { colour = 1 })", "unknown key 'colour'"),
        ("wm.bind('alt-a', 'x', { description = 5 })", "'description' must be a string"),
        ("wm.bind('alt-a', 'x', 'fast')", "the options must be a table"),
        ("wm.mode('*', {})", "'*' is reserved"),
    ])
    func bindOptionErrorsNameTheProblem(script: String, expected: String) throws {
        let error = #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.write("init.lua", script))
        }
        #expect(error?.message.contains(expected) == true)
    }

    @Test func gesturesNeedAModifierADirectionAndACommand() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.gesture { mods = "alt", direction = "left", command = "workspace prev", description = "Previous workspace" }
        wm.gesture { mods = "alt+shift", direction = "right", command = function() end, threshold = 200 }
        """))

        #expect(config.gestures.count == 2)
        #expect(config.gestures[0] == Gesture(
            modifiers: .option, direction: .left, action: .command("workspace prev"), threshold: 100, description: "Previous workspace"))
        #expect(config.gestures[1].modifiers == [.option, .shift])
        #expect(config.gestures[1].direction == .right)
        #expect(config.gestures[1].threshold == 200)
        if case .function = config.gestures[1].action {} else { Issue.record("expected a function action") }
        #expect(config.bindRecords.map(\.keys) == ["alt-scroll left", "alt-shift-scroll right"])
        #expect(config.bindRecords.allSatisfy { $0.mode == "gesture" })
    }

    @Test func aGestureForTheSameModifiersAndDirectionReplacesTheOldOne() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.gesture { mods = "alt", direction = "left", command = "workspace prev" }
        wm.gesture { mods = "alt", direction = "left", command = "workspace next" }
        """))
        #expect(config.gestures == [Gesture(modifiers: .option, direction: .left, action: .command("workspace next"))])
    }

    @Test(arguments: [
        ("wm.gesture { direction = 'left', command = 'x' }", "needs 'mods'"),
        ("wm.gesture { mods = 'alt', command = 'x' }", "needs a 'direction'"),
        ("wm.gesture { mods = 'alt', direction = 'left' }", "needs a 'command'"),
        ("wm.gesture { mods = 'alt', direction = 'diagonal', command = 'x' }", "'direction' must be one of"),
        ("wm.gesture { mods = 'hyper', direction = 'left', command = 'x' }", "unknown modifier 'hyper'"),
        ("wm.gesture { mods = '', direction = 'left', command = 'x' }", "needs at least one modifier"),
        ("wm.gesture { mods = 'alt', direction = 'left', command = '  ' }", "'command' must not be empty"),
        ("wm.gesture { mods = 'alt', direction = 'left', command = 'x', threshold = 1 }", "'threshold' must be between 10 and 2000"),
        ("wm.gesture { mods = 'alt', direction = 'left', command = 'x', fingers = 3 }", "unknown key 'fingers'"),
        ("wm.gesture('alt')", "wm.gesture expects a table"),
    ])
    func gestureErrorsNameTheProblem(script: String, expected: String) throws {
        let error = #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.write("init.lua", script))
        }
        #expect(error?.message.contains(expected) == true)
    }

    @Test func bindSettingsSetTheLongPressTimeout() throws {
        let config = try host.load(configURL: dir.write("init.lua", "wm.config { binds = { long_press_timeout = 0.6 } }"))
        #expect(config.settings.binds.longPressTimeout == 0.6)
        let error = #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.write("init.lua", "wm.config { binds = { long_press_timeout = 9 } }"))
        }
        #expect(error?.message.contains("'binds.long_press_timeout' must be between 0.1 and 3") == true)
    }

    @Test(arguments: ["top-left", "top-center", "top-right", "center", "bottom-left", "bottom-center", "bottom-right"])
    func theLabelCanBePlacedInEachOfTheSevenPositions(name: String) throws {
        let config = try host.load(configURL: dir.write("init.lua", "wm.config { prefix = { label = { position = '\(name)' } } }"))
        #expect(config.settings.prefix.label.position.rawValue == name)
    }

    @Test func topAndBottomStayAsNamesForTheCenteredPositions() throws {
        let top = try host.load(configURL: dir.write("init.lua", "wm.config { prefix = { label = { position = 'top' } } }"))
        #expect(top.settings.prefix.label.position == .topCenter)
        let bottom = try host.load(configURL: dir.write("init.lua", "wm.config { prefix = { label = { position = 'bottom' } } }"))
        #expect(bottom.settings.prefix.label.position == .bottomCenter)
    }

    @Test func theLabelListsKeysByDefaultAndTakesAnAccentColor() throws {
        let defaults = try host.load(configURL: dir.write("init.lua", ""))
        #expect(defaults.settings.prefix.label.showKeys)
        #expect(defaults.settings.prefix.label.position == .bottomCenter)
        let config = try host.load(configURL: dir.write("init.lua", "wm.config { prefix = { label = { show_keys = false, accent = '#ff0000' } } }"))
        #expect(!config.settings.prefix.label.showKeys)
        #expect(config.settings.prefix.label.accent == Color(red: 1, green: 0, blue: 0))
    }

    @Test func aBindCanBeHiddenFromTheKeyList() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.bind("alt-a", "focus left", { hidden = true })
        wm.mode("m", { h = { "focus right", hidden = true, description = "Right" } })
        """))
        #expect(config.bindRecords.first { $0.keys == "alt-a" }?.options.hidden == true)
        #expect(config.bindRecords.first { $0.mode == "m" }?.options == BindOptions(description: "Right", hidden: true))
    }

    @Test func theLabelFontCanBeNamed() throws {
        let config = try host.load(configURL: dir.write("init.lua", "wm.config { prefix = { label = { font = 'Menlo' } } }"))
        #expect(config.settings.prefix.label.fontName == "Menlo")
        let empty = try host.load(configURL: dir.write("init.lua", "wm.config { prefix = { label = { font = '' } } }"))
        #expect(empty.settings.prefix.label.fontName == nil)
    }

    @Test(arguments: [
        ("wm.config { prefix = { label = { show_keys = 'yes' } } }", "'prefix.label.show_keys' must be true or false"),
        ("wm.config { prefix = { label = { font = 5 } } }", "'prefix.label.font' must be a string"),
        ("wm.config { prefix = { label = { accent = 'blue' } } }", "'prefix.label.accent' must be a color"),
        ("wm.bind('alt-a', 'x', { hidden = 'yes' })", "'hidden' must be true or false"),
    ])
    func labelOptionErrorsNameTheProblem(script: String, expected: String) throws {
        let error = #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.write("init.lua", script))
        }
        #expect(error?.message.contains(expected) == true)
    }

    // MARK: the type stubs that editors read

    private func typeStubs() throws -> String {
        // Tests/ScriptingTests/LuaHostTests.swift -> the repository root.
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent("types/wm.lua"), encoding: .utf8)
    }

    @Test func everyFunctionOfTheWmTableHasATypeStub() throws {
        try host.load(configURL: dir.write("init.lua", """
        local names = {}
        for key in pairs(wm) do names[#names + 1] = key end
        table.sort(names)
        wm.log(table.concat(names, ","))
        """))
        let names = try #require(bridge.logs.first).split(separator: ",").map(String.init)
        let stubs = try typeStubs()
        #expect(!names.isEmpty)
        for name in names {
            #expect(stubs.contains("function wm.\(name)(") || stubs.contains("---@field \(name) "), "types/wm.lua does not describe wm.\(name)")
        }
    }

    @Test func everyConfigKeyHasATypeStub() throws {
        let stubs = try typeStubs()
        for key in topLevelConfigKeys {
            #expect(stubs.contains("---@field \(key)? "), "types/wm.lua does not describe the config key '\(key)'")
        }
    }

    @Test func functionBindRunsOnTheLuaThread() throws {
        let config = try host.load(configURL: dir.write("init.lua", sampleConfig))
        let action = try #require(config.binds["main"]?[try parseChord("alt-t")])
        guard case .function(let id) = action else {
            Issue.record("alt-t is not a function bind")
            return
        }

        host.call(function: id)
        host.flush()

        #expect(bridge.execs == ["open -a Terminal"])
    }

    @Test func configCallsMerge() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.config { gaps = { inner = 4 }, layout = "scrolling" }
        wm.config { gaps = { outer = 2 } }
        """))

        #expect(config.settings.layout == .scrolling)
        #expect(config.settings.gaps == Gaps(inner: 4, outer: 2))
    }

    @Test func workspacesCanHaveTheirOwnLayout() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.config { layout = "scrolling" }
        wm.workspace("1", { layout = "tiling" })
        wm.workspace(2, { layout = "scrolling" })
        wm.workspace("2/2", { layout = "tiling" })
        """))

        #expect(config.settings.layout == .scrolling)
        #expect(config.workspaceLayouts == ["1": .tiling, "2": .scrolling, "2/2": .tiling])
    }

    @Test func workspaceRulesBindMonitorsAndOverrideSettings() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.workspace("web", { monitor = 2, default = true, gaps = { inner = 0, outer = 0 }, border = false })
        wm.workspace("code", { layout = "scrolling", monitor = "LG", layout_options = { default_width = 0.7, split_ratio = 0.6 } })
        """))

        let web = try #require(config.workspaceRules["web"])
        #expect(web.monitor == "2")
        #expect(web.isDefault)
        #expect(web.layout == nil)
        var settings = Settings()
        try applyWorkspaceOverrides(try #require(web.overrides), to: &settings)
        #expect(settings.gaps == Gaps(inner: 0, outer: 0))
        #expect(settings.border.enabled == false)

        let code = try #require(config.workspaceRules["code"])
        #expect(code.monitor == "LG")
        #expect(code.layout == .scrolling)
        var other = Settings()
        try applyWorkspaceOverrides(try #require(code.overrides), to: &other)
        #expect(other.scrolling.defaultWidth == 0.7)
        #expect(other.tiling.splitRatio == 0.6)
        #expect(config.workspaceLayouts == ["code": .scrolling])
    }

    @Test func aWorkspaceDefinedTwiceKeepsTheLastLayout() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.workspace("1", { layout = "scrolling" })
        wm.workspace("1", { layout = "tiling" })
        """))

        #expect(config.workspaceLayouts == ["1": .tiling])
    }

    @Test func definingAModeTwiceReplacesIt() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.mode("m", { a = "first", b = "second" })
        wm.mode("m", { c = "third" })
        """))

        #expect(config.binds["m"] == [try parseChord("c"): .command("third")])
    }

    @Test func requireFindsSiblingFile() throws {
        try dir.write("colors.lua", "return { active = '#112233' }")
        let config = try host.load(configURL: dir.write("init.lua", """
        local colors = require("colors")
        wm.config { border = { active = colors.active } }
        """))

        #expect(config.settings.border.active == Color(red: 17.0 / 255, green: 34.0 / 255, blue: 51.0 / 255))
    }

    @Test func eventFiltersMatchPayloadValues() throws {
        _ = try host.load(configURL: dir.write("init.lua", """
        wm.on("focus", function(p) wm.log("any", p.app) end)
        wm.on("focus", { app = "Safari" }, function(p) wm.log("safari", p.app) end)
        wm.on("focus", { app = "Safari", pid = 7 }, function(p) wm.log("safari-7", p.pid) end)
        """))

        host.fire(event: "focus", payload: ["app": .string("Safari"), "pid": .number(7)])
        host.fire(event: "focus", payload: ["app": .string("Mail"), "pid": .number(7)])
        host.fire(event: "other", payload: ["app": .string("Safari")])
        host.flush()

        #expect(bridge.logs == ["any Safari", "safari Safari", "safari-7 7", "any Mail"])
    }

    @Test func failingHandlerDoesNotStopOthers() throws {
        _ = try host.load(configURL: dir.write("init.lua", """
        wm.on("tick", function() wm.log("first") end)
        wm.on("tick", function() error("boom") end)
        wm.on("tick", function() wm.log("third") end)
        """))

        host.fire(event: "tick", payload: [:])
        host.flush()

        let logs = bridge.logs
        #expect(logs.count == 3)
        #expect(logs[0] == "first")
        #expect(logs[1].contains("boom"))
        #expect(logs[1].contains("tick"))
        #expect(logs[2] == "third")
    }

    @Test func failedReloadKeepsThePreviousState() throws {
        _ = try host.load(configURL: dir.write("good.lua", """
        wm.on("tick", function() wm.log("old handler") end)
        """))

        let syntax = #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.write("syntax.lua", "wm.config {"))
        }
        let runtime = #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.write("runtime.lua", """
            wm.on("tick", function() wm.log("new handler") end)
            error("boom")
            """))
        }
        host.fire(event: "tick", payload: [:])
        host.flush()

        #expect(syntax?.message.contains("syntax.lua:1:") == true)
        #expect(runtime?.message.contains("runtime.lua:2: boom") == true)
        #expect(bridge.logs == ["old handler"])
    }

    @Test func missingFileThrows() {
        let error = #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.url.appendingPathComponent("nope.lua"))
        }
        #expect(error?.message.contains("nope.lua") == true)
    }

    @Test func reloadReplacesHandlers() throws {
        let file = try dir.write("init.lua", "wm.on('tick', function() wm.log('v1') end)")
        _ = try host.load(configURL: file)
        try dir.write("init.lua", "wm.on('tick', function() wm.log('v2') end)")
        _ = try host.load(configURL: file)

        host.fire(event: "tick", payload: [:])
        host.flush()

        #expect(bridge.logs == ["v2"])
    }

    @Test func staleFunctionIDIsIgnoredAfterReload() throws {
        let first = try host.load(configURL: dir.write("a.lua", "wm.bind('alt-a', function() wm.exec('old') end)"))
        let second = try host.load(configURL: dir.write("b.lua", "wm.bind('alt-a', function() wm.exec('new') end)"))
        let chord = try parseChord("alt-a")
        guard case .function(let oldID)? = first.binds["main"]?[chord], case .function(let newID)? = second.binds["main"]?[chord] else {
            Issue.record("alt-a is not a function bind")
            return
        }

        host.call(function: oldID)
        host.flush()
        #expect(bridge.execs == [])

        host.call(function: newID)
        host.flush()
        #expect(bridge.execs == ["new"])
    }

    @Test func failingFunctionBindIsLogged() throws {
        let config = try host.load(configURL: dir.write("init.lua", "wm.bind('alt-a', function() error('bad bind') end)"))
        guard case .function(let id)? = config.binds["main"]?[try parseChord("alt-a")] else {
            Issue.record("alt-a is not a function bind")
            return
        }

        host.call(function: id)
        host.flush()

        #expect(bridge.logs.count == 1)
        #expect(bridge.logs[0].contains("bad bind"))
    }

    @Test func hostFunctionsReachTheBridge() throws {
        bridge.dispatchResults["ok"] = (0, "out", "")
        bridge.dispatchResults["bad"] = (1, "", "nope")
        bridge.queryResults["windows"] = .array([.table(["id": .number(7), "title": .string("a")])])

        _ = try host.load(configURL: dir.write("init.lua", """
        local out = wm.dispatch("ok")
        local none, err = wm.dispatch("bad")
        local windows = wm.query("windows")
        wm.exec("open -a Notes")
        wm.log("result", out, none, err, windows[1].title, windows[1].id, #windows, wm.version)
        """))

        #expect(bridge.dispatched == ["ok", "bad"])
        #expect(bridge.execs == ["open -a Notes"])
        #expect(bridge.logs == ["result out nil nope a 7 1 \(LuaHost.apiVersion)"])
    }

    @Test(arguments: [
        ("wm.config { gapz = 1 }", "unknown key 'gapz'"),
        ("wm.config { gaps = { innr = 1 } }", "unknown key 'gaps.innr'"),
        ("wm.config { layout = 'grid' }", "'layout' must be one of"),
        ("wm.config { border = { active = 'red' } }", "'border.active' must be a color"),
        ("wm.config { border = { active = '#12345' } }", "'border.active' must be a color"),
        ("wm.config { layout = 'dwindle' }", "'layout' must be one of"),
        ("wm.config { dwindle = {} }", "unknown key 'dwindle'"),
        ("wm.config { master = {} }", "unknown key 'master'"),
        ("wm.config { tree = {} }", "unknown key 'tree'"),
        ("wm.config { tiling = { split_ratio = 2 } }", "'tiling.split_ratio' must be between 0.1 and 0.9"),
        ("wm.config { animations = { enabled = 'yes' } }", "'animations.enabled' must be true or false"),
        ("wm.config { scrolling = { vertical = { side = 'up' } } }", "'scrolling.vertical.side' must be one of"),
        ("wm.config { scrolling = { vertical = { width = 0.95 } } }", "'scrolling.vertical.width' must be between 0.1 and 0.9"),
        ("wm.config { scrolling = { vertical = { foo = 1 } } }", "unknown key 'scrolling.vertical.foo'"),
        ("wm.config { scrolling = { default_column_display = 'accordion' } }", "'scrolling.default_column_display' must be one of"),
        ("wm.config { scrolling = { always_center_single_column = 'yes' } }", "'scrolling.always_center_single_column' must be true or false"),
        ("wm.config { scrolling = { preset_heights = {} } }", "'scrolling.preset_heights' must not be empty"),
        ("wm.config { scrolling = { preset_heights = { 1 } } }", "'scrolling.preset_heights'"),
        ("wm.config { tab_indicator = { colour = 1 } }", "unknown key 'tab_indicator.colour'"),
        ("wm.config { tab_indicator = { position = 'middle' } }", "'tab_indicator.position' must be one of"),
        ("wm.config { tab_indicator = { size = 0 } }", "'tab_indicator.size' must be between 1 and 40"),
        ("wm.config { tab_indicator = { active = 'blue' } }", "'tab_indicator.active' must be a color"),
        ("wm.config { tiling = { force_split = 'left' } }", "'tiling.force_split' must be one of"),
        ("wm.config { tiling = { split_width_multiplier = 5 } }", "'tiling.split_width_multiplier' must be between 0.1 and 3"),
        ("wm.config { switcher = { foo = 1 } }", "unknown key 'switcher.foo'"),
        ("wm.config { switcher = { thumbnails = 'yes' } }", "'switcher.thumbnails' must be true or false"),
        ("wm.config { switcher = { delay = -1 } }", "'switcher.delay' must be at least 0"),
        ("wm.config { switcher = { selected = 'blue' } }", "'switcher.selected' must be a color"),
        ("wm.config { switcher = { max_scale = 2 } }", "'switcher.max_scale' must be between 0.3 and 1"),
        ("wm.bind('alt-foo', 'x')", "mode 'main': invalid chord 'alt-foo'"),
        ("wm.mode('windows', { ['alt-foo'] = 'x' })", "mode 'windows': invalid chord 'alt-foo'"),
        ("wm.bind('alt-a', 5)", "must be a command string or a function"),
        ("wm.rule { float = true }", "needs at least one match field"),
        ("wm.rule { app = 'x', colour = 1 }", "unknown key 'colour'"),
        ("wm.rule { title = '[' }", "not a valid regular expression"),
        ("wm.rule { app = 'x', width = 2 }", "'width' must be between 0.05 and 1"),
        ("wm.rule { app = 'x', monitor = 0 }", "'monitor' must be a whole number, at least 1"),
        ("wm.rule { app = 'x', focus = 'no' }", "'focus' must be true or false"),
        ("wm.rule { app = 'x', maximize = 1 }", "'maximize' must be true or false"),
        ("wm.rule { app = 'x', size = { 1 } }", "'size' must be { width, height }"),
        ("wm.workspace('1', { layout = 'grid' })", "'layout' must be one of"),
        ("wm.workspace('1', {})", "'1' needs at least one option"),
        ("wm.workspace('1', { default = true })", "has 'default' and needs a 'monitor' too"),
        ("wm.workspace('1', { monitor = 0 })", "'monitor' must be a whole number, at least 1"),
        ("wm.workspace('1', { border = 'no' })", "'border' must be true or false"),
        ("wm.workspace('1', { gaps = { inner = -1 } })", "wm.workspace '1': 'gaps.inner' must be at least 0"),
        ("wm.workspace('1', { layout_options = { nope = 1 } })", "unknown key 'layout_options.nope'"),
        ("wm.workspace('1', { layout_options = { split_ratio = 2 } })", "'tiling.split_ratio' must be between 0.1 and 0.9"),
        ("wm.workspace('1', { layout = 'tiling', colour = 2 })", "unknown key 'colour'"),
        ("wm.workspace({}, { layout = 'tiling' })", "expects a workspace name"),
        ("os.exit()", "os.exit is disabled"),
    ])
    func configErrorsNameTheProblem(script: String, expected: String) throws {
        let error = #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.write("init.lua", script))
        }
        #expect(error?.message.contains(expected) == true)
        #expect(error?.message.contains("init.lua:1:") == true)
    }

    @Test func configCannotChangeAfterLoading() throws {
        _ = try host.load(configURL: dir.write("init.lua", "wm.on('tick', function() wm.config { layout = 'scrolling' } end)"))

        host.fire(event: "tick", payload: [:])
        host.flush()

        #expect(bridge.logs.count == 1)
        #expect(bridge.logs[0].contains("can only be called while the config file loads"))
    }

    @Test func infiniteLoopIsAborted() throws {
        let start = ContinuousClock.now
        let error = #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.write("init.lua", "while true do end"))
        }
        let elapsed = ContinuousClock.now - start

        #expect(error?.message.contains("longer than 2 seconds") == true)
        #expect(elapsed < .seconds(4))
    }

    @Test func loopThatCatchesTheAbortStillEnds() throws {
        let error = #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.write("init.lua", "while true do pcall(function() while true do end end) end"))
        }

        #expect(error?.message.contains("longer than 2 seconds") == true)
    }

    @Test func slowHandlerIsAbortedAndHostKeepsWorking() throws {
        _ = try host.load(configURL: dir.write("init.lua", """
        wm.on("slow", function() while true do end end)
        wm.on("fast", function() wm.log("fast") end)
        """))

        host.fire(event: "slow", payload: [:])
        host.fire(event: "fast", payload: [:])
        host.flush()

        #expect(bridge.logs.count == 2)
        #expect(bridge.logs[0].contains("longer than 2 seconds"))
        #expect(bridge.logs[1] == "fast")
    }
}
