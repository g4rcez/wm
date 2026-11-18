import CoreGraphics
import Core
import Foundation

/// Typed access to one Lua table that was converted to `LuaValue`. Every error names the owner and the dotted key.
struct Fields {
    let owner: String
    let path: [String]
    let values: [String: LuaValue]

    init(_ value: LuaValue, owner: String, path: [String] = [], allowed: [String]) throws {
        self.owner = owner
        self.path = path
        guard case .table(let values) = value else {
            let name = path.isEmpty ? "the argument" : "'\(path.joined(separator: "."))'"
            throw ConfigError(message: "\(owner): \(name) must be a table with named keys")
        }
        self.values = values
        if let unknown = values.keys.filter({ !allowed.contains($0) }).sorted().first {
            throw ConfigError(message: "\(owner): unknown key '\(dotted(unknown))'")
        }
    }

    private func dotted(_ key: String) -> String { (path + [key]).joined(separator: ".") }

    private func wrong(_ key: String, _ expected: String) -> ConfigError {
        ConfigError(message: "\(owner): '\(dotted(key))' must be \(expected)")
    }

    func bool(_ key: String) throws -> Bool? {
        guard let value = values[key] else { return nil }
        guard case .bool(let flag) = value else { throw wrong(key, "true or false") }
        return flag
    }

    func number(_ key: String, min: Double? = nil, max: Double? = nil) throws -> Double? {
        guard let value = values[key] else { return nil }
        guard case .number(let number) = value, number.isFinite else { throw wrong(key, "a number") }
        if let min, let max, !(min...max).contains(number) { throw wrong(key, "between \(format(min)) and \(format(max))") }
        if let min, max == nil, number < min { throw wrong(key, "at least \(format(min))") }
        if let max, min == nil, number > max { throw wrong(key, "at most \(format(max))") }
        return number
    }

    func integer(_ key: String, min: Int) throws -> Int? {
        guard let number = try number(key) else { return nil }
        guard number == number.rounded(), number >= Double(min), number < 1e9 else { throw wrong(key, "a whole number, at least \(min)") }
        return Int(number)
    }

    func string(_ key: String) throws -> String? {
        guard let value = values[key] else { return nil }
        guard case .string(let text) = value else { throw wrong(key, "a string") }
        return text
    }

    /// A whole number (at least `min`) or a string, as text: a monitor or a workspace can be named by either.
    func numberOrString(_ key: String, min: Int) throws -> String? {
        if case .number? = values[key] { return String(try integer(key, min: min)!) }
        return try string(key)
    }

    /// A list of numbers in `range` that has at least one item.
    func nonEmptyNumbers(_ key: String, in range: ClosedRange<Double>) throws -> [Double]? {
        guard let list = try numbers(key, in: range) else { return nil }
        guard !list.isEmpty else { throw ConfigError(message: "\(owner): '\(dotted(key))' must not be empty") }
        return list
    }

    /// One of `options`, or a name in `aliases` (which gives the option that it stands for).
    func choice(_ key: String, _ options: [String], aliases: [String: String] = [:]) throws -> String? {
        guard let given = try string(key) else { return nil }
        let text = aliases[given] ?? given
        guard options.contains(text) else {
            throw wrong(key, "one of " + options.map { "\"\($0)\"" }.joined(separator: ", "))
        }
        return text
    }

    func table(_ key: String, allowed: [String]) throws -> Fields? {
        guard let value = values[key] else { return nil }
        return try Fields(value, owner: owner, path: path + [key], allowed: allowed)
    }

    /// A Lua list. An empty Lua table counts as an empty list.
    func list(_ key: String) throws -> [LuaValue]? {
        guard let value = values[key] else { return nil }
        switch value {
        case .array(let items): return items
        case .table(let table) where table.isEmpty: return []
        default: throw wrong(key, "a list")
        }
    }

    func numbers(_ key: String, in range: ClosedRange<Double>) throws -> [Double]? {
        guard let items = try list(key) else { return nil }
        return try items.map { item in
            guard case .number(let number) = item, range.contains(number) else {
                throw wrong(key, "a list of numbers between \(format(range.lowerBound)) and \(format(range.upperBound))")
            }
            return number
        }
    }

    func strings(_ key: String) throws -> [String]? {
        guard let items = try list(key) else { return nil }
        return try items.map { item in
            guard case .string(let text) = item else { throw wrong(key, "a list of strings") }
            return text
        }
    }

    private func format(_ number: Double) -> String {
        number == number.rounded() ? String(Int(number)) : String(number)
    }
}

func parseColor(_ text: String) -> Color? {
    guard text.hasPrefix("#") else { return nil }
    let digits = text.dropFirst()
    guard digits.count == 6 || digits.count == 8, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }),
          let number = UInt32(digits, radix: 16)
    else { return nil }
    let hasAlpha = digits.count == 8
    func channel(_ shift: UInt32) -> Double { Double((number >> shift) & 0xff) / 255 }
    return hasAlpha
        ? Color(red: channel(24), green: channel(16), blue: channel(8), alpha: channel(0))
        : Color(red: channel(16), green: channel(8), blue: channel(0))
}

private func color(_ fields: Fields, _ key: String) throws -> Color? {
    guard let text = try fields.string(key) else { return nil }
    guard let color = parseColor(text) else {
        throw ConfigError(message: "\(fields.owner): '\((fields.path + [key]).joined(separator: "."))' must be a color like \"#rrggbb\" or \"#rrggbbaa\", got \"\(text)\"")
    }
    return color
}

/// The keys of `wm.config`. `types/wm.lua` must describe every one of them (a test checks it).
let topLevelConfigKeys = [
    "layout", "workspaces", "gaps", "animations", "border", "focus_follows_mouse", "mouse_follows_focus",
    "start_at_login", "wrap_focus", "mouse", "trackpad", "workspace_back_and_forth", "tiling", "scrolling", "switcher", "prefix", "url",
    "tab_indicator", "binds", "zen", "special", "overview", "hints", "keyboards", "floating", "master",
    "commands",
]

/// Applies the keys that are present; keys that are absent keep their value, so two `wm.config` calls merge.
func applyConfig(_ value: LuaValue, to settings: inout Settings) throws {
    let owner = "wm.config"
    let top = try Fields(value, owner: owner, allowed: topLevelConfigKeys)

    if let name = try top.choice("layout", LayoutKind.allCases.map(\.rawValue)) { settings.layout = LayoutKind(rawValue: name)! }
    // `workspaces = "native"` (the macOS desktops) was removed. "emulated" is the only mode and stays valid.
    _ = try top.choice("workspaces", ["emulated"])
    switch top.values["focus_follows_mouse"] {
    case nil: break
    case .table?:
        // The table form: `enabled` keeps its value when it is missing.
        let fields = try top.table("focus_follows_mouse", allowed: ["enabled", "only_fully_visible"])!
        if let flag = try fields.bool("enabled") { settings.focusFollowsMouse.enabled = flag }
        if let flag = try fields.bool("only_fully_visible") { settings.focusFollowsMouse.onlyFullyVisible = flag }
    default:
        if let flag = try top.bool("focus_follows_mouse") { settings.focusFollowsMouse.enabled = flag }
    }
    if let flag = try top.bool("mouse_follows_focus") { settings.mouseFollowsFocus = flag }
    if let flag = try top.bool("start_at_login") { settings.startAtLogin = flag }
    if let flag = try top.bool("wrap_focus") { settings.wrapFocus = flag }
    if let trackpad = try top.table("trackpad", allowed: ["enabled", "fingers", "scroll_fingers", "speed"]) {
        if let flag = try trackpad.bool("enabled") {
            settings.trackpad.enabled = flag
            settings.trackpad.warnsWhenMissing = flag
        }
        // `scroll_fingers` follows `fingers` unless the config sets it too.
        if let count = try trackpad.integer("fingers", min: 0) {
            guard [3, 4].contains(count) else { throw ConfigError(message: "wm.config: 'trackpad.fingers' must be 3 or 4") }
            settings.trackpad.fingers = count
            settings.trackpad.scrollFingers = count
        }
        if let count = try trackpad.integer("scroll_fingers", min: 0) {
            guard [0, 3, 4].contains(count) else { throw ConfigError(message: "wm.config: 'trackpad.scroll_fingers' must be 3, 4 or 0 (off)") }
            settings.trackpad.scrollFingers = count
        }
        if let speed = try trackpad.number("speed", min: 0.1, max: 10) { settings.trackpad.speed = speed }
    }
    if let mouse = try top.table("mouse", allowed: ["move_modifier", "resize_modifier"]) {
        for (key, assign) in [("move_modifier", \MouseSettings.moveModifier), ("resize_modifier", \MouseSettings.resizeModifier)] {
            guard let text = try mouse.string(key) else { continue }
            do { _ = try parseModifiers(text) } catch { throw ConfigError(message: "wm.config: 'mouse.\(key)' \(error)") }
            settings.mouse[keyPath: assign] = text
        }
    }
    if let flag = try top.bool("workspace_back_and_forth") { settings.workspaceBackAndForth = flag }

    if let gaps = try top.table("gaps", allowed: ["inner", "outer", "smart"]) {
        if let inner = try gaps.number("inner", min: 0) { settings.gaps.inner = CGFloat(inner) }
        if let smart = try gaps.bool("smart") { settings.gaps.smart = smart }
        switch gaps.values["outer"] {
        case .number?:
            let outer = CGFloat(try gaps.number("outer", min: 0)!)
            settings.gaps.top = outer
            settings.gaps.right = outer
            settings.gaps.bottom = outer
            settings.gaps.left = outer
        case .some:
            let sides = try gaps.table("outer", allowed: ["top", "right", "bottom", "left"])!
            if let top = try sides.number("top", min: 0) { settings.gaps.top = CGFloat(top) }
            if let right = try sides.number("right", min: 0) { settings.gaps.right = CGFloat(right) }
            if let bottom = try sides.number("bottom", min: 0) { settings.gaps.bottom = CGFloat(bottom) }
            if let left = try sides.number("left", min: 0) { settings.gaps.left = CGFloat(left) }
        case nil:
            break
        }
    }

    if let animations = try top.table("animations", allowed: ["enabled", "fps"]) {
        if let flag = try animations.bool("enabled") { settings.animations.enabled = flag }
        if let fps = try animations.number("fps", min: 30, max: 240) { settings.animations.fps = fps }
    }

    if let border = try top.table("border", allowed: ["enabled", "width", "radius", "active", "inactive"]) {
        if let flag = try border.bool("enabled") { settings.border.enabled = flag }
        if let width = try border.number("width", min: 0) { settings.border.width = CGFloat(width) }
        if let radius = try border.number("radius", min: 0) { settings.border.radius = CGFloat(radius) }
        if let active = try color(border, "active") { settings.border.active = active }
        if let inactive = try color(border, "inactive") { settings.border.inactive = inactive }
    }

    if let tabs = try top.table("tab_indicator", allowed: ["enabled", "position", "size", "spacing", "radius", "active", "inactive"]) {
        if let flag = try tabs.bool("enabled") { settings.tabIndicator.enabled = flag }
        if let name = try tabs.choice("position", TabIndicatorPosition.allCases.map(\.rawValue)) {
            settings.tabIndicator.position = TabIndicatorPosition(rawValue: name)!
        }
        if let size = try tabs.number("size", min: 1, max: 40) { settings.tabIndicator.size = CGFloat(size) }
        if let spacing = try tabs.number("spacing", min: 0, max: 40) { settings.tabIndicator.spacing = CGFloat(spacing) }
        if let radius = try tabs.number("radius", min: 0) { settings.tabIndicator.radius = CGFloat(radius) }
        if let active = try color(tabs, "active") { settings.tabIndicator.active = active }
        if let inactive = try color(tabs, "inactive") { settings.tabIndicator.inactive = inactive }
    }

    if let tiling = try top.table("tiling", allowed: ["split_ratio", "preserve_split", "force_split", "split_width_multiplier", "templates", "smart_split", "split_under_pointer"]) {
        if let list = try templates(tiling) { settings.tiling.templates = list }
        if let name = try tiling.choice("force_split", NewWindowSide.allCases.map(\.rawValue)) { settings.tiling.forceSplit = NewWindowSide(rawValue: name)! }
        if let factor = try tiling.number("split_width_multiplier", min: 0.1, max: 3) { settings.tiling.splitWidthMultiplier = factor }
        if let ratio = try tiling.number("split_ratio", min: 0.1, max: 0.9) { settings.tiling.splitRatio = ratio }
        if let flag = try tiling.bool("preserve_split") { settings.tiling.preserveSplit = flag }
        if let flag = try tiling.bool("smart_split") { settings.tiling.smartSplit = flag }
        if let flag = try tiling.bool("split_under_pointer") { settings.tiling.splitUnderPointer = flag }
    }

    if let scrolling = try top.table("scrolling", allowed: [
        "presets", "default_width", "center", "sliver_width", "sliver_height", "vertical",
        "always_center_single_column", "default_column_display", "preset_heights", "templates",
        "single_window_fit", "visible_columns", "orientation",
    ]) {
        if let list = try templates(scrolling) { settings.scrolling.templates = list }
        if let presets = try scrolling.nonEmptyNumbers("presets", in: 0.05...1) { settings.scrolling.presets = presets }
        if let heights = try scrolling.nonEmptyNumbers("preset_heights", in: 0.1...0.9) { settings.scrolling.presetHeights = heights }
        if let flag = try scrolling.bool("always_center_single_column") { settings.scrolling.alwaysCenterSingleColumn = flag }
        if let name = try scrolling.choice("single_window_fit", SingleWindowFit.allCases.map(\.rawValue)) {
            settings.scrolling.singleWindowFit = SingleWindowFit(rawValue: name)!
        }
        if let name = try scrolling.choice("orientation", ScrollOrientation.allCases.map(\.rawValue)) {
            settings.scrolling.orientation = ScrollOrientation(rawValue: name)!
        }
        if let count = try scrolling.integer("visible_columns", min: 0) { settings.scrolling.visibleColumns = count }
        if let name = try scrolling.choice("default_column_display", ColumnDisplay.allCases.map(\.rawValue)) {
            settings.scrolling.defaultColumnDisplay = ColumnDisplay(rawValue: name)!
        }
        if let width = try scrolling.number("default_width", min: 0.05, max: 1) { settings.scrolling.defaultWidth = width }
        if let mode = try scrolling.choice("center", ["never", "always", "on-overflow"]) { settings.scrolling.center = CenterMode(rawValue: mode)! }
        if let width = try scrolling.number("sliver_width", min: 0) { settings.scrolling.sliverWidth = CGFloat(width) }
        if let height = try scrolling.number("sliver_height", min: 0.05, max: 1) { settings.scrolling.sliverHeight = height }
        if let vertical = try scrolling.table("vertical", allowed: ["side", "width", "row_height"]) {
            if let side = try vertical.choice("side", ["left", "right"]) { settings.scrolling.vertical.side = Direction(rawValue: side)! }
            if let width = try vertical.number("width", min: 0.1, max: 0.9) { settings.scrolling.vertical.width = width }
            if let height = try vertical.number("row_height", min: 0.05, max: 1) { settings.scrolling.vertical.rowHeight = height }
        }
    }

    if let switcher = try top.table("switcher", allowed: ["thumbnails", "delay", "background", "selected", "max_scale"]) {
        if let flag = try switcher.bool("thumbnails") { settings.switcher.thumbnails = flag }
        if let delay = try switcher.number("delay", min: 0) { settings.switcher.delay = delay }
        if let background = try color(switcher, "background") { settings.switcher.background = background }
        if let selected = try color(switcher, "selected") { settings.switcher.selected = selected }
        if let scale = try switcher.number("max_scale", min: 0.3, max: 1) { settings.switcher.maxScale = scale }
    }

    if let prefix = try top.table("prefix", allowed: ["timeout", "menubar", "label"]) {
        // `timeout` is accepted and ignored so that old configs still load: a sequence waits until a key or Escape.
        _ = try prefix.number("timeout", min: 0.1)
        if let flag = try prefix.bool("menubar") { settings.prefix.menuBar = flag }
        if let label = try prefix.table("label", allowed: ["enabled", "position", "offset", "font_size", "background", "foreground", "show_keys", "accent", "font"]) {
            if let flag = try label.bool("enabled") { settings.prefix.label.enabled = flag }
            if let name = try label.choice("position", LabelPosition.allCases.map(\.rawValue), aliases: LabelPosition.aliases) {
                settings.prefix.label.position = LabelPosition(rawValue: name)!
            }
            if let offset = try label.table("offset", allowed: ["x", "y"]) {
                if let x = try offset.number("x") { settings.prefix.label.offsetX = CGFloat(x) }
                if let y = try offset.number("y") { settings.prefix.label.offsetY = CGFloat(y) }
            }
            if let size = try label.number("font_size", min: 8, max: 96) { settings.prefix.label.fontSize = CGFloat(size) }
            if let background = try color(label, "background") { settings.prefix.label.background = background }
            if let foreground = try color(label, "foreground") { settings.prefix.label.foreground = foreground }
            if let flag = try label.bool("show_keys") { settings.prefix.label.showKeys = flag }
            if let name = try label.string("font") { settings.prefix.label.fontName = name.isEmpty ? nil : name }
            if let accent = try color(label, "accent") { settings.prefix.label.accent = accent }
        }
    }

    if let commands = try top.table("commands", allowed: ["mode", "timeout"]) {
        if let name = try commands.choice("mode", CommandSettings.Mode.allCases.map(\.rawValue)) { settings.commands.mode = CommandSettings.Mode(rawValue: name)! }
        // `wm.commands.timeout` is in milliseconds, as in Hyprland.
        if let milliseconds = try commands.number("timeout", min: 100, max: 10_000) { settings.commands.timeout = milliseconds / 1000 }
    }

    if let binds = try top.table("binds", allowed: ["long_press_timeout", "disable_system_cmd_tab", "capslock"]) {
        if let seconds = try binds.number("long_press_timeout", min: 0.1, max: 3) { settings.binds.longPressTimeout = seconds }
        if let flag = try binds.bool("disable_system_cmd_tab") { settings.binds.disableSystemCmdTab = flag }
        if let role = try binds.choice("capslock", ["hyper"]) { settings.binds.capsLockHyper = role == "hyper" }
    }

    if let master = try top.table("master", allowed: ["ratio", "count", "orientation", "new_window"]) {
        if let ratio = try master.number("ratio", min: MasterSettings.minRatio, max: MasterSettings.maxRatio) { settings.master.ratio = ratio }
        if let count = try master.integer("count", min: 1) { settings.master.count = count }
        if let name = try master.choice("orientation", MasterOrientation.allCases.map(\.rawValue)) { settings.master.orientation = MasterOrientation(rawValue: name)! }
        if let name = try master.choice("new_window", MasterSettings.NewWindow.allCases.map(\.rawValue)) { settings.master.newWindow = MasterSettings.NewWindow(rawValue: name)! }
    }

    if let floating = try top.table("floating", allowed: ["remember_position"]) {
        if let flag = try floating.bool("remember_position") { settings.floating.rememberPosition = flag }
    }

    if let entries = top.values["keyboards"] {
        // Names of keyboards are the keys, so there is no fixed list of fields: `default` and then `["name"] = bool`.
        guard case .table(let table) = entries else {
            throw ConfigError(message: "wm.config: 'keyboards' must be a table like { default = true, [\"Keyboard name\"] = false }")
        }
        for (key, value) in table.sorted(by: { $0.key < $1.key }) {
            guard case .bool(let flag) = value else { throw ConfigError(message: "wm.config: 'keyboards.\(key)' must be true or false") }
            if key == "default" { settings.keyboards.defaultEnabled = flag } else { settings.keyboards.overrides[key.lowercased()] = flag }
        }
    }

    if let overview = try top.table("overview", allowed: ["zoom", "gap", "backdrop"]) {
        if let zoom = try overview.number("zoom", min: OverviewSettings.zoomRange.lowerBound, max: OverviewSettings.zoomRange.upperBound) {
            settings.overview.zoom = zoom
        }
        if let gap = try overview.number("gap", min: 0, max: OverviewSettings.maxGap) { settings.overview.gap = gap }
        if let backdrop = try color(overview, "backdrop") { settings.overview.backdrop = backdrop }
    }

    if let hints = try top.table("hints", allowed: ["background", "text", "focus", "area"]) {
        if let background = try color(hints, "background") { settings.hints.background = background }
        if let text = try color(hints, "text") { settings.hints.text = text }
        if let focus = try color(hints, "focus") { settings.hints.focus = focus }
        if let area = try color(hints, "area") { settings.hints.area = area }
    }

    if let special = try top.table("special", allowed: ["size", "backdrop", "hide_on_other_monitor"]) {
        if let size = try special.number("size", min: SpecialSettings.minSize, max: 1) { settings.special.size = size }
        if let backdrop = try color(special, "backdrop") { settings.special.backdrop = backdrop }
        if let flag = try special.bool("hide_on_other_monitor") { settings.special.hideOnOtherMonitor = flag }
    }

    if let zen = try top.table("zen", allowed: ["width"]) {
        if let width = try zen.number("width", min: ZenSettings.minWidth, max: 1) { settings.zen.width = width }
    }

    if let url = try top.table("url", allowed: ["allow"]), let allow = try url.strings("allow") {
        settings.urlAllow = allow
    }
}

/// The `templates` list of the `tiling` or `scrolling` table: the patterns that the picker and the menu list.
/// A template is `{ name, key?, title?, cells, area? }`; `wm.templates` has the built-in ones in this shape.
private func templates(_ group: Fields) throws -> [SplitTemplate]? {
    guard let items = try group.list("templates") else { return nil }
    let list = (group.path + ["templates"]).joined(separator: ".")
    func fail(_ path: String, _ message: String) -> ConfigError { ConfigError(message: "\(group.owner): '\(path)' \(message)") }
    guard !items.isEmpty else { throw fail(list, "must not be empty") }
    var result: [SplitTemplate] = []
    for (index, item) in items.enumerated() {
        let at = "\(list)[\(index + 1)]"
        let fields = try Fields(item, owner: group.owner, path: group.path + ["templates[\(index + 1)]"], allowed: ["name", "key", "title", "cells", "area"])
        guard let name = try fields.string("name"), !name.isEmpty else { throw fail(at + ".name", "is required, for example name = \"70/30\"") }
        guard !name.contains(where: \.isWhitespace), name != "chain" else {
            throw fail(at + ".name", "must have no spaces and must not be \"chain\"")
        }
        let key = try fields.string("key")
        if let key, key.range(of: "^[a-z0-9]$", options: .regularExpression) == nil || key == "c" {
            throw fail(at + ".key", "must be one of a-z or 0-9, and not \"c\" (the chain)")
        }
        guard let rows = try fields.list("cells") else { throw fail(at + ".cells", "is required, a list of { x, y, width, height }") }
        func rect(_ row: LuaValue, _ path: String) throws -> CGRect {
            guard case .array(let values) = row else { throw fail(path, "must be { x, y, width, height }") }
            let numbers = values.compactMap { value -> Double? in
                if case .number(let number) = value { number } else { nil }
            }
            guard numbers.count == 4, values.count == 4 else { throw fail(path, "must be { x, y, width, height }, four numbers") }
            return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        }
        let cells = try rows.enumerated().map { cellIndex, row in try rect(row, "\(at).cells[\(cellIndex + 1)]") }
        // The area is optional: the part of the screen that the cells fill (the middle two thirds, for example).
        var area = SplitTemplate.unit
        if let value = fields.values["area"], value != .nil { area = try rect(value, at + ".area") }
        if let problem = SplitTemplate.shapeError(cells, area: area) {
            throw fail(area == SplitTemplate.unit ? at + ".cells" : at + ".area", "is not valid: " + problem)
        }
        if result.contains(where: { $0.name == name }) { throw fail(at + ".name", "\"\(name)\" is already in this list") }
        if let key, result.contains(where: { $0.key == key }) { throw fail(at + ".key", "\"\(key)\" is already in this list") }
        result.append(SplitTemplate(name: name, key: key, title: try fields.string("title"), cells: cells, area: area))
    }
    return result
}

/// The options of `layout_options` in a workspace rule: the ones of `tiling` and of `scrolling` in `wm.config`, flat.
private let tilingOptionKeys: Set<String> = ["split_ratio", "preserve_split", "force_split", "split_width_multiplier", "smart_split", "split_under_pointer"]
/// The options of the `master` table, in `layout_options` with a `master_` in front (`orientation` is also a scrolling option).
private let masterOptionKeys: Set<String> = ["master_ratio", "master_count", "master_orientation", "master_new_window"]
private let scrollingOptionKeys: Set<String> = [
    "presets", "default_width", "center", "sliver_width", "sliver_height", "vertical",
    "always_center_single_column", "default_column_display", "preset_heights", "single_window_fit", "visible_columns", "orientation",
]

/// Applies the overrides of a workspace rule (a table shaped like `wm.config`: `gaps`, `border`, `tiling`, `scrolling`)
/// on top of `settings`.
public func applyWorkspaceOverrides(_ overrides: LuaValue, to settings: inout Settings) throws {
    try applyConfig(overrides, to: &settings)
}

func parseWorkspaceRule(name: String, _ value: LuaValue) throws -> WorkspaceRule {
    let fields = try Fields(value, owner: "wm.workspace", allowed: ["layout", "monitor", "default", "gaps", "border", "layout_options"])
    guard !fields.values.isEmpty else { throw ConfigError(message: "wm.workspace: '\(name)' needs at least one option") }
    var rule = WorkspaceRule()
    if let layout = try fields.choice("layout", LayoutKind.allCases.map(\.rawValue)) { rule.layout = LayoutKind(rawValue: layout) }
    rule.monitor = try fields.numberOrString("monitor", min: 1)
    rule.isDefault = try fields.bool("default") ?? false
    if rule.isDefault, rule.monitor == nil {
        throw ConfigError(message: "wm.workspace: '\(name)' has 'default' and needs a 'monitor' too")
    }

    var overrides: [String: LuaValue] = [:]
    if let gaps = fields.values["gaps"] { overrides["gaps"] = gaps }
    if let border = try fields.bool("border") { overrides["border"] = .table(["enabled": .bool(border)]) }
    if let options = try fields.table("layout_options", allowed: Array(tilingOptionKeys.union(scrollingOptionKeys).union(masterOptionKeys))) {
        var tiling: [String: LuaValue] = [:], scrolling: [String: LuaValue] = [:], master: [String: LuaValue] = [:]
        for (key, option) in options.values {
            if tilingOptionKeys.contains(key) {
                tiling[key] = option
            } else if masterOptionKeys.contains(key) {
                master[String(key.dropFirst("master_".count))] = option
            } else {
                scrolling[key] = option
            }
        }
        if !tiling.isEmpty { overrides["tiling"] = .table(tiling) }
        if !scrolling.isEmpty { overrides["scrolling"] = .table(scrolling) }
        if !master.isEmpty { overrides["master"] = .table(master) }
    }
    if !overrides.isEmpty {
        // Check the values now, so a mistake is a config error and not a surprise later.
        var scratch = Settings()
        do { try applyConfig(.table(overrides), to: &scratch) } catch let error as ConfigError {
            throw ConfigError(message: error.message.replacingOccurrences(of: "wm.config", with: "wm.workspace '\(name)'"))
        }
        rule.overrides = .table(overrides)
    }
    return rule
}

func parseRule(_ value: LuaValue) throws -> WindowRule {
    let fields = try Fields(value, owner: "wm.rule", allowed: [
        "name", "app", "title", "float", "workspace", "layout", "size", "center", "run", "stop",
        "maximize", "width", "monitor", "focus",
    ])
    var rule = WindowRule()
    rule.name = try fields.string("name")
    rule.app = try fields.string("app")
    rule.title = try fields.string("title")
    guard rule.app != nil || rule.title != nil else {
        throw ConfigError(message: "wm.rule: needs at least one match field ('app' or 'title')")
    }
    if let title = rule.title, (try? NSRegularExpression(pattern: title)) == nil {
        throw ConfigError(message: "wm.rule: 'title' is not a valid regular expression: \(title)")
    }
    rule.float = try fields.bool("float")
    rule.workspace = try fields.numberOrString("workspace", min: 0)
    if let name = try fields.choice("layout", LayoutKind.allCases.map(\.rawValue)) { rule.layout = LayoutKind(rawValue: name) }
    if let size = try fields.numbers("size", in: 0.000001...100_000) {
        guard size.count == 2 else { throw ConfigError(message: "wm.rule: 'size' must be { width, height }") }
        rule.size = RuleSize(width: size[0], height: size[1])
    }
    rule.center = try fields.bool("center") ?? false
    rule.maximize = try fields.bool("maximize")
    rule.width = try fields.number("width", min: 0.05, max: 1)
    rule.focus = try fields.bool("focus")
    rule.monitor = try fields.numberOrString("monitor", min: 1)
    switch fields.values["run"] {
    case .string(let command)?: rule.commands = [command]
    case .some: rule.commands = try fields.strings("run") ?? []
    case nil: break
    }
    rule.stop = try fields.bool("stop") ?? true
    return rule
}
