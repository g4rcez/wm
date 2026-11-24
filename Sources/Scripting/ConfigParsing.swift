import CoreGraphics
import Core
import Foundation

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
        if let unknown = values.keys.filter({ !allowed.contains($0) && !removedKeys.keys.contains((path + [$0]).joined(separator: ".")) }).sorted().first {
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

    func integer(_ key: String, min: Int, max: Int? = nil) throws -> Int? {
        guard let number = try number(key) else { return nil }
        guard number == number.rounded(), number >= Double(min), number <= Double(max ?? 999_999_999) else {
            throw wrong(key, max.map { "a whole number between \(min) and \($0)" } ?? "a whole number, at least \(min)")
        }
        return Int(number)
    }

    func string(_ key: String) throws -> String? {
        guard let value = values[key] else { return nil }
        guard case .string(let text) = value else { throw wrong(key, "a string") }
        return text
    }

    func numberOrString(_ key: String, min: Int) throws -> String? {
        if case .number? = values[key] { return String(try integer(key, min: min)!) }
        return try string(key)
    }

    func nonEmptyNumbers(_ key: String, in range: ClosedRange<Double>) throws -> [Double]? {
        guard let list = try numbers(key, in: range) else { return nil }
        guard !list.isEmpty else { throw ConfigError(message: "\(owner): '\(dotted(key))' must not be empty") }
        return list
    }

    func choice(_ key: String, _ options: [String], aliases: [String: String] = [:]) throws -> String? {
        guard let given = try string(key) else { return nil }
        let text = aliases[given] ?? given
        guard options.contains(text) else {
            throw wrong(key, "one of " + options.map { "\"\($0)\"" }.joined(separator: ", "))
        }
        return text
    }

    func choice<E: CaseIterable & RawRepresentable>(_ key: String, _ type: E.Type, aliases: [String: String] = [:]) throws -> E?
    where E.RawValue == String {
        try choice(key, E.allCases.map(\.rawValue), aliases: aliases).map { E(rawValue: $0)! }
    }

    func table(_ key: String, allowed: [String]) throws -> Fields? {
        guard let value = values[key] else { return nil }
        return try Fields(value, owner: owner, path: path + [key], allowed: allowed)
    }

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

private func hintLetters(_ text: String) throws -> [Character] {
    let letters = Array(text)
    let valid = letters.allSatisfy { $0.isASCII && $0.isLowercase && $0.isLetter }
    guard valid, Set(letters).count == letters.count, HintSettings.letterCount.contains(letters.count) else {
        throw ConfigError(message: "wm.config: 'hints.letters' must be 4 to 26 different lowercase letters, like \"asdfghjkl\"")
    }
    return letters
}

private func animationKind(_ fields: Fields, into kind: inout AnimationKind) throws {
    if let flag = try fields.bool("enabled") { kind.enabled = flag }
    if let rate = try fields.number("rate", min: 0.1) { kind.rate = rate }
}

func colorList(_ fields: Fields, _ key: String) throws -> [Color]? {
    guard let value = fields.values[key] else { return nil }
    let name = (fields.path + [key]).joined(separator: ".")
    let expected = "a color like \"#rrggbb\" or \"#rrggbbaa\", or a list of at least two colors"
    let texts: [String]
    switch value {
    case .string(let text): texts = [text]
    case .array(let items):
        texts = try items.map {
            guard case .string(let text) = $0 else { throw ConfigError(message: "\(fields.owner): '\(name)' must be \(expected)") }
            return text
        }
        guard texts.count >= 2 else { throw ConfigError(message: "\(fields.owner): '\(name)' must be \(expected)") }
    default:
        throw ConfigError(message: "\(fields.owner): '\(name)' must be \(expected)")
    }
    return try texts.map { text in
        guard let color = parseColor(text) else {
            throw ConfigError(message: "\(fields.owner): '\(name)' must be \(expected), got \"\(text)\"")
        }
        return color
    }
}

private func color(_ fields: Fields, _ key: String) throws -> Color? {
    guard let text = try fields.string(key) else { return nil }
    guard let color = parseColor(text) else {
        throw ConfigError(message: "\(fields.owner): '\((fields.path + [key]).joined(separator: "."))' must be a color like \"#rrggbb\" or \"#rrggbbaa\", got \"\(text)\"")
    }
    return color
}

private func selectChords(_ value: LuaValue, action: SelectAction) throws -> [String] {
    let name = "wm.config: 'select.keys.\(action.rawValue)'"
    var texts: [String] = []
    switch value {
    case .string(let text): texts = [text]
    case .array(let items):
        for item in items {
            guard case .string(let text) = item else { throw ConfigError(message: "\(name) must be a chord or a list of chords") }
            texts.append(text)
        }
    case .table(let table) where table.isEmpty: break
    default: throw ConfigError(message: "\(name) must be a chord or a list of chords")
    }
    return try texts.map { text in
        let chord: Chord
        do { chord = try parseChord(text) } catch { throw ConfigError(message: "\(name): \(error)") }
        guard !chord.modifiers.contains(.hyper) else { throw ConfigError(message: "\(name): '\(text)' uses hyper, which select mode cannot see") }
        return SelectSettings.chordName(
            key: chord.key, control: chord.modifiers.contains(.control), option: chord.modifiers.contains(.option),
            shift: chord.modifiers.contains(.shift), command: chord.modifiers.contains(.command))
    }
}

let topLevelConfigKeys = [
    "layout", "workspaces", "gaps", "animations", "border", "focus_follows_mouse", "mouse_follows_focus",
    "start_at_login", "wrap_focus", "mouse", "trackpad", "workspace_back_and_forth", "tiling", "scrolling", "switcher", "prefix", "url",
    "tab_indicator", "binds", "zen", "special", "overview", "hints", "select", "keyboards", "floating", "master",
    "commands", "menubar", "swallow", "urgent", "appearance",
]

private let appearanceKeys = [
    "style", "density", "theme", "material", "accent", "background", "foreground", "secondary", "selection", "border", "border_width",
    "radius", "shadow", "font", "font_size", "mono_font", "animation",
]

private let removedKeys: [String: String] = [
    "switcher.background": "appearance.background", "switcher.selected": "appearance.accent",
    "overview.backdrop": "appearance.background", "prefix.label.background": "appearance.background",
    "prefix.label.foreground": "appearance.foreground", "prefix.label.accent": "appearance.accent",
    "prefix.label.font_size": "appearance.font_size", "prefix.label.font": "appearance.font",
]

private func parseAppearance(_ fields: Fields, into settings: inout AppearanceSettings) throws {
    if let value = try fields.choice("style", AppearanceStyle.self) { settings.style = value }
    if let value = try fields.choice("density", Density.self) { settings.density = value }
    if let value = try fields.choice("theme", ThemeMode.self) { settings.theme = value }
    if let value = try fields.choice("material", OverlayMaterial.self) { settings.material = value }
    if let value = try color(fields, "accent") { settings.accent = value }
    if let value = try color(fields, "background") { settings.background = value }
    if let value = try color(fields, "foreground") { settings.foreground = value }
    if let value = try color(fields, "secondary") { settings.secondary = value }
    if let value = try color(fields, "selection") { settings.selection = value }
    if let value = try color(fields, "border") { settings.border = value }
    let width = AppearanceSettings.borderWidthRange
    if let value = try fields.number("border_width", min: width.lowerBound, max: width.upperBound) { settings.borderWidth = value }
    let radius = AppearanceSettings.radiusRange
    if let value = try fields.number("radius", min: radius.lowerBound, max: radius.upperBound) { settings.radius = value }
    if let value = try fields.bool("shadow") { settings.shadow = value }
    if let value = try fields.string("font") { settings.font = value.isEmpty ? nil : value }
    let size = AppearanceSettings.fontSizeRange
    if let value = try fields.number("font_size", min: size.lowerBound, max: size.upperBound) { settings.fontSize = value }
    if let value = try fields.string("mono_font") { settings.monoFont = value.isEmpty ? nil : value }
    let animation = AppearanceSettings.animationRange
    if let value = try fields.number("animation", min: animation.lowerBound, max: animation.upperBound) { settings.animation = value }
}

private func applyRemovedKeys(_ value: LuaValue, owner: String, to settings: inout AppearanceSettings) throws {
    for (dotted, replacement) in removedKeys.sorted(by: { $0.key < $1.key }) {
        var node: LuaValue? = value
        for part in dotted.split(separator: ".") {
            guard case .table(let values)? = node else { node = nil; break }
            node = values[String(part)]
        }
        guard let node else { continue }
        let key = String(replacement.dropFirst("appearance.".count))
        let fields = try Fields(.table([key: node]), owner: owner, path: ["appearance"], allowed: appearanceKeys)
        try parseAppearance(fields, into: &settings)
    }
}

func applyConfig(_ value: LuaValue, to settings: inout Settings) throws {
    let owner = "wm.config"
    let top = try Fields(value, owner: owner, allowed: topLevelConfigKeys)

    if let value = try top.choice("layout", LayoutKind.self) { settings.layout = value }
    switch top.values["workspaces"] {
    case nil: break
    case .number?: settings.workspaceLimit = try top.integer("workspaces", min: 1, max: 999)
    case .table?:
        let fields = try top.table("workspaces", allowed: ["mode", "max"])!
        if let value = try fields.choice("mode", WorkspaceMode.self) { settings.workspaceMode = value }
        if let value = try fields.integer("max", min: 1, max: 999) { settings.workspaceLimit = value }
    default:
        if let value = try top.choice("workspaces", WorkspaceMode.self) { settings.workspaceMode = value }
    }
    switch top.values["focus_follows_mouse"] {
    case nil: break
    case .table?:
        let fields = try top.table("focus_follows_mouse", allowed: ["enabled", "only_fully_visible"])!
        if let flag = try fields.bool("enabled") { settings.focusFollowsMouse.enabled = flag }
        if let flag = try fields.bool("only_fully_visible") { settings.focusFollowsMouse.onlyFullyVisible = flag }
    default:
        if let flag = try top.bool("focus_follows_mouse") { settings.focusFollowsMouse.enabled = flag }
    }
    if let flag = try top.bool("mouse_follows_focus") { settings.mouseFollowsFocus = flag }
    if let flag = try top.bool("start_at_login") { settings.startAtLogin = flag }
    if let flag = try top.bool("wrap_focus") { settings.wrapFocus = flag }
    if let trackpad = try top.table("trackpad", allowed: ["enabled", "fingers", "scroll_fingers", "speed", "title_bar", "title_bar_height", "pinch"]) {
        if let flag = try trackpad.bool("enabled") {
            settings.trackpad.enabled = flag
            settings.trackpad.warnsWhenMissing = flag
        }
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
        if let flag = try trackpad.bool("title_bar") { settings.trackpad.titleBar = flag }
        if let height = try trackpad.number("title_bar_height", min: 10, max: 200) { settings.trackpad.titleBarHeight = height }
        if let flag = try trackpad.bool("pinch") { settings.trackpad.pinch = flag }
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

    if let animations = try top.table("animations", allowed: ["enabled", "fps", "rate", "windows", "workspaces", "special"]) {
        if let flag = try animations.bool("enabled") { settings.animations.enabled = flag }
        if let fps = try animations.number("fps", min: 30, max: 240) { settings.animations.fps = fps }
        if let rate = try animations.number("rate", min: 0.1) { settings.animations.rate = rate }
        if let windows = try animations.table("windows", allowed: ["enabled", "rate"]) {
            try animationKind(windows, into: &settings.animations.windows)
        }
        for (key, keyPath) in [("workspaces", \AnimationSettings.workspaces), ("special", \AnimationSettings.special)] {
            guard let table = try animations.table(key, allowed: ["enabled", "rate", "style"]) else { continue }
            try animationKind(table, into: &settings.animations[keyPath: keyPath])
            if let style = try table.choice("style", WorkspaceSlide.Style.self) { settings.animations[keyPath: keyPath].style = style }
        }
    }

    if let border = try top.table("border", allowed: ["enabled", "width", "radius", "active", "inactive", "angle"]) {
        if let flag = try border.bool("enabled") { settings.border.enabled = flag }
        if let width = try border.number("width", min: 0) { settings.border.width = CGFloat(width) }
        if let radius = try border.number("radius", min: 0) { settings.border.radius = CGFloat(radius) }
        if let angle = try border.number("angle", min: -3600, max: 3600) { settings.border.angle = angle }
        if let colors = try colorList(border, "active") {
            settings.border.active = colors[0]
            settings.border.gradient = colors.count >= 2 ? colors : []
        }
        if let inactive = try color(border, "inactive") { settings.border.inactive = inactive }
    }

    if let tabs = try top.table("tab_indicator", allowed: ["enabled", "position", "size", "spacing", "radius", "active", "inactive"]) {
        if let flag = try tabs.bool("enabled") { settings.tabIndicator.enabled = flag }
        if let value = try tabs.choice("position", TabIndicatorPosition.self) { settings.tabIndicator.position = value }
        if let size = try tabs.number("size", min: 1, max: 40) { settings.tabIndicator.size = CGFloat(size) }
        if let spacing = try tabs.number("spacing", min: 0, max: 40) { settings.tabIndicator.spacing = CGFloat(spacing) }
        if let radius = try tabs.number("radius", min: 0) { settings.tabIndicator.radius = CGFloat(radius) }
        if let active = try color(tabs, "active") { settings.tabIndicator.active = active }
        if let inactive = try color(tabs, "inactive") { settings.tabIndicator.inactive = inactive }
    }

    if let tiling = try top.table("tiling", allowed: ["split_ratio", "preserve_split", "force_split", "split_width_multiplier", "templates", "smart_split", "split_under_pointer"]) {
        if let list = try templates(tiling) { settings.tiling.templates = list }
        if let value = try tiling.choice("force_split", NewWindowSide.self) { settings.tiling.forceSplit = value }
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
        if let value = try scrolling.choice("single_window_fit", SingleWindowFit.self) { settings.scrolling.singleWindowFit = value }
        if let value = try scrolling.choice("orientation", ScrollOrientation.self) { settings.scrolling.orientation = value }
        if let count = try scrolling.integer("visible_columns", min: 0) { settings.scrolling.visibleColumns = count }
        if let value = try scrolling.choice("default_column_display", ColumnDisplay.self) { settings.scrolling.defaultColumnDisplay = value }
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

    try applyRemovedKeys(value, owner: owner, to: &settings.appearance)
    if let appearance = try top.table("appearance", allowed: appearanceKeys) {
        try parseAppearance(appearance, into: &settings.appearance)
    }

    if let switcher = try top.table("switcher", allowed: ["thumbnails", "delay", "max_scale"]) {
        if let flag = try switcher.bool("thumbnails") { settings.switcher.thumbnails = flag }
        if let delay = try switcher.number("delay", min: 0) { settings.switcher.delay = delay }
        if let scale = try switcher.number("max_scale", min: 0.3, max: 1) { settings.switcher.maxScale = scale }
    }

    if let prefix = try top.table("prefix", allowed: ["timeout", "menubar", "label"]) {
        _ = try prefix.number("timeout", min: 0.1)
        if let flag = try prefix.bool("menubar") { settings.prefix.menuBar = flag }
        if let label = try prefix.table("label", allowed: ["enabled", "position", "offset", "show_keys"]) {
            if let flag = try label.bool("enabled") { settings.prefix.label.enabled = flag }
            if let value = try label.choice("position", LabelPosition.self, aliases: LabelPosition.aliases) { settings.prefix.label.position = value }
            if let offset = try label.table("offset", allowed: ["x", "y"]) {
                if let x = try offset.number("x") { settings.prefix.label.offsetX = CGFloat(x) }
                if let y = try offset.number("y") { settings.prefix.label.offsetY = CGFloat(y) }
            }
            if let flag = try label.bool("show_keys") { settings.prefix.label.showKeys = flag }
        }
    }

    if let menubar = try top.table("menubar", allowed: ["workspaces", "current", "other", "separator", "modes"]) {
        if let value = try menubar.choice("workspaces", MenuBarSettings.Workspaces.self) { settings.menuBar.workspaces = value }
        for (key, assign) in [("current", \MenuBarSettings.current), ("other", \MenuBarSettings.other)] {
            guard let text = try menubar.string(key) else { continue }
            if let word = StatusLabel.unknownPlaceholder(in: text) {
                throw ConfigError(message: "wm.config: 'menubar.\(key)' has {\(word)}; use " + StatusLabel.placeholders.map { "{\($0)}" }.joined(separator: ", "))
            }
            settings.menuBar[keyPath: assign] = text
        }
        if let text = try menubar.string("separator") { settings.menuBar.separator = text }
        if let modes = try menubar.table("modes", allowed: LayoutKind.allCases.map(\.rawValue)) {
            for kind in LayoutKind.allCases {
                if let text = try modes.string(kind.rawValue) { settings.menuBar.modes[kind] = text }
            }
        }
    }

    if let commands = try top.table("commands", allowed: ["mode", "timeout", "layers"]) {
        if let value = try commands.choice("mode", CommandSettings.Mode.self) { settings.commands.mode = value }
        if let milliseconds = try commands.number("timeout", min: 100, max: 10_000) { settings.commands.timeout = milliseconds / 1000 }
        if case .table(let named)? = commands.values["layers"], let layers = try commands.table("layers", allowed: Array(named.keys)) {
            settings.commands.layers = [:]
            for name in named.keys.sorted() {
                let chord: Chord
                do { chord = try parseChord(name) } catch { throw ConfigError(message: "wm.commands.layers: '\(name)': \(error)") }
                guard let layer = try layers.table(name, allowed: ["mode", "timeout"]) else { continue }
                settings.commands.layers[chord.description] = CommandSettings.Layer(
                    mode: try layer.choice("mode", CommandSettings.Mode.self),
                    timeout: try layer.number("timeout", min: 100, max: 10_000).map { $0 / 1000 })
            }
        } else if commands.values["layers"] != nil {
            _ = try commands.table("layers", allowed: [])
        }
    }

    if let binds = try top.table("binds", allowed: ["long_press_timeout", "disable_system_cmd_tab", "capslock"]) {
        if let seconds = try binds.number("long_press_timeout", min: 0.1, max: 3) { settings.binds.longPressTimeout = seconds }
        if let flag = try binds.bool("disable_system_cmd_tab") { settings.binds.disableSystemCmdTab = flag }
        if let role = try binds.choice("capslock", ["hyper"]) { settings.binds.capsLockHyper = role == "hyper" }
    }

    if let master = try top.table("master", allowed: ["ratio", "count", "orientation", "new_window"]) {
        if let ratio = try master.number("ratio", min: MasterSettings.minRatio, max: MasterSettings.maxRatio) { settings.master.ratio = ratio }
        if let count = try master.integer("count", min: 1) { settings.master.count = count }
        if let value = try master.choice("orientation", MasterOrientation.self) { settings.master.orientation = value }
        if let value = try master.choice("new_window", MasterSettings.NewWindow.self) { settings.master.newWindow = value }
    }

    if let floating = try top.table("floating", allowed: ["remember_position"]) {
        if let flag = try floating.bool("remember_position") { settings.floating.rememberPosition = flag }
    }

    if let entries = top.values["keyboards"] {
        guard case .table(let table) = entries else {
            throw ConfigError(message: "wm.config: 'keyboards' must be a table like { default = true, [\"Keyboard name\"] = false }")
        }
        for (key, value) in table.sorted(by: { $0.key < $1.key }) {
            guard case .bool(let flag) = value else { throw ConfigError(message: "wm.config: 'keyboards.\(key)' must be true or false") }
            if key == "default" { settings.keyboards.defaultEnabled = flag } else { settings.keyboards.overrides[key.lowercased()] = flag }
        }
    }

    if let overview = try top.table("overview", allowed: ["zoom", "gap"]) {
        if let zoom = try overview.number("zoom", min: OverviewSettings.zoomRange.lowerBound, max: OverviewSettings.zoomRange.upperBound) {
            settings.overview.zoom = zoom
        }
        if let gap = try overview.number("gap", min: 0, max: OverviewSettings.maxGap) { settings.overview.gap = gap }
    }

    if let hints = try top.table("hints", allowed: ["background", "text", "focus", "area", "letters", "scroll_step", "scroll_dash_factor"]) {
        if let background = try color(hints, "background") { settings.hints.background = background }
        if let text = try color(hints, "text") { settings.hints.text = text }
        if let focus = try color(hints, "focus") { settings.hints.focus = focus }
        if let area = try color(hints, "area") { settings.hints.area = area }
        if let letters = try hints.string("letters") { settings.hints.letters = try hintLetters(letters) }
        if let step = try hints.number("scroll_step", min: HintSettings.stepRange.lowerBound, max: HintSettings.stepRange.upperBound) { settings.hints.scrollStep = step }
        if let factor = try hints.number("scroll_dash_factor", min: HintSettings.dashFactorRange.lowerBound, max: HintSettings.dashFactorRange.upperBound) {
            settings.hints.scrollDashFactor = factor
        }
    }

    if let select = try top.table("select", allowed: ["keys"]),
       let keys = try select.table("keys", allowed: SelectAction.allCases.map(\.rawValue)) {
        for action in SelectAction.allCases {
            guard let value = keys.values[action.rawValue] else { continue }
            settings.select.keys[action] = try selectChords(value, action: action)
        }
        if let clash = settings.select.conflict {
            throw ConfigError(
                message: "wm.config: 'select.keys': '\(clash.chord)' is bound to both '\(clash.first.rawValue)' and '\(clash.second.rawValue)'")
        }
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

    if let urgent = try top.table("urgent", allowed: ["enabled", "interval"]) {
        if let flag = try urgent.bool("enabled") { settings.urgent.enabled = flag }
        if let interval = try urgent.number("interval", min: 1, max: 60) { settings.urgent.interval = interval }
    }

    if let swallow = try top.table("swallow", allowed: ["enabled", "terminals", "exceptions"]) {
        if let flag = try swallow.bool("enabled") { settings.swallow.enabled = flag }
        if let terminals = try swallow.strings("terminals") { settings.swallow.terminals = terminals }
        if let exceptions = try swallow.strings("exceptions") { settings.swallow.exceptions = exceptions }
    }
}

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

private let tilingOptionKeys: Set<String> = ["split_ratio", "preserve_split", "force_split", "split_width_multiplier", "smart_split", "split_under_pointer"]
private let masterOptionKeys: Set<String> = ["master_ratio", "master_count", "master_orientation", "master_new_window"]
private let scrollingOptionKeys: Set<String> = [
    "presets", "default_width", "center", "sliver_width", "sliver_height", "vertical",
    "always_center_single_column", "default_column_display", "preset_heights", "single_window_fit", "visible_columns", "orientation",
]

public func applyWorkspaceOverrides(_ overrides: LuaValue, to settings: inout Settings) throws {
    try applyConfig(overrides, to: &settings)
}

private func parseOnEmpty(_ fields: Fields, workspace: String) throws -> ExecRequest? {
    guard let value = fields.values["on_empty"] else { return nil }
    var options = ExecOptions(rule: WindowRule(stop: true))
    let command: String
    switch value {
    case .string(let text):
        command = text
    case .table(let table):
        guard case .string(let text)? = table["cmd"] else { throw ConfigError(message: "wm.workspace: 'on_empty.cmd' must be a command string") }
        guard table["workspace"] == nil else {
            throw ConfigError(message: "wm.workspace: 'on_empty' cannot have 'workspace': the window goes to this workspace")
        }
        command = text
        var rest = table
        rest["cmd"] = nil
        if let parsed = try parseExecOptions(.table(rest), owner: "wm.workspace", path: ["on_empty"]) { options = parsed }
    default:
        throw ConfigError(message: "wm.workspace: 'on_empty' must be a command string or a table with 'cmd'")
    }
    guard !command.trimmingCharacters(in: .whitespaces).isEmpty else {
        throw ConfigError(message: "wm.workspace: 'on_empty' must not be empty")
    }
    options.rule.workspace = workspace
    return ExecRequest(command: command, options: options)
}

func parseWorkspaceRule(name: String, _ value: LuaValue) throws -> WorkspaceRule {
    let fields = try Fields(
        value, owner: "wm.workspace", allowed: ["layout", "monitor", "default", "gaps", "border", "layout_options", "on_empty", "persistent", "wallpaper", "space"])
    guard !fields.values.isEmpty else { throw ConfigError(message: "wm.workspace: '\(name)' needs at least one option") }
    var rule = WorkspaceRule()
    if let layout = try fields.choice("layout", LayoutKind.self) { rule.layout = layout }
    rule.monitor = try fields.numberOrString("monitor", min: 1)
    rule.isDefault = try fields.bool("default") ?? false
    rule.persistent = try fields.bool("persistent") ?? false
    rule.space = try fields.integer("space", min: 1)
    if let path = try fields.string("wallpaper") {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else {
            throw ConfigError(message: "wm.workspace: 'wallpaper' must be an absolute path or start with ~/, got \"\(path)\"")
        }
        rule.wallpaper = expanded
    }
    rule.onEmpty = try parseOnEmpty(fields, workspace: name)
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
        "name", "app", "title", "role", "subrole", "identifier", "float", "workspace", "layout", "size", "center", "run", "stop",
        "maximize", "width", "monitor", "focus", "dynamic", "border",
    ])
    var rule = WindowRule()
    rule.name = try fields.string("name")
    rule.app = try fields.string("app")
    rule.title = try fields.string("title")
    rule.role = try fields.string("role")
    rule.subrole = try fields.string("subrole")
    rule.identifier = try fields.string("identifier")
    guard rule.app != nil || rule.title != nil || rule.role != nil || rule.subrole != nil || rule.identifier != nil else {
        throw ConfigError(
            message: "wm.rule: needs at least one match field ('app', 'title', 'role', 'subrole' or 'identifier')")
    }
    for (field, pattern) in [("title", rule.title), ("identifier", rule.identifier)] {
        if let pattern, (try? NSRegularExpression(pattern: pattern)) == nil {
            throw ConfigError(message: "wm.rule: '\(field)' is not a valid regular expression: \(pattern)")
        }
    }
    try applyRuleActions(fields, to: &rule)
    rule.stop = try fields.bool("stop") ?? true
    rule.dynamic = try fields.bool("dynamic") ?? false
    rule.border = try colorList(fields, "border")
    return rule
}

private let ruleActionKeys = ["float", "workspace", "layout", "size", "center", "maximize", "width", "monitor", "focus", "run"]

func applyRuleActions(_ fields: Fields, to rule: inout WindowRule) throws {
    rule.float = try fields.bool("float")
    rule.workspace = try fields.numberOrString("workspace", min: 0)
    if let layout = try fields.choice("layout", LayoutKind.self) { rule.layout = layout }
    if let size = try fields.numbers("size", in: 0.000001...100_000) {
        guard size.count == 2 else { throw ConfigError(message: "\(fields.owner): 'size' must be { width, height }") }
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
}

func parseExecOptions(_ value: LuaValue, owner: String = "wm.exec", path: [String] = []) throws -> ExecOptions? {
    if case .nil = value { return nil }
    let fields = try Fields(value, owner: owner, path: path, allowed: ruleActionKeys + ["timeout", "app"])
    var options = ExecOptions(rule: WindowRule(stop: true))
    try applyRuleActions(fields, to: &options.rule)
    if let timeout = try fields.number("timeout", min: ExecOptions.minTimeout, max: ExecOptions.maxTimeout) { options.timeout = timeout }
    options.app = try fields.string("app")
    guard fields.values.keys.contains(where: ruleActionKeys.contains) else {
        if fields.values.isEmpty { return nil }
        throw ConfigError(message: "\(owner): 'timeout' and 'app' need an action for the window, such as 'float' or 'workspace'")
    }
    return options
}
