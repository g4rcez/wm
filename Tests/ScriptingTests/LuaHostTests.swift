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
  animations = { enabled = true, fps = 90 },
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
        #expect(settings.animations.fps == 90)
        #expect(settings.border.enabled == true)
        #expect(settings.border.width == 3)
        #expect(settings.border.radius == 12)
        #expect(settings.border.active == Color(red: 137.0 / 255, green: 180.0 / 255, blue: 250.0 / 255))
        #expect(settings.border.inactive == Color(red: 0, green: 0, blue: 0, alpha: 0))
        #expect(settings.focusFollowsMouse.enabled == true)
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

        // The rules of the config come first; the default floating rules follow them.
        #expect(config.rules.dropFirst(5).map(\.name) == Self.defaultFloatingNames)
        #expect(Array(config.rules.prefix(5)) == [
            WindowRule(app: "com.apple.finder", float: true, size: RuleSize(width: 0.62, height: 0.68), center: true),
            WindowRule(app: "Spotify", workspace: "9", layout: .tiling, commands: ["focus left"], stop: false),
            WindowRule(title: "^Picture in Picture$", float: true, commands: ["layout tiling", "focus right"]),
            WindowRule(app: "Notes", maximize: true, width: 0.4, monitor: "2", focus: false),
            WindowRule(app: "Mail", monitor: "Studio"),
        ])
    }

    @Test func ruleMatchFieldsRoleSubroleAndIdentifierLoad() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.rule { subrole = "AXDialog", float = true }
        wm.rule { app = "Notes", role = "AXWindow", identifier = "^settings-" , float = true }
        """))

        #expect(Array(config.rules.prefix(2)) == [
            WindowRule(subrole: "AXDialog", float: true),
            WindowRule(app: "Notes", role: "AXWindow", identifier: "^settings-", float: true),
        ])
    }

    private func monitor(_ index: Int, _ name: String, role: String) -> LuaValue {
        .table(["index": .number(Double(index)), "name": .string(name), "role": .string(role)])
    }

    private func logsAfterDisplaysChange(_ monitors: [LuaValue]) -> [String] {
        bridge.queryResults["monitors"] = .array(monitors)
        host.fire(event: "displays_changed", payload: [:])
        host.flush()
        return bridge.logs
    }

    @Test func aProfileRunsWhenItsMonitorsFitAndOnlyOnceWhileItFits() throws {
        _ = try host.load(configURL: dir.write("init.lua", """
        wm.profile("desk", { monitors = { "dell", "main" }, apply = function(m) wm.log("desk", #m) end })
        wm.profile("laptop", { monitors = { "main" }, apply = function() wm.log("laptop") end })
        """))
        let dell = monitor(1, "DELL U2723", role: "secondary")
        let builtIn = monitor(2, "Built-in Retina", role: "main")

        #expect(logsAfterDisplaysChange([dell, builtIn]) == ["desk 2"])
        #expect(logsAfterDisplaysChange([dell, builtIn]) == ["desk 2"])
        #expect(logsAfterDisplaysChange([monitor(1, "Built-in Retina", role: "main")]) == ["desk 2", "laptop"])
        #expect(logsAfterDisplaysChange([dell, builtIn]) == ["desk 2", "laptop", "desk 2"])
    }

    @Test func aProfileNeedsADifferentMonitorForEachSelector() throws {
        _ = try host.load(configURL: dir.write("init.lua", """
        wm.profile("twice", { monitors = { "main", "main" }, apply = function() wm.log("twice") end })
        wm.profile("pair", { monitors = { "e", "main" }, apply = function() wm.log("pair") end })
        wm.profile("third", { monitors = { 3, "ez" }, apply = function() wm.log("third") end })
        """))
        let eizo = monitor(1, "Eizo", role: "main")
        let ex = monitor(2, "Ex", role: "secondary")

        // "e" fits both monitors, and "main" only the first: the profile fits when "e" takes the second one.
        #expect(logsAfterDisplaysChange([eizo, ex]) == ["pair"])
        // Two selectors and three monitors: no profile fits.
        #expect(logsAfterDisplaysChange([eizo, ex, monitor(3, "Z", role: "tertiary")]) == ["pair"])
    }

    @Test func aProfileRunsWhenTheConfigLoadsToo() throws {
        bridge.queryResults["monitors"] = .array([monitor(1, "Built-in Retina", role: "main")])
        _ = try host.load(configURL: dir.write("init.lua", """
        wm.profile("laptop", { monitors = { "main" }, apply = function() wm.log("laptop") end })
        """))

        host.fire(event: "config_reloaded", payload: [:])
        host.flush()

        #expect(bridge.logs == ["laptop"])
    }

    @Test func profilesCannotBeAddedAfterTheConfigLoaded() throws {
        _ = try host.load(configURL: dir.write("init.lua", """
        wm.on("tick", function()
          local ok, err = pcall(wm.profile, "late", { monitors = { "main" }, apply = function() end })
          wm.log(tostring(ok), err)
        end)
        """))

        host.fire(event: "tick", payload: [:])
        host.flush()

        #expect(bridge.logs.count == 1)
        #expect(bridge.logs.first?.hasPrefix("false") == true)
        #expect(bridge.logs.first?.contains("wm.profile can only be called while the config file loads") == true)
    }

    @Test func ruleMatchingChecksEveryField() {
        let rule = WindowRule(app: "Notes", title: "^Draft", role: "AXWindow", subrole: "axdialog", identifier: "^settings-")
        func matches(
            app: String = "Notes", title: String = "Draft 1", role: String = "AXWindow",
            subrole: String = "AXDialog", identifier: String = "settings-general"
        ) -> Bool {
            rule.matches(bundleID: "com.apple.Notes", appName: app, title: title, role: role, subrole: subrole, identifier: identifier)
        }

        #expect(matches())
        #expect(!matches(app: "Mail"))
        #expect(!matches(title: "My Draft"))
        #expect(!matches(role: "AXSheet"))
        #expect(!matches(subrole: "AXStandardWindow"))
        #expect(!matches(identifier: "document-1"))
        #expect(!matches(identifier: ""))
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

    @Test(arguments: [
        """
        wm.bind("alt-a", "focus left")
        wm.bind("alt-a", "focus right", { repeating = true })
        """,
        """
        wm.bind("alt-a", "focus right", { repeating = true })
        wm.bind("alt-a", "focus left")
        """,
    ])
    func aPlainBindAndARepeatingBindShareAChordInAnyOrder(script: String) throws {
        let config = try host.load(configURL: dir.write("init.lua", script))
        let a = try parseChord("alt-a")
        #expect(config.binds["main"]?[a] == .command("focus left"))
        #expect(config.holdBinds["main"]?[a] == .command("focus right"))
        #expect(Set(config.bindRecords.map(\.trigger)) == [.press, .hold])
    }

    @Test func aRepeatingBindAloneRunsOnPressAndOnRepeats() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.bind("alt-a", "focus right", { repeating = true })
        wm.bind("alt-b>c", "focus up", { repeating = true })
        """))
        let a = try parseChord("alt-a")
        #expect(config.binds["main"]?[a] == .command("focus right"))
        #expect(config.holdBinds["main"]?[a] == .command("focus right"))
        #expect(config.bindRecords.first?.trigger == .hold)
        // On a sequence the option has no effect, as before.
        #expect(config.holdBinds["main"]?[try parseChord("alt-b")] == nil)
        #expect(config.sequences["main"]?[[try parseChord("alt-b"), try parseChord("c")]] == .command("focus up"))
    }

    @Test func theHyprlandNameOfUniversalWorks() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.bind("alt-a", "focus left", { submap_universal = true })
        """))
        #expect(config.binds[universalMode]?[try parseChord("alt-a")] == .command("focus left"))
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
        ("wm.mode('back', {})", "'back' is reserved"),
        ("wm.mode('a', {}, { sticky = true })", "unknown key 'sticky'"),
        ("wm.mode('a', {}, { once = 'yes' })", "'once' must be true or false"),
        ("wm.bind('alt-a', 'x', { long_press = 9 })", "'long_press' for 'alt-a' must be between 0.1 and 3 seconds"),
        ("wm.bind('alt-a', 'x', { long_press = 'long' })", "'long_press' for 'alt-a' must be true, false or a number of seconds"),
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

    @Test func aTitleBarGestureTakesAZoneAndNoModifier() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.gesture { zone = "title_bar", direction = "pinch-in", command = "window minimize" }
        wm.gesture { zone = "title_bar", direction = "up", command = "window maximize" }
        wm.config { trackpad = { title_bar = true, title_bar_height = 60, pinch = false } }
        """))
        #expect(config.gestures == [
            Gesture(zone: .titleBar, direction: .pinchIn, action: .command("window minimize")),
            Gesture(zone: .titleBar, direction: .up, action: .command("window maximize")),
        ])
        #expect(config.bindRecords.map(\.keys) == ["title_bar pinch-in", "title_bar-scroll up"])
        #expect(config.settings.trackpad.titleBar)
        #expect(config.settings.trackpad.titleBarHeight == 60)
        #expect(!config.settings.trackpad.pinch)
    }

    @Test(arguments: [
        ("wm.gesture { mods = 'alt', direction = 'pinch-in', command = 'x' }", "needs zone = \"title_bar\""),
        ("wm.gesture { zone = 'title_bar', mods = 'alt', direction = 'left', command = 'x' }", "takes no 'mods' and no 'fingers'"),
        ("wm.gesture { zone = 'title_bar', fingers = 3, direction = 'left', command = 'x' }", "takes no 'mods' and no 'fingers'"),
        ("wm.gesture { zone = 'corner', direction = 'left', command = 'x' }", "'zone' must be one of"),
        ("wm.config { trackpad = { title_bar_height = 5 } }", "'trackpad.title_bar_height' must be between 10 and 200"),
    ])
    func badTitleBarGesturesNameTheProblem(script: String, expected: String) throws {
        let error = #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.write("init.lua", script))
        }
        #expect(error?.message.contains(expected) == true)
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
        ("wm.gesture { mods = 'alt', direction = 'left', command = 'x', touches = 3 }", "unknown key 'touches'"),
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

    @Test func theCapsLockCanBeTheHyperKey() throws {
        let off = try host.load(configURL: dir.write("init.lua", "wm.config { binds = { long_press_timeout = 0.5 } }"))
        #expect(off.settings.binds.capsLockHyper == false)
        let on = try host.load(configURL: dir.write("init.lua", "wm.config { binds = { capslock = 'hyper' } }"))
        #expect(on.settings.binds.capsLockHyper == true)
        let error = #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.write("init.lua", "wm.config { binds = { capslock = 'escape' } }"))
        }
        #expect(error?.message.contains("'binds.capslock' must be one of \"hyper\"") == true)
    }

    @Test func aRemapIsABindThatTypesAnotherKey() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.remap("hyper-k", "up", { description = "Up" })
        wm.remap("hyper-4", "cmd-right")
        wm.remap("hyper-s", "play")
        wm.mode("vim", { h = { remap = "left", description = "Left" }, w = { remap = "alt-right" }, esc = "mode main" })
        """))
        #expect(config.binds["main"]?[try parseChord("hyper-k")] == .remap(Chord(modifiers: [], key: "up")))
        #expect(config.binds["main"]?[try parseChord("hyper-4")] == .remap(Chord(modifiers: [.command], key: "right")))
        #expect(config.binds["main"]?[try parseChord("hyper-s")] == .remap(Chord(modifiers: [], key: "play")))
        #expect(config.binds["vim"]?[try parseChord("h")] == .remap(Chord(modifiers: [], key: "left")))
        #expect(config.binds["vim"]?[try parseChord("w")] == .remap(Chord(modifiers: [.option], key: "right")))
        #expect(config.bindRecords.contains { $0.keys == "hyper-k" && $0.action == "remap up" && $0.options.description == "Up" })
    }

    @Test(arguments: [
        ("wm.remap('hyper-k', 'nokey')", "unknown key 'nokey'"),
        ("wm.remap('hyper-k', 'hyper-up')", "'hyper' is not a key that wm can type"),
        ("wm.remap('hyper-k>j', 'up')", "is a remap; it needs a single chord"),
        ("wm.remap('hyper-k', 'up', { release = true })", "is a remap; it needs a single chord"),
        ("wm.remap('hyper-k', 'up', { repeating = true })", "is a remap; it needs a single chord"),
        ("wm.remap('hyper-k', 5)", "wm.remap expects the key to type"),
    ])
    func aWrongRemapIsAConfigError(script: String, expected: String) throws {
        let error = #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.write("init.lua", script))
        }
        #expect(error?.message.contains(expected) == true)
    }

    @Test func theMasterTableSetsTheLayoutOptions() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.config { layout = "master", master = { ratio = 0.6, count = 2, orientation = "center", new_window = "master" } }
        """))
        #expect(config.settings.layout == .master)
        #expect(config.settings.master.ratio == 0.6)
        #expect(config.settings.master.count == 2)
        #expect(config.settings.master.orientation == .center)
        #expect(config.settings.master.newWindow == .master)
        let defaults = try host.load(configURL: dir.write("init.lua", "wm.config { layout = 'tiling' }"))
        #expect(defaults.settings.master == MasterSettings())
    }

    @Test(arguments: [
        ("wm.config { master = { ratio = 0.95 } }", "'master.ratio' must be between 0.1 and 0.9"),
        ("wm.config { master = { count = 0 } }", "'master.count' must be a whole number, at least 1"),
        ("wm.config { master = { orientation = 'diagonal' } }", "'master.orientation' must be one of"),
        ("wm.config { master = { new_window = 'bottom' } }", "'master.new_window' must be one of"),
        ("wm.config { master = { size = 1 } }", "unknown key 'master.size'"),
    ])
    func masterOptionErrorsNameTheKey(script: String, expected: String) {
        let error = #expect(throws: ConfigError.self) { try host.load(configURL: dir.write("init.lua", script)) }
        #expect(error?.message.contains(expected) == true)
    }

    @Test func aWorkspaceCanUseTheMasterLayoutWithItsOwnOptions() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.workspace("code", { layout = "master", layout_options = { master_ratio = 0.7, master_orientation = "right" } })
        """))
        #expect(config.workspaceLayouts["code"] == .master)
        var settings = Settings()
        try applyWorkspaceOverrides(try #require(config.workspaceRules["code"]?.overrides), to: &settings)
        #expect(settings.master.ratio == 0.7)
        #expect(settings.master.orientation == .right)
    }

    @Test func zenSettingsSetTheWidthAndCheckIt() throws {
        let config = try host.load(configURL: dir.write("init.lua", "wm.config { zen = { width = 0.6 } }"))
        #expect(config.settings.zen.width == 0.6)
        #expect(try host.load(configURL: dir.write("init.lua", "wm.config { layout = 'tiling' }")).settings.zen.width == 0.7)
        let low = #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.write("init.lua", "wm.config { zen = { width = 0.1 } }"))
        }
        #expect(low?.message.contains("'zen.width' must be between 0.3 and 1") == true)
    }

    @Test func bindSettingsCanTurnOffTheSystemCmdTab() throws {
        let off = try host.load(configURL: dir.write("init.lua", "wm.config { binds = { long_press_timeout = 0.5 } }"))
        #expect(off.settings.binds.disableSystemCmdTab == false)
        let on = try host.load(configURL: dir.write("init.lua", "wm.config { binds = { disable_system_cmd_tab = true } }"))
        #expect(on.settings.binds.disableSystemCmdTab == true)
        let error = #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.write("init.lua", "wm.config { binds = { disable_system_cmd_tab = 'yes' } }"))
        }
        #expect(error?.message.contains("'binds.disable_system_cmd_tab' must be true or false") == true)
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

    @Test func theMenuBarListsTheOccupiedWorkspacesUntilTheConfigSaysOtherwise() throws {
        let defaults = try host.load(configURL: dir.write("init.lua", "wm.config { layout = \"tiling\" }"))
        #expect(defaults.settings.menuBar == MenuBarSettings())
        #expect(defaults.settings.menuBar.workspaces == .occupied)

        let custom = try host.load(configURL: dir.write("init.lua", """
        wm.config { menubar = { workspaces = "current", current = "[{name}]", other = "{mode}{name}", separator = "," } }
        """))
        #expect(custom.settings.menuBar.workspaces == .current)
        #expect(custom.settings.menuBar.current == "[{name}]")
        #expect(custom.settings.menuBar.other == "{mode}{name}")
        #expect(custom.settings.menuBar.separator == ",")
    }

    @Test func aMenuBarTemplateWithAnUnknownPlaceholderIsAnError() throws {
        let error = #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.write("init.lua", "wm.config { menubar = { current = \"{mode}:{nme}\" } }"))
        }
        #expect(error?.message.contains("{nme}") == true)
    }

    @Test func aMenuBarSettingWithAWrongValueIsAnError() throws {
        #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.write("init.lua", "wm.config { menubar = { workspaces = \"all\" } }"))
        }
        #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.write("init.lua", "wm.config { menubar = { color = \"red\" } }"))
        }
    }

    @Test func workspaceBackAndForthIsOffUntilTheConfigSetsIt() throws {
        let off = try host.load(configURL: dir.write("init.lua", "wm.config { layout = \"tiling\" }"))
        #expect(off.settings.workspaceBackAndForth == false)

        let on = try host.load(configURL: dir.write("init.lua", "wm.config { workspace_back_and_forth = true }"))
        #expect(on.settings.workspaceBackAndForth == true)
    }

    @Test func scrollingFillOptionsLoadFromTheConfigAndFromAWorkspaceRule() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.config { scrolling = { single_window_fit = "fill", visible_columns = 3, orientation = "auto" } }
        wm.workspace("code", { layout = "scrolling", layout_options = { single_window_fit = "keep", visible_columns = 2 } })
        """))
        #expect(config.settings.scrolling.singleWindowFit == .fill)
        #expect(config.settings.scrolling.visibleColumns == 3)
        #expect(config.settings.scrolling.orientation == .auto)

        var other = Settings()
        try applyWorkspaceOverrides(try #require(config.workspaceRules["code"]?.overrides), to: &other)
        #expect(other.scrolling.singleWindowFit == .keep)
        #expect(other.scrolling.visibleColumns == 2)
    }

    @Test func focusFollowsMouseTakesATrueOrATable() throws {
        let flag = try host.load(configURL: dir.write("init.lua", "wm.config { focus_follows_mouse = true }"))
        #expect(flag.settings.focusFollowsMouse == FocusFollowsMouse(enabled: true, onlyFullyVisible: false))

        let table = try host.load(configURL: dir.write("init.lua", "wm.config { focus_follows_mouse = { enabled = true, only_fully_visible = true } }"))
        #expect(table.settings.focusFollowsMouse == FocusFollowsMouse(enabled: true, onlyFullyVisible: true))
    }

    @Test func theMouseModifiersAreOffUntilTheConfigSetsThem() throws {
        let off = try host.load(configURL: dir.write("init.lua", "wm.config { layout = \"tiling\" }"))
        #expect(off.settings.mouse == MouseSettings())

        let on = try host.load(configURL: dir.write("init.lua", "wm.config { mouse = { move_modifier = \"alt\", resize_modifier = \"alt+shift\" } }"))
        #expect(on.settings.mouse == MouseSettings(moveModifier: "alt", resizeModifier: "alt+shift"))
    }

    @Test func aGestureCanNameTheNumberOfFingersInsteadOfAModifier() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.gesture { fingers = 3, direction = "left", command = "workspace prev" }
        wm.gesture { mods = "alt", fingers = 4, direction = "up", command = "overview", threshold = 200 }
        """))
        #expect(config.gestures.count == 2)
        #expect(config.gestures[0].fingers == 3)
        #expect(config.gestures[0].modifiers == [])
        #expect(config.gestures[1].fingers == 4)
        #expect(config.gestures[1].modifiers == .option)
    }

    @Test func theTrackpadIsOnWithFourFingersUntilTheConfigSaysOtherwise() throws {
        let plain = try host.load(configURL: dir.write("init.lua", "wm.config { layout = \"tiling\" }"))
        #expect(plain.settings.trackpad == TrackpadSettings(enabled: true, fingers: 4, scrollFingers: 4, speed: 1, warnsWhenMissing: false))
        let off = try host.load(configURL: dir.write("init.lua", "wm.config { trackpad = { enabled = false } }"))
        #expect(off.settings.trackpad.enabled == false)
        let on = try host.load(configURL: dir.write("init.lua", "wm.config { trackpad = { enabled = true, scroll_fingers = 3, speed = 2 } }"))
        #expect(on.settings.trackpad == TrackpadSettings(enabled: true, fingers: 4, scrollFingers: 3, speed: 2, warnsWhenMissing: true))
    }

    @Test func specialWorkspacesAreNinetyPercentOfTheScreenWithNoBackdropByDefault() throws {
        let plain = try host.load(configURL: dir.write("init.lua", "wm.config { layout = \"tiling\" }"))
        #expect(plain.settings.special == SpecialSettings())
        #expect(plain.settings.special.size == 0.9)
        #expect(plain.settings.special.backdrop == .clear)
        #expect(plain.settings.special.hideOnOtherMonitor == false)
        let set = try host.load(configURL: dir.write("init.lua", "wm.config { special = { size = 0.7, backdrop = \"#00000066\", hide_on_other_monitor = true } }"))
        #expect(set.settings.special.size == 0.7)
        #expect(set.settings.special.backdrop == Color(red: 0, green: 0, blue: 0, alpha: 0.4))
        #expect(set.settings.special.hideOnOtherMonitor == true)
    }

    @Test func aModeCanEndAfterOneActionAndSwallowTheKeysItDoesNotBind() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.mode("once", { h = "focus left" }, { once = true })
        wm.mode("vim", { h = "focus left" }, { swallow = true })
        wm.mode("plain", { h = "focus left" })
        """))
        #expect(config.modeOptions == ["once": ModeOptions(once: true), "vim": ModeOptions(swallow: true)])
    }

    @Test func aModeThatIsDefinedAgainLosesItsOldOptions() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.mode("vim", { h = "focus left" }, { swallow = true })
        wm.mode("vim", { h = "focus left" })
        """))
        #expect(config.modeOptions == [:])
    }

    @Test func aLongPressCanNameItsOwnSeconds() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.bind("alt-a", "focus right", { long_press = 0.8 })
        wm.bind("alt-b", "focus left", { long_press = true })
        """))
        let chordA = try parseChord("alt-a"), chordB = try parseChord("alt-b")
        #expect(config.longPressBinds["main"]?[chordA] == .command("focus right"))
        #expect(config.longPressTimeouts["main"] == [chordA: 0.8])
        #expect(config.longPressBinds["main"]?[chordB] == .command("focus left"))
    }

    @Test func smartGapsAreOffUntilTheConfigSetsThemAndWorkForAWorkspaceToo() throws {
        let off = try host.load(configURL: dir.write("init.lua", "wm.config { gaps = { inner = 4 } }"))
        #expect(off.settings.gaps.smart == false)
        let on = try host.load(configURL: dir.write("init.lua", "wm.config { gaps = { inner = 4, smart = true } }"))
        #expect(on.settings.gaps.smart == true)
        let rule = try host.load(configURL: dir.write("init.lua", "wm.workspace('3', { gaps = { smart = true } })"))
        #expect(rule.workspaceRules["3"] != nil)
    }

    @Test func theOverviewHasAZoomAGapAndABackdrop() throws {
        let plain = try host.load(configURL: dir.write("init.lua", "wm.config { layout = \"tiling\" }"))
        #expect(plain.settings.overview == OverviewSettings())
        #expect(plain.settings.overview.zoom == 0.5)
        #expect(plain.settings.overview.gap == 48)
        let set = try host.load(configURL: dir.write("init.lua", "wm.config { overview = { zoom = 0.4, gap = 20, backdrop = \"#00000080\" } }"))
        #expect(set.settings.overview.zoom == 0.4)
        #expect(set.settings.overview.gap == 20)
        #expect(set.settings.overview.backdrop == Color(red: 0, green: 0, blue: 0, alpha: 128.0 / 255))
    }

    @Test func theLabelsOfTheHintsHaveColorsThatTheConfigChanges() throws {
        let plain = try host.load(configURL: dir.write("init.lua", "wm.config { layout = \"tiling\" }"))
        #expect(plain.settings.hints == HintSettings())
        let set = try host.load(configURL: dir.write("init.lua", "wm.config { hints = { background = \"#ff0000\", text = \"#ffffff\", area = \"#00ff0080\" } }"))
        #expect(set.settings.hints.background == Color(red: 1, green: 0, blue: 0))
        #expect(set.settings.hints.text == Color(red: 1, green: 1, blue: 1))
        #expect(set.settings.hints.area == Color(red: 0, green: 1, blue: 0, alpha: 128.0 / 255))
        #expect(set.settings.hints.focus == HintSettings().focus)
    }

    @Test func theSelectKeysHaveDefaultsThatTheConfigReplacesOneActionAtATime() throws {
        let plain = try host.load(configURL: dir.write("init.lua", "wm.config { layout = 'tiling' }"))
        #expect(plain.settings.select.keys[.copy] == ["y", "cmd-c", "enter"])
        let set = try host.load(configURL: dir.write(
            "init.lua", "wm.config { select = { keys = { copy = 'ctrl-shift-c', extend = { 'v', 'x' }, search = {} } } }"))
        #expect(set.settings.select.keys[.copy] == ["ctrl-shift-c"])
        #expect(set.settings.select.keys[.extend] == ["v", "x"])
        #expect(set.settings.select.keys[.search] == [])
        #expect(set.settings.select.keys[.rightClick] == ["shift-enter"])
    }

    @Test(arguments: [
        ("wm.config { select = { keys = { copy = 'c', extend = 'c' } } }", "'c' is bound to both"),
        ("wm.config { select = { keys = { copy = 'hyper-c' } } }", "uses hyper"),
        ("wm.config { select = { keys = { copy = 'nope' } } }", "unknown key 'nope'"),
        ("wm.config { select = { keys = { copy = 3 } } }", "'select.keys.copy' must be a chord or a list of chords"),
        ("wm.config { select = { keys = { paste = 'p' } } }", "unknown key 'select.keys.paste'"),
    ])
    func selectKeyErrorsNameTheKey(script: String, expected: String) {
        let error = #expect(throws: ConfigError.self) { try host.load(configURL: dir.write("init.lua", script)) }
        #expect(error?.message.contains(expected) == true)
    }

    @Test func aHintColorThatIsNotAColorIsAnError() throws {
        #expect(throws: (any Error).self) {
            try host.load(configURL: dir.write("init.lua", "wm.config { hints = { background = \"red\" } }"))
        }
    }

    @Test func everyKeyboardIsEnabledUnlessTheConfigNamesOne() throws {
        let plain = try host.load(configURL: dir.write("init.lua", "wm.config { layout = \"tiling\" }"))
        #expect(plain.settings.keyboards == KeyboardSettings())
        let set = try host.load(configURL: dir.write("init.lua", """
        wm.config { keyboards = { default = false, ["Apple Internal Keyboard / Trackpad"] = true, ["046D:C52B"] = false } }
        """))
        #expect(set.settings.keyboards == KeyboardSettings(
            defaultEnabled: false, overrides: ["apple internal keyboard / trackpad": true, "046d:c52b": false]))
    }

    private static let defaultFloatingNames = [
        "helium-popups", "chrome-popups", "brave-popups", "chromium-popups", "edge-popups", "firefox-popups", "finder", "preview", "calculator", "activity-monitor", "archive-utility",
        "quicktime-player", "system-settings", "raycast-settings",
    ]

    @Test func theDefaultFloatingRulesAreAddedWithoutAnyConfig() throws {
        let config = try host.load(configURL: dir.write("init.lua", "wm.config { layout = \"tiling\" }"))
        #expect(config.rules.map(\.name) == Self.defaultFloatingNames)
        #expect(config.rules.allSatisfy { $0.float == true && $0.center && $0.stop })
        #expect(config.rules.first { $0.name == "finder" }?.app == "com.apple.finder")
        #expect(config.rules.first { $0.name == "helium-popups" }?.title == "^(?!.* - Helium).+")
    }

    @Test func aRuleOfTheUserComesBeforeTheDefaultOnes() throws {
        let config = try host.load(configURL: dir.write("init.lua", "wm.rule { app = 'com.apple.finder', float = false }"))
        #expect(config.rules.first?.name == nil)
        #expect(config.rules.first?.float == false)
        #expect(config.rules.dropFirst().map(\.name) == Self.defaultFloatingNames)
    }

    @Test func aDefaultRuleIsTurnedOffByItsName() throws {
        let config = try host.load(configURL: dir.write("init.lua", "wm.floating.disable('finder', 'preview')"))
        #expect(config.rules.map(\.name) == Self.defaultFloatingNames.filter { $0 != "finder" && $0 != "preview" })
    }

    @Test func theNamesCanBeGivenAsAList() throws {
        let config = try host.load(configURL: dir.write("init.lua", "wm.floating.disable { 'calculator', 'brave-popups' }"))
        #expect(config.rules.map(\.name) == Self.defaultFloatingNames.filter { $0 != "calculator" && $0 != "brave-popups" })
    }

    @Test func allTheDefaultRulesCanBeTurnedOff() throws {
        let config = try host.load(configURL: dir.write("init.lua", "wm.floating.enabled = false"))
        #expect(config.rules.isEmpty)
    }

    @Test func aNameThatIsNotADefaultRuleIsAnError() {
        #expect(throws: (any Error).self) {
            _ = try host.load(configURL: dir.write("init.lua", "wm.floating.disable('finderr')"))
        }
        do {
            _ = try host.load(configURL: dir.write("init.lua", "wm.floating.disable('finderr')"))
        } catch {
            #expect("\(error)".contains("there is no default rule named 'finderr'"))
        }
    }

    @Test func theListOfDefaultRulesCanBeChangedByTheConfig() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        table.insert(wm.floating.defaultRules, { name = "notes", app = "com.apple.Notes", float = true, center = true })
        for _, rule in ipairs(wm.floating.defaultRules) do
          if rule.name == "finder" then rule.size = { 0.5, 0.6 } end
        end
        table.remove(wm.floating.defaultRules, 1)
        """))
        #expect(config.rules.map(\.name) == Array(Self.defaultFloatingNames.dropFirst()) + ["notes"])
        #expect(config.rules.first { $0.name == "finder" }?.size == RuleSize(width: 0.5, height: 0.6))
    }

    @Test func aRuleCanHaveANameAndTheNameMustBeAString() throws {
        let config = try host.load(configURL: dir.write("init.lua", "wm.floating.enabled = false; wm.rule { name = 'mine', app = 'x' }"))
        #expect(config.rules.map(\.name) == ["mine"])
        #expect(throws: (any Error).self) {
            _ = try host.load(configURL: dir.write("init.lua", "wm.rule { name = 3, app = 'x' }"))
        }
    }

    @Test func floatingWindowsRememberTheirPositionUnlessTheConfigSaysNo() throws {
        let plain = try host.load(configURL: dir.write("init.lua", "wm.config { layout = \"tiling\" }"))
        #expect(plain.settings.floating.rememberPosition)
        let off = try host.load(configURL: dir.write("init.lua", "wm.config { floating = { remember_position = false } }"))
        #expect(off.settings.floating.rememberPosition == false)
    }

    @Test func theFingersOfTheTrackpadAlsoSetTheScrollingFingers() throws {
        let three = try host.load(configURL: dir.write("init.lua", "wm.config { trackpad = { fingers = 3 } }"))
        #expect(three.settings.trackpad.fingers == 3)
        #expect(three.settings.trackpad.scrollFingers == 3)
        let mixed = try host.load(configURL: dir.write("init.lua", "wm.config { trackpad = { fingers = 3, scroll_fingers = 0 } }"))
        #expect(mixed.settings.trackpad.fingers == 3)
        #expect(mixed.settings.trackpad.scrollFingers == 0)
    }

    @Test func splitUnderPointerIsOffUntilTheConfigSetsIt() throws {
        let off = try host.load(configURL: dir.write("init.lua", "wm.config { tiling = { smart_split = true } }"))
        #expect(off.settings.tiling.splitUnderPointer == false)
        let on = try host.load(configURL: dir.write("init.lua", "wm.config { tiling = { split_under_pointer = true } }"))
        #expect(on.settings.tiling.splitUnderPointer == true)
        #expect(on.settings.tiling.smartSplit == false)
    }

    @Test func smartSplitIsOffUntilTheConfigSetsIt() throws {
        let off = try host.load(configURL: dir.write("init.lua", "wm.config { tiling = { split_ratio = 0.6 } }"))
        #expect(off.settings.tiling.smartSplit == false)
        let on = try host.load(configURL: dir.write("init.lua", "wm.config { tiling = { smart_split = true } }"))
        #expect(on.settings.tiling.smartSplit == true)
    }

    @Test func aWorkspaceAndARuleCanNameAMonitorByRole() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.workspace("web", { monitor = "main", default = true })
        wm.workspace("chat", { monitor = "secondary" })
        wm.rule { app = "com.apple.Notes", monitor = "tertiary" }
        """))

        #expect(config.workspaceRules["web"]?.monitor == "main")
        #expect(config.workspaceRules["chat"]?.monitor == "secondary")
        #expect(config.rules.first?.monitor == "tertiary")
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
        ("wm.config { layoutz = {} }", "unknown key 'layoutz'"),
        ("wm.config { tree = {} }", "unknown key 'tree'"),
        ("wm.config { tiling = { split_ratio = 2 } }", "'tiling.split_ratio' must be between 0.1 and 0.9"),
        ("wm.config { animations = { enabled = 'yes' } }", "'animations.enabled' must be true or false"),
        ("wm.config { scrolling = { vertical = { side = 'up' } } }", "'scrolling.vertical.side' must be one of"),
        ("wm.config { scrolling = { vertical = { width = 0.95 } } }", "'scrolling.vertical.width' must be between 0.1 and 0.9"),
        ("wm.config { scrolling = { vertical = { foo = 1 } } }", "unknown key 'scrolling.vertical.foo'"),
        ("wm.config { scrolling = { default_column_display = 'accordion' } }", "'scrolling.default_column_display' must be one of"),
        ("wm.config { trackpad = { scroll_fingers = 2 } }", "'trackpad.scroll_fingers' must be 3, 4 or 0"),
        ("wm.config { trackpad = { fingers = 5 } }", "'trackpad.fingers' must be 3 or 4"),
        ("wm.config { gaps = { smart = 1 } }", "'gaps.smart' must be true or false"),
        ("wm.config { overview = { zoom = 0.9 } }", "'overview.zoom'"),
        ("wm.config { overview = { gap = -1 } }", "'overview.gap'"),
        ("wm.config { overview = { backdrop = \"dark\" } }", "'overview.backdrop' must be a color"),
        ("wm.config { keyboards = { default = 'yes' } }", "'keyboards.default' must be true or false"),
        ("wm.config { keyboards = true }", "'keyboards' must be a table"),
        ("wm.config { floating = { remember_position = 'yes' } }", "'floating.remember_position' must be true or false"),
        ("wm.config { special = { size = 0.2 } }", "'special.size'"),
        ("wm.config { special = { backdrop = \"red\" } }", "'special.backdrop' must be a color"),
        ("wm.gesture { fingers = 5, direction = 'left', command = 'x' }", "'fingers' must be 3 or 4"),
        ("wm.gesture { direction = 'left', command = 'x' }", "needs 'mods'"),
        ("wm.config { mouse = { move_modifier = 'hyper' } }", "'mouse.move_modifier' unknown modifier 'hyper'"),
        ("wm.config { mouse = { drag = 'alt' } }", "unknown key 'mouse.drag'"),
        ("wm.config { focus_follows_mouse = { only = true } }", "unknown key 'focus_follows_mouse.only'"),
        ("wm.config { scrolling = { orientation = 'diagonal' } }", "'scrolling.orientation' must be one of"),
        ("wm.config { scrolling = { single_window_fit = 'stretch' } }", "'scrolling.single_window_fit' must be one of"),
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
        ("wm.profile('', {})", "wm.profile expects a profile name"),
        ("wm.profile('a', { monitors = {}, apply = function() end })", "'monitors' must be a list of selectors"),
        ("wm.profile('a', { monitors = { {} }, apply = function() end })", "a monitor selector is a role, a number or part of a name"),
        ("wm.profile('a', { monitors = { 'main' } })", "'apply' must be a function"),
        ("local p = { monitors = { 'main' }, apply = function() end }; wm.profile('a', p); wm.profile('a', p)", "wm.profile 'a' is already defined"),
        ("wm.rule { identifier = '[' }", "'identifier' is not a valid regular expression"),
        ("wm.rule { subrole = 5 }", "'subrole'"),
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

    // MARK: Tile templates

    @Test func theCenteredTemplateAndACustomAreaCanBeListed() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.config { tiling = { templates = {
          wm.templates.two,
          wm.templates.centered,
          { name = "wide", key = "y", cells = { { 0, 0, 1, 1 } }, area = { 0.1, 0, 0.8, 1 } },
        } } }
        """))
        #expect(config.settings.tiling.templates.map(\.name) == ["2", "center", "wide"])
        #expect(config.settings.tiling.templates[1] == .centered)
        #expect(config.settings.tiling.templates[2].area == CGRect(x: 0.1, y: 0, width: 0.8, height: 1))
    }

    @Test func aBadTemplateAreaNamesItsPath() {
        let error = #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.write("init.lua", "wm.config { tiling = { templates = { { name = 'x', cells = { {0,0,1,1} }, area = { 0, 0, 1 } } } } }"))
        }
        #expect(error?.message.contains("'tiling.templates[1].area' must be { x, y, width, height }, four numbers") == true)
        let outside = #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.write("init.lua", "wm.config { tiling = { templates = { { name = 'x', cells = { {0,0,1,1} }, area = { 0.5, 0, 0.8, 1 } } } } }"))
        }
        #expect(outside?.message.contains("'tiling.templates[1].area' is not valid: the area needs a positive size") == true)
    }

    @Test func templatesStayBuiltInWhenTheConfigHasNone() throws {
        let config = try host.load(configURL: dir.write("init.lua", "wm.config { layout = 'scrolling' }"))

        #expect(config.settings.tiling.templates == SplitTemplate.tilingCases)
        #expect(config.settings.scrolling.templates == SplitTemplate.allCases)
    }

    @Test func templatesAreListedPerLayoutAndMixBuiltInWithCustomOnes() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.config {
          tiling = { templates = { wm.templates.two, wm.templates.stack_left } },
          scrolling = { templates = {
            wm.templates.two_thirds,
            { name = "70/30", key = "s", title = "Focus 70%", cells = { { 0, 0, 0.7, 1 }, { 0.7, 0, 0.3, 1 } } },
            { name = "halves", cells = { { 0, 0, 1, 0.5 }, { 0, 0.5, 1, 0.5 } } },
          } },
        }
        """))

        #expect(config.settings.tiling.templates == [.two, .stackLeft])
        #expect(config.settings.scrolling.templates == [
            .twoThirds,
            SplitTemplate(
                name: "70/30", key: "s", title: "Focus 70%",
                cells: [CGRect(x: 0, y: 0, width: 0.7, height: 1), CGRect(x: 0.7, y: 0, width: 0.3, height: 1)]),
            SplitTemplate(
                name: "halves", key: nil, title: "halves",
                cells: [CGRect(x: 0, y: 0, width: 1, height: 0.5), CGRect(x: 0, y: 0.5, width: 1, height: 0.5)]),
        ])
    }

    @Test func everyBuiltInTemplateIsExportedToLua() throws {
        _ = try host.load(configURL: dir.write("init.lua", """
        local ids = { "two", "three", "four", "five", "six", "stack_left", "stack_right", "two_thirds", "three_quarters", "one_quarter", "two_rows", "two_thirds_tall", "three_rows", "one_over_two", "two_over_one", "sidebars", "corner_top_left", "corner_bottom_left" }
        local names = {}
        for _, id in ipairs(ids) do names[#names + 1] = wm.templates[id].name end
        wm.log(table.concat(names, ","))
        """))

        #expect(bridge.logs == ["2,3,4,5,6,2+1,1+2,2/3,3/4,1/4,2v,2/3v,3v,1-over-2,2-over-1,1/2/1,corner-tl,corner-bl"])
    }

    @Test(arguments: [
        ("wm.config { scrolling = { templates = {} } }", "'scrolling.templates' must not be empty"),
        ("wm.config { tiling = { templates = { { name = 'chain', cells = { {0,0,.5,1}, {.5,0,.5,1} } } } } }", "'tiling.templates[1].name' must have no spaces and must not be \"chain\""),
        ("wm.config { tiling = { templates = { { name = 'a', key = 'c', cells = { {0,0,.5,1}, {.5,0,.5,1} } } } } }", "'tiling.templates[1].key' must be one of a-z or 0-9, and not \"c\""),
        ("wm.config { tiling = { templates = { wm.templates.two, wm.templates.two } } }", "'tiling.templates[2].name' \"2\" is already in this list"),
        ("wm.config { tiling = { templates = { wm.templates.two, { name = 'x', key = '2', cells = { {0,0,.5,1}, {.5,0,.5,1} } } } } }", "'tiling.templates[2].key' \"2\" is already in this list"),
        ("wm.config { scrolling = { templates = { { name = 'x' } } } }", "'scrolling.templates[1].cells' is required"),
        ("wm.config { scrolling = { templates = { { name = 'x', cells = { {0,0,.5}, {.5,0,.5,1} } } } } }", "'scrolling.templates[1].cells[1]' must be { x, y, width, height }"),
        ("wm.config { scrolling = { templates = { { name = 'x', cells = { {0,0,.6,1}, {.5,0,.5,1} } } } } }", "'scrolling.templates[1].cells' is not valid: the cells must fill the screen with straight cuts and no overlap"),
        ("wm.config { scrolling = { templates = { { name = 'x', cells = { {0,0,1,1} } } } } }", "a template needs at least two cells"),
        ("wm.workspace('1', { layout_options = { templates = {} } })", "unknown key 'layout_options.templates'"),
    ])
    func templateErrorsNameTheProblem(script: String, expected: String) throws {
        let error = #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.write("init.lua", script))
        }
        #expect(error?.message.contains(expected) == true)
    }
}

struct ConfigCheckTests {
    let dir: ConfigDir

    init() throws { dir = try ConfigDir() }

    @Test func aGoodConfigIsSummarized() throws {
        let url = try dir.write("init.lua", "wm.bind('alt-h', 'focus left')\nwm.bind('alt-l', 'focus right')")

        #expect(checkConfig(at: url) == .success(ConfigSummary(binds: 2)))
    }

    @Test func aBrokenConfigNamesTheLine() throws {
        let url = try dir.write("init.lua", "wm.bind('alt-h', 'focus left')\nwm.bind('alt-foo', 'x')")

        guard case .failure(let error) = checkConfig(at: url) else {
            Issue.record("the config should not load")
            return
        }
        #expect(error.message.contains("init.lua:2:"))
        #expect(error.message.contains("invalid chord 'alt-foo'"))
    }

    @Test func aMissingFileIsAnError() {
        let url = dir.url.appendingPathComponent("nothing.lua")

        #expect(checkConfig(at: url) == .failure(ConfigError(message: "there is no config file at \(url.path)")))
    }

    @Test func theCheckDoesNotRunWhatTheConfigStarts() throws {
        let marker = dir.url.appendingPathComponent("ran").path
        let url = try dir.write("init.lua", "wm.exec('touch \(marker)')\nwm.dispatch('focus left')")

        #expect(checkConfig(at: url) == .success(ConfigSummary(binds: 0)))
        #expect(!FileManager.default.fileExists(atPath: marker))
    }
}
