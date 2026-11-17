import Foundation

public struct Modifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let shift = Modifiers(rawValue: 1 << 0)
    public static let control = Modifiers(rawValue: 1 << 1)
    public static let option = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
    /// The key that `binds.capslock = "hyper"` makes of CapsLock. It is not a flag of macOS: wm keeps the state itself.
    public static let hyper = Modifiers(rawValue: 1 << 4)

    /// The display order of the modifiers, with the name and the symbol of each.
    private static let displayOrder: [(modifier: Modifiers, name: String, symbol: String)] = [
        (.hyper, "hyper", "✦"), (.control, "ctrl", "⌃"), (.option, "alt", "⌥"), (.shift, "shift", "⇧"), (.command, "cmd", "⌘"),
    ]

    /// The names of the modifiers in this set, in the order hyper, ctrl, alt, shift, cmd.
    var names: [String] { Self.displayOrder.filter { contains($0.modifier) }.map(\.name) }

    /// The symbols of the modifiers in this set, in the order ⌃⌥⇧⌘.
    var symbols: String { Self.displayOrder.filter { contains($0.modifier) }.map(\.symbol).joined() }
}

/// A key combination. `key` is a canonical lowercase name such as `h`, `2`, `esc` or `leftsquarebracket`.
public struct Chord: Hashable, Sendable, CustomStringConvertible {
    public var modifiers: Modifiers
    public var key: String

    /// Canonical display name such as `ctrl-alt-shift-cmd-p`: modifiers in the order hyper, ctrl, alt, shift, cmd, then the key.
    public var description: String {
        (modifiers.names + [key]).joined(separator: "-")
    }

    public init(modifiers: Modifiers, key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    /// The screenshot shortcuts of macOS: Cmd+Shift+3, 4, 5 or 6, also with Ctrl (the picture goes to the clipboard).
    public var isScreenshotShortcut: Bool {
        modifiers.isSuperset(of: [.command, .shift]) && !modifiers.contains(.option) && ["3", "4", "5", "6"].contains(key)
    }
}

public struct ChordError: Error, Sendable, Equatable, CustomStringConvertible, LocalizedError {
    public let message: String
    public init(message: String) { self.message = message }
    public var description: String { message }
    public var errorDescription: String? { message }
}

private let modifierNames: [String: Modifiers] = [
    "shift": .shift,
    "ctrl": .control, "control": .control,
    "alt": .option, "opt": .option, "option": .option,
    "cmd": .command, "command": .command,
]

/// The modifiers of a chord. Gestures and the mouse take `modifierNames`: they read the flags of macOS, which have no hyper.
private let chordModifierNames = modifierNames.merging(["hyper": .hyper]) { first, _ in first }

/// Keys that wm can type but that are not on a US keyboard row: `wm.remap`, `wm.press` and `key press` take them.
public let mediaKeyNames: Set<String> = [
    "volume_up", "volume_down", "mute", "play", "next", "previous", "brightness_up", "brightness_down",
]

private let keyAliases: [String: String] = [
    "escape": "esc", "return": "enter",
    "leftarrow": "left", "rightarrow": "right", "uparrow": "up", "downarrow": "down",
    "leftbracket": "leftsquarebracket", "rightbracket": "rightsquarebracket",
]

private let namedKeys: Set<String> = [
    "esc", "space", "tab", "enter", "backspace", "delete",
    "left", "right", "up", "down",
    "minus", "equal", "comma", "period", "slash", "backslash", "semicolon", "quote", "backtick",
    "leftsquarebracket", "rightsquarebracket",
    "home", "end", "pageup", "pagedown",
]

private let singleKeys: Set<String> = Set("abcdefghijklmnopqrstuvwxyz0123456789".map(String.init))
private let functionKeys: Set<String> = Set((1...20).map { "f\($0)" })

/// Parses `alt-shift-h`, `cmd + ctrl - 2`, `esc`. Modifiers and key are joined by `-` or `+`; the last token is the key.
/// `allowMedia`: the key can also be a media key such as `play`; only for keys that wm types, not for keys that it binds.
public func parseChord(_ text: String, allowMedia: Bool = false) throws -> Chord {
    func fail(_ reason: String) -> ChordError {
        ChordError(message: "invalid chord '\(text)': \(reason)")
    }

    let tokens = text.split(omittingEmptySubsequences: false) { $0 == "-" || $0 == "+" }
        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    guard tokens.allSatisfy({ !$0.isEmpty }) else {
        throw fail(text.trimmingCharacters(in: .whitespaces).isEmpty ? "it is empty" : "a modifier or key name is missing")
    }

    var modifiers: Modifiers = []
    for token in tokens.dropLast() {
        guard let modifier = chordModifierNames[token] else {
            throw fail("unknown modifier '\(token)' (use hyper, shift, ctrl, alt, cmd)")
        }
        modifiers.insert(modifier)
    }

    let token = tokens[tokens.count - 1]
    let key = keyAliases[token] ?? token
    guard namedKeys.contains(key) || singleKeys.contains(key) || functionKeys.contains(key) || (allowMedia && mediaKeyNames.contains(key)) else {
        throw fail("unknown key '\(token)'")
    }
    return Chord(modifiers: modifiers, key: key)
}

/// Parses the modifiers of a gesture: `alt`, `alt shift`, `cmd+ctrl`. At least one is needed.
public func parseModifiers(_ text: String) throws -> Modifiers {
    let tokens = text.split { $0 == " " || $0 == "+" || $0 == "-" }.map { $0.lowercased() }
    guard !tokens.isEmpty else { throw ChordError(message: "needs at least one modifier (shift, ctrl, alt, cmd)") }
    var modifiers: Modifiers = []
    for token in tokens {
        guard let modifier = modifierNames[token] else {
            throw ChordError(message: "unknown modifier '\(token)' (use shift, ctrl, alt, cmd)")
        }
        modifiers.insert(modifier)
    }
    return modifiers
}

/// Parses `ctrl-p>h` or `alt-space > t > n`: chords separated by `>`. A lone chord gives an array of 1.
public func parseChordSequence(_ text: String) throws -> [Chord] {
    let steps = text.split(separator: ">", omittingEmptySubsequences: false)
    if steps.count == 1 { return [try parseChord(text)] }
    return try steps.map { step in
        guard !step.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ChordError(message: "invalid key sequence '\(text)': a step is empty (use chords separated by a single '>')")
        }
        return try parseChord(String(step))
    }
}
