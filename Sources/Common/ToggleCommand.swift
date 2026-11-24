import Foundation

/// The word that `hints`, `scroll` and `jump` take: open the mode, close it, or switch it.
public enum ToggleMode: String, Sendable, CaseIterable {
    case open, close, toggle
}

/// What follows the command name of `wm hints`, `wm scroll` or `wm jump`.
public struct ToggleArguments: Equatable, Sendable {
    /// Every word that starts with `--`, known or not. The caller checks them against the options of its command first.
    public let flags: Set<String>
    /// The mode word, or `nil` when there is none (the caller then toggles).
    public let mode: ToggleMode?
    /// `false` when there is more than one word that is not an option, or the word is not `open`, `close` or `toggle`.
    public let isValid: Bool
}

/// Splits the words after the command name into options and the mode. It does not know which options a command has.
public func parseToggleArguments(_ args: [String]) -> ToggleArguments {
    let flags = Set(args.filter { $0.hasPrefix("--") })
    let words = args.filter { !$0.hasPrefix("--") }
    guard let word = words.first else { return ToggleArguments(flags: flags, mode: nil, isValid: true) }
    let mode = ToggleMode(rawValue: word)
    return ToggleArguments(flags: flags, mode: mode, isValid: words.count == 1 && mode != nil)
}

/// What `wm hints` labels: every window that shows on the screen (the default), or only the focused one.
public enum HintScope: String, Sendable {
    case all, window
}

/// Splits the words after `wm hints` into the scope and the rest, which `parseToggleArguments` reads. The scope word can be
/// before or after the mode word; a second scope word is left in the rest, so the arguments are not valid.
public func parseHintsArguments(_ args: [String]) -> (scope: HintScope, toggle: ToggleArguments) {
    var rest = args
    var scope = HintScope.all
    if let index = rest.firstIndex(where: { HintScope(rawValue: $0) != nil }) {
        scope = HintScope(rawValue: rest.remove(at: index)) ?? .all
    }
    return (scope, parseToggleArguments(rest))
}
