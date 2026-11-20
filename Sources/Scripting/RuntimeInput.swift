import Core
import Foundation

/// The options that `wm exec` takes before the command: they make a rule for the window that the command opens.
///
///     wm exec --float --center --size 0.5,0.5 -- /Applications/Foo.app/Contents/MacOS/foo
///
/// Options stop at `--` or at the first word that is not an option. Without options the text is the command as it is.
public func parseExecRule(_ text: String) throws -> (rule: WindowRule?, command: String) {
    var words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    var rule = WindowRule(stop: true)
    var seen = false

    func value(_ option: String, _ inline: String?) throws -> String {
        if let inline { return inline }
        guard !words.isEmpty else { throw ConfigError(message: "exec: \(option) needs a value") }
        return words.removeFirst()
    }

    optionLoop: while let first = words.first {
        if first == "--" {
            words.removeFirst()
            break
        }
        guard first.hasPrefix("--") else { break }
        let name = String(first.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)[0])
        let inline = first.contains("=") ? String(first.drop { $0 != "=" }.dropFirst()) : nil
        switch name {
        case "--float": rule.float = true
        case "--tile": rule.float = false
        case "--center": rule.center = true
        case "--maximize": rule.maximize = true
        case "--no-focus": rule.focus = false
        case "--workspace", "--monitor", "--width", "--size", "--layout":
            words.removeFirst()
            let raw = try value(name, inline)
            switch name {
            case "--workspace": rule.workspace = raw
            case "--monitor": rule.monitor = raw
            case "--width":
                guard let width = Double(raw), (0.05...1).contains(width) else { throw ConfigError(message: "exec: --width must be between 0.05 and 1") }
                rule.width = width
            case "--size":
                let parts = raw.split(separator: ",").compactMap { Double($0) }
                guard parts.count == 2, parts.allSatisfy({ $0 > 0 }) else { throw ConfigError(message: "exec: --size needs <width>,<height>, for example 0.5,0.5") }
                rule.size = RuleSize(width: parts[0], height: parts[1])
            default:
                guard let layout = LayoutKind(rawValue: raw) else { throw ConfigError(message: "exec: --layout must be scrolling, tiling, master or monocle") }
                rule.layout = layout
            }
            seen = true
            continue optionLoop
        default:
            // Not an option of ours: the command starts here.
            break optionLoop
        }
        seen = true
        words.removeFirst()
    }
    return (seen ? rule : nil, words.joined(separator: " "))
}

/// A `wm set` value as a config value: `true`, a number, a list of numbers (`0.3,0.5`), or text.
func parseSettingValue(_ text: String) -> LuaValue {
    if text == "true" { return .bool(true) }
    if text == "false" { return .bool(false) }
    if let number = Double(text) { return .number(number) }
    let parts = text.split(separator: ",", omittingEmptySubsequences: false)
    if parts.count > 1, let numbers = parts.map({ Double($0) }) as? [Double] { return .array(numbers.map(LuaValue.number)) }
    return .string(text)
}

/// Changes one config value from text, as `wm set gaps.inner 4` does. The key is a path (`tiling.split_ratio`) and the
/// value is checked like in the config file. `workspaces` (a restart) and `url` (what a web page may run) cannot change
/// this way.
public func applyRuntimeSetting(path: String, value: String, to settings: inout Settings) throws {
    let keys = path.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    guard !keys.isEmpty, keys.allSatisfy({ !$0.isEmpty }) else { throw ConfigError(message: "set: '\(path)' is not a setting name like gaps.inner") }
    guard !["workspaces", "url"].contains(keys[0]) else { throw ConfigError(message: "set: '\(keys[0])' can only change in the config file") }
    var nested = parseSettingValue(value)
    for key in keys.reversed() { nested = .table([key: nested]) }
    do { try applyConfig(nested, to: &settings) } catch let error as ConfigError {
        throw ConfigError(message: error.message.replacingOccurrences(of: "wm.config: ", with: "set: "))
    }
}
