import Foundation

/// Commands that act outside wm (a shell, the keyboard of another app) or hold the connection open. A `wm://` URL may not run them unless the config lists them in `url.allow`: any app or web page can open a URL.
public let urlBlockedCommands: Set<String> = ["exec", "daemon", "subscribe", "key"]

/// The first command of a URL request that the URL may not run, or `nil`. `batch` runs other commands, so each of its commands
/// counts too: `wm://batch?args=exec ...` must not get around the list.
public func urlBlockedCommand(in words: [String], allowed: [String]) -> String? {
    guard let command = words.first else { return nil }
    if command == "batch" {
        let inner = splitBatch(words.dropFirst().joined(separator: " ")).map(splitCommand)
        return inner.lazy.compactMap { urlBlockedCommand(in: $0, allowed: allowed) }.first
    }
    return urlBlockedCommands.contains(command) && !allowed.contains(command) ? command : nil
}

/// Splits a command string into words. Single or double quotes group words. The rest of an `exec` command
/// stays one string, so the shell sees it unchanged.
public func splitCommand(_ command: String) -> [String] {
    var words: [String] = []
    var current = ""
    var quote: Character?
    var hasWord = false
    for character in command {
        if let open = quote {
            if character == open { quote = nil } else { current.append(character) }
        } else if character == "\"" || character == "'" {
            quote = character
            hasWord = true
        } else if character.isWhitespace {
            if hasWord || !current.isEmpty { words.append(current) }
            current = ""
            hasWord = false
            if words == ["exec"] {
                return ["exec", String(command.drop(while: { !$0.isWhitespace }).drop(while: \.isWhitespace))]
            }
        } else {
            current.append(character)
        }
    }
    if hasWord || !current.isEmpty { words.append(current) }
    return words
}

/// `wm://focus?args=left` and `wm://workspace/2` both become command words. Returns `nil` for other schemes.
public func commandWords(fromURL url: URL) -> [String]? {
    guard url.scheme == "wm", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    var words: [String] = []
    if let host = components.host, !host.isEmpty { words.append(host) }
    words += components.path.split(separator: "/").map(String.init)
    guard let command = words.first else { return nil }
    let value = components.queryItems?.first(where: { $0.name == "args" })?.value
    if command == "exec" {
        return ["exec", value ?? ""]
    }
    if let value { words += splitCommand(value) }
    return words
}

/// The commands of `wm batch "a; b; c"`: split at `;` outside quotes, trimmed, empty ones dropped.
public func splitBatch(_ text: String) -> [String] {
    var commands: [String] = []
    var current = ""
    var quote: Character?
    for character in text {
        if let open = quote {
            if character == open { quote = nil }
            current.append(character)
        } else if character == "\"" || character == "'" {
            quote = character
            current.append(character)
        } else if character == ";" {
            commands.append(current)
            current = ""
        } else {
            current.append(character)
        }
    }
    commands.append(current)
    return commands.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

public struct WindowFlagError: Error, Equatable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

/// Whether `text` names a window without an id: `focused`, `app:<name>`, `title:<regex>`, `mark:<name>` or `pid:<number>`.
public func isWindowSelector(_ text: String) -> Bool {
    if text == "focused" { return true }
    for prefix in ["app:", "title:", "mark:"] where text.hasPrefix(prefix) { return text.count > prefix.count }
    if text.hasPrefix("pid:") { return Int32(text.dropFirst(4)) != nil }
    return false
}

private let windowFlagHint = "a window id, or app:<name>, title:<regex>, mark:<name>, pid:<n>, focused"

/// Takes `--window <window>` or `--window=<window>` out of the arguments, wherever it is: `wm --window 5 close` and
/// `wm close --window 5` mean the same. The window is an id (`windowId`) or a selector (`selector`, see
/// `isWindowSelector`). `exec` is left alone: everything after it belongs to the shell command.
/// Arguments without the flag come back unchanged.
public func parseWindowFlag(_ args: [String]) throws -> (windowId: UInt32?, selector: String?, rest: [String]) {
    guard args.first != "exec",
          let index = args.firstIndex(where: { $0 == "--window" || $0.hasPrefix("--window=") }) else { return (nil, nil, args) }
    let usage = WindowFlagError(message: "usage: wm --window <window> <command> [args...]")
    var rest = args
    let value: String
    if args[index] == "--window" {
        guard index + 1 < args.count else { throw WindowFlagError(message: "--window needs \(windowFlagHint)") }
        value = args[index + 1]
        rest.removeSubrange(index...(index + 1))
    } else {
        value = String(args[index].dropFirst("--window=".count))
        rest.remove(at: index)
    }
    guard !rest.isEmpty else { throw usage }
    if let id = UInt32(value) { return (id, nil, rest) }
    guard isWindowSelector(value) else { throw WindowFlagError(message: "--window needs \(windowFlagHint), got '\(value)'") }
    return (nil, value, rest)
}

/// The request in a `wm://` URL: `wm://close?window=3042` acts on window 3042, and `window=app:Notes` on a window
/// of that app. Returns `nil` for other schemes and for a `window` value that is neither an id nor a selector.
public func commandRequest(fromURL url: URL) -> ClientRequest? {
    guard let words = commandWords(fromURL: url) else { return nil }
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    guard let value = items.first(where: { $0.name == "window" })?.value else { return ClientRequest(args: words) }
    if let id = UInt32(value) { return ClientRequest(args: words, windowId: id) }
    guard isWindowSelector(value) else { return nil }
    return ClientRequest(args: words, windowSelector: value)
}
