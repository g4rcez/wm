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
    "start_at_login", "wrap_focus", "tiling", "scrolling", "switcher", "prefix", "url", "tab_indicator", "binds",
]

/// Applies the keys that are present; keys that are absent keep their value, so two `wm.config` calls merge.
func applyConfig(_ value: LuaValue, to settings: inout Settings) throws {
    let owner = "wm.config"
    let top = try Fields(value, owner: owner, allowed: topLevelConfigKeys)

    if let name = try top.choice("layout", LayoutKind.allCases.map(\.rawValue)) { settings.layout = LayoutKind(rawValue: name)! }
    if let name = try top.choice("workspaces", ["emulated", "native"]) { settings.workspaces = WorkspaceMode(rawValue: name)! }
    if let flag = try top.bool("focus_follows_mouse") { settings.focusFollowsMouse = flag }
    if let flag = try top.bool("mouse_follows_focus") { settings.mouseFollowsFocus = flag }
    if let flag = try top.bool("start_at_login") { settings.startAtLogin = flag }
    if let flag = try top.bool("wrap_focus") { settings.wrapFocus = flag }

    if let gaps = try top.table("gaps", allowed: ["inner", "outer"]) {
        if let inner = try gaps.number("inner", min: 0) { settings.gaps.inner = CGFloat(inner) }
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

    if let animations = try top.table("animations", allowed: ["enabled", "rate"]) {
        if let flag = try animations.bool("enabled") { settings.animations.enabled = flag }
        if let rate = try animations.number("rate", min: 0.1) { settings.animations.rate = rate }
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

    if let tiling = try top.table("tiling", allowed: ["split_ratio", "preserve_split", "force_split", "split_width_multiplier"]) {
        if let name = try tiling.choice("force_split", NewWindowSide.allCases.map(\.rawValue)) { settings.tiling.forceSplit = NewWindowSide(rawValue: name)! }
        if let factor = try tiling.number("split_width_multiplier", min: 0.1, max: 3) { settings.tiling.splitWidthMultiplier = factor }
        if let ratio = try tiling.number("split_ratio", min: 0.1, max: 0.9) { settings.tiling.splitRatio = ratio }
        if let flag = try tiling.bool("preserve_split") { settings.tiling.preserveSplit = flag }
    }

    if let scrolling = try top.table("scrolling", allowed: [
        "presets", "default_width", "center", "sliver_width", "sliver_height", "vertical",
        "always_center_single_column", "default_column_display", "preset_heights",
    ]) {
        if let presets = try scrolling.numbers("presets", in: 0.05...1) {
            guard !presets.isEmpty else { throw ConfigError(message: "\(owner): 'scrolling.presets' must not be empty") }
            settings.scrolling.presets = presets
        }
        if let heights = try scrolling.numbers("preset_heights", in: 0.1...0.9) {
            guard !heights.isEmpty else { throw ConfigError(message: "\(owner): 'scrolling.preset_heights' must not be empty") }
            settings.scrolling.presetHeights = heights
        }
        if let flag = try scrolling.bool("always_center_single_column") { settings.scrolling.alwaysCenterSingleColumn = flag }
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

    if let binds = try top.table("binds", allowed: ["long_press_timeout"]) {
        if let seconds = try binds.number("long_press_timeout", min: 0.1, max: 3) { settings.binds.longPressTimeout = seconds }
    }

    if let url = try top.table("url", allowed: ["allow"]), let allow = try url.strings("allow") {
        settings.urlAllow = allow
    }
}

/// The options of `layout_options` in a workspace rule: the ones of `tiling` and of `scrolling` in `wm.config`, flat.
private let tilingOptionKeys: Set<String> = ["split_ratio", "preserve_split", "force_split", "split_width_multiplier"]
private let scrollingOptionKeys: Set<String> = [
    "presets", "default_width", "center", "sliver_width", "sliver_height", "vertical",
    "always_center_single_column", "default_column_display", "preset_heights",
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
    switch fields.values["monitor"] {
    case .number?: rule.monitor = String(try fields.integer("monitor", min: 1)!)
    default: rule.monitor = try fields.string("monitor")
    }
    rule.isDefault = try fields.bool("default") ?? false
    if rule.isDefault, rule.monitor == nil {
        throw ConfigError(message: "wm.workspace: '\(name)' has 'default' and needs a 'monitor' too")
    }

    var overrides: [String: LuaValue] = [:]
    if let gaps = fields.values["gaps"] { overrides["gaps"] = gaps }
    if let border = try fields.bool("border") { overrides["border"] = .table(["enabled": .bool(border)]) }
    if let options = try fields.table("layout_options", allowed: Array(tilingOptionKeys.union(scrollingOptionKeys))) {
        var tiling: [String: LuaValue] = [:], scrolling: [String: LuaValue] = [:]
        for (key, option) in options.values {
            if tilingOptionKeys.contains(key) { tiling[key] = option } else { scrolling[key] = option }
        }
        if !tiling.isEmpty { overrides["tiling"] = .table(tiling) }
        if !scrolling.isEmpty { overrides["scrolling"] = .table(scrolling) }
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
        "app", "title", "float", "workspace", "layout", "size", "center", "run", "stop",
        "maximize", "width", "monitor", "focus",
    ])
    var rule = WindowRule()
    rule.app = try fields.string("app")
    rule.title = try fields.string("title")
    guard rule.app != nil || rule.title != nil else {
        throw ConfigError(message: "wm.rule: needs at least one match field ('app' or 'title')")
    }
    if let title = rule.title, (try? NSRegularExpression(pattern: title)) == nil {
        throw ConfigError(message: "wm.rule: 'title' is not a valid regular expression: \(title)")
    }
    rule.float = try fields.bool("float")
    switch fields.values["workspace"] {
    case .number?: rule.workspace = String(try fields.integer("workspace", min: 0)!)
    default: rule.workspace = try fields.string("workspace")
    }
    if let name = try fields.choice("layout", LayoutKind.allCases.map(\.rawValue)) { rule.layout = LayoutKind(rawValue: name) }
    if let size = try fields.numbers("size", in: 0.000001...100_000) {
        guard size.count == 2 else { throw ConfigError(message: "wm.rule: 'size' must be { width, height }") }
        rule.size = RuleSize(width: size[0], height: size[1])
    }
    rule.center = try fields.bool("center") ?? false
    rule.maximize = try fields.bool("maximize")
    rule.width = try fields.number("width", min: 0.05, max: 1)
    rule.focus = try fields.bool("focus")
    switch fields.values["monitor"] {
    case .number?: rule.monitor = String(try fields.integer("monitor", min: 1)!)
    default: rule.monitor = try fields.string("monitor")
    }
    switch fields.values["run"] {
    case .string(let command)?: rule.commands = [command]
    case .some: rule.commands = try fields.strings("run") ?? []
    case nil: break
    }
    rule.stop = try fields.bool("stop") ?? true
    return rule
}
