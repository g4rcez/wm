import Foundation

/// The file that the Shortcuts window writes and that `wm.shortcuts()` loads, next to `init.lua`.
public let shortcutsFileName = "shortcuts.toml"

public func shortcutsURL(for configURL: URL) -> URL {
    configURL.deletingLastPathComponent().appendingPathComponent(shortcutsFileName)
}

/// The keys of a `[[shortcut]]`. `types/shortcuts.schema.json` lists the same keys, for the completion of the editor.
public let shortcutKeys = ["action", "description", "hidden", "keys", "long_press", "mode", "release", "remap", "repeating", "universal"]

/// One `[[shortcut]]` of `shortcuts.toml`: the same thing as one `wm.bind` (or `wm.remap`) call.
public struct Shortcut: Equatable, Sendable {
    public enum LongPress: Equatable, Sendable {
        /// `long_press = true`: it waits for `binds.long_press_timeout`.
        case on
        case seconds(Double)
    }

    /// A chord (`alt-h`) or a sequence (`ctrl-p>h`).
    public var keys: String
    /// A wm command line. Exactly one of `action` and `remap` is set.
    public var action: String?
    /// The key to type instead of `keys`.
    public var remap: String?
    public var mode: String
    public var description: String?
    public var repeating: Bool?
    public var release: Bool
    public var longPress: LongPress?
    public var universal: Bool
    public var hidden: Bool

    public init(
        keys: String, action: String? = nil, remap: String? = nil, mode: String = "main", description: String? = nil,
        repeating: Bool? = nil, release: Bool = false, longPress: LongPress? = nil, universal: Bool = false, hidden: Bool = false
    ) {
        self.keys = keys
        self.action = action
        self.remap = remap
        self.mode = mode
        self.description = description
        self.repeating = repeating
        self.release = release
        self.longPress = longPress
        self.universal = universal
        self.hidden = hidden
    }

    /// The same rule as in `wm.bind`: `repeating = true` on a single chord is a hold bind.
    public var trigger: BindTrigger {
        if release { return .release }
        if longPress != nil { return .longPress }
        if repeating == true, !keys.contains(">") { return .hold }
        return .press
    }

    /// The mode, the canonical keys and the trigger: two shortcuts with the same identity are the same bind.
    /// `nil` when the keys do not parse.
    public var identity: String? {
        guard let chords = try? parseChordSequence(keys) else { return nil }
        return "\(universal ? universalMode : mode)|\(chords.map(\.description).joined(separator: ">"))|\(trigger.rawValue)"
    }

    /// Throws what `wm.bind` would throw for this shortcut, so the file never holds a bind that the config cannot load.
    public func validate() throws {
        let chords: [Chord]
        do { chords = try parseChordSequence(keys) } catch { throw ConfigError(message: "keys '\(keys)': \(error)") }
        if mode.isEmpty { throw ConfigError(message: "'\(keys)': the mode is empty") }
        if mode == universalMode { throw ConfigError(message: "'\(keys)': mode '*' is reserved, use universal = true") }
        if action != nil && remap != nil { throw ConfigError(message: "'\(keys)' has both 'action' and 'remap': use one") }
        if action == nil && remap == nil { throw ConfigError(message: "'\(keys)' needs an 'action' or a 'remap'") }
        if release && longPress != nil { throw ConfigError(message: "'\(keys)' cannot be both 'release' and 'long_press'") }
        if case .seconds(let seconds) = longPress, !(0.1...3).contains(seconds) {
            throw ConfigError(message: "'long_press' for '\(keys)' must be between 0.1 and 3 seconds")
        }
        if trigger == .release || trigger == .longPress {
            if chords.count > 1 { throw ConfigError(message: "'\(keys)' is a key sequence; 'release' and 'long_press' need a single chord") }
            if repeating != nil { throw ConfigError(message: "'repeating' does not apply to '\(keys)': it does not run when the key goes down") }
        }
        if let remap {
            guard chords.count == 1, trigger == .press, repeating != true else {
                throw ConfigError(message: "'\(keys)' is a remap: it needs a single chord that runs when the key goes down")
            }
            let target: Chord
            do { target = try parseChord(remap, allowMedia: true) } catch { throw ConfigError(message: "remap of '\(keys)': \(error)") }
            if target.modifiers.contains(.hyper) { throw ConfigError(message: "remap of '\(keys)': 'hyper' is not a key that wm can type") }
        }
    }

    /// The arguments of `native.bind`, for the Lua side of `wm.shortcuts()`.
    var luaValue: LuaValue {
        var options: [String: LuaValue] = [:]
        if let description { options["description"] = .string(description) }
        if let repeating { options["repeating"] = .bool(repeating) }
        if release { options["release"] = .bool(true) }
        switch longPress {
        case .on?: options["long_press"] = .bool(true)
        case .seconds(let seconds)?: options["long_press"] = .number(seconds)
        case nil: break
        }
        if universal { options["universal"] = .bool(true) }
        if hidden { options["hidden"] = .bool(true) }
        let target: LuaValue = remap.map { .table(["remap": .string($0)]) } ?? .string(action ?? "")
        return .table(["mode": .string(mode), "keys": .string(keys), "action": target, "options": .table(options)])
    }
}

/// The indexes of the first two shortcuts that are the same bind, if any.
func firstDuplicate(in list: [Shortcut]) -> (Int, Int)? {
    var seen: [String: Int] = [:]
    for (index, shortcut) in list.enumerated() {
        guard let identity = shortcut.identity else { continue }
        if let first = seen[identity] { return (first, index) }
        seen[identity] = index
    }
    return nil
}

/// The indexes of the first two press shortcuts of one mode where a chord is also the start of a sequence, or a sequence
/// is the start of a longer one: `wm.bind` refuses that pair, so the config would not load.
func firstPrefixConflict(in list: [Shortcut]) -> (Int, Int)? {
    let entries = list.enumerated().compactMap { index, shortcut -> (index: Int, mode: String, chords: [Chord])? in
        guard shortcut.trigger == .press || shortcut.trigger == .hold, let chords = try? parseChordSequence(shortcut.keys) else { return nil }
        return (index, shortcut.universal ? universalMode : shortcut.mode, chords)
    }
    for first in entries {
        for second in entries where first.index < second.index && first.mode == second.mode && first.chords != second.chords {
            if first.chords.starts(with: second.chords) || second.chords.starts(with: first.chords) { return (first.index, second.index) }
        }
    }
    return nil
}

/// Checks every shortcut and that none is the same bind as another. The Shortcuts window calls it before a save.
public func validateShortcuts(_ list: [Shortcut]) throws {
    for (index, shortcut) in list.enumerated() {
        do { try shortcut.validate() } catch { throw ConfigError(message: "shortcut \(index + 1): \(error)") }
    }
    if let (first, second) = firstDuplicate(in: list) {
        throw ConfigError(message: "shortcuts \(first + 1) and \(second + 1) are the same bind: '\(list[second].keys)'")
    }
    if let (first, second) = firstPrefixConflict(in: list) {
        throw ConfigError(message: "'\(list[first].keys)' and '\(list[second].keys)' conflict: a chord cannot also start a sequence")
    }
}

/// The shortcuts of the file at `url`. A missing file is no shortcuts. A file that cannot be read, or that holds a bind
/// that `wm.bind` would refuse, throws a message with the line.
public func readShortcuts(at url: URL) throws -> [Shortcut] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let text: String
    do { text = try String(contentsOf: url, encoding: .utf8) } catch {
        throw ConfigError(message: "\(shortcutsFileName): cannot read the file: \(error.localizedDescription)")
    }
    return try parseShortcuts(text)
}

func parseShortcuts(_ text: String) throws -> [Shortcut] {
    func fail(_ line: Int, _ message: String) -> ConfigError { ConfigError(message: "\(shortcutsFileName) line \(line): \(message)") }
    let tables: [TomlTable]
    do { tables = try parseToml(text) } catch let error as TomlError { throw fail(error.line, error.message) }

    var list: [Shortcut] = []
    for table in tables {
        guard table.name == "shortcut" else { throw fail(table.line, "unknown table [[\(table.name)]]; the only table is [[shortcut]]") }
        if let key = table.values.keys.filter({ !shortcutKeys.contains($0) }).min() {
            throw fail(table.keyLines[key] ?? table.line, "unknown key '\(key)' (allowed: \(shortcutKeys.joined(separator: ", ")))")
        }
        func line(_ key: String) -> Int { table.keyLines[key] ?? table.line }
        func string(_ key: String) throws -> String? {
            guard let value = table.values[key] else { return nil }
            guard case .string(let text) = value else { throw fail(line(key), "'\(key)' must be a string") }
            return text
        }
        func bool(_ key: String) throws -> Bool? {
            guard let value = table.values[key] else { return nil }
            guard case .bool(let flag) = value else { throw fail(line(key), "'\(key)' must be true or false") }
            return flag
        }

        guard let keys = try string("keys") else { throw fail(table.line, "the shortcut needs 'keys'") }
        var shortcut = Shortcut(keys: keys, action: try string("action"), remap: try string("remap"))
        shortcut.mode = try string("mode") ?? "main"
        shortcut.description = try string("description")
        shortcut.repeating = try bool("repeating")
        shortcut.release = try bool("release") ?? false
        shortcut.universal = try bool("universal") ?? false
        shortcut.hidden = try bool("hidden") ?? false
        switch table.values["long_press"] {
        case nil, .bool(false)?: break
        case .bool(true)?: shortcut.longPress = .on
        case .int(let seconds)?: shortcut.longPress = .seconds(Double(seconds))
        case .double(let seconds)?: shortcut.longPress = .seconds(seconds)
        case .string?: throw fail(line("long_press"), "'long_press' must be true, false or a number of seconds")
        }
        do { try shortcut.validate() } catch { throw fail(table.line, "\(error)") }
        list.append(shortcut)
    }
    if let (first, second) = firstDuplicate(in: list) {
        throw fail(tables[second].line, "'\(list[second].keys)' is the same bind as the shortcut at line \(tables[first].line)")
    }
    if let (first, second) = firstPrefixConflict(in: list) {
        throw fail(tables[second].line, "'\(list[second].keys)' conflicts with '\(list[first].keys)' at line \(tables[first].line): a chord cannot also start a sequence")
    }
    return list
}

/// The text of `shortcuts.toml` for `list`. The key order is fixed, so a save changes only what the user changed.
public func renderShortcuts(_ list: [Shortcut]) -> String {
    var text = """
        # Managed by wm: the Shortcuts window rewrites this file and drops the comments.
        # init.lua loads it with wm.shortcuts(); a wm.bind in init.lua for the same keys replaces the shortcut.

        """
    for shortcut in list {
        text += "\n[[shortcut]]\n"
        text += "keys = \(tomlString(shortcut.keys))\n"
        if shortcut.mode != "main" { text += "mode = \(tomlString(shortcut.mode))\n" }
        if let action = shortcut.action { text += "action = \(tomlString(action))\n" }
        if let remap = shortcut.remap { text += "remap = \(tomlString(remap))\n" }
        if let description = shortcut.description { text += "description = \(tomlString(description))\n" }
        if let repeating = shortcut.repeating { text += "repeating = \(repeating)\n" }
        if shortcut.release { text += "release = true\n" }
        switch shortcut.longPress {
        case .on?: text += "long_press = true\n"
        case .seconds(let seconds)?: text += "long_press = \(seconds)\n"
        case nil: break
        }
        if shortcut.universal { text += "universal = true\n" }
        if shortcut.hidden { text += "hidden = true\n" }
    }
    return text
}

/// Writes `list` to `url` (atomically). Throws, and leaves the file as it is, when a shortcut is not valid.
public func writeShortcuts(_ list: [Shortcut], to url: URL) throws {
    try validateShortcuts(list)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(renderShortcuts(list).utf8).write(to: url, options: .atomic)
}
