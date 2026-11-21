import Common
import Foundation

/// The files that `wm init` writes by default: the binds of the template are in `shortcuts.toml`, and `init.lua` keeps what
/// TOML cannot say (the settings, the modes and the binds that run a Lua function). `wm init --lua` writes one Lua file instead.
public struct InitFiles: Equatable, Sendable {
    public var lua: String
    public var shortcuts: String
}

private final class NullBridge: HostBridge, @unchecked Sendable {
    func dispatch(_ command: String, window: UInt32?) -> (exitCode: Int32, stdout: String, stderr: String) { (0, "", "") }
    func query(_ what: String) -> LuaValue { .nil }
    func exec(_ command: String) {}
    func log(_ message: String) {}
}

/// The `init.lua` and the `shortcuts.toml` of `template`, with `mod` as the main modifier. The template runs once, and each of
/// its binds of the main mode that is a command becomes a `[[shortcut]]`; the lines of the Lua text that made them are left out.
public func initFiles(_ template: InitTemplate, mod: String) throws -> InitFiles {
    let full = initConfig(template, mod: mod)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wm-init-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("init.lua")
    try Data(full.utf8).write(to: file)
    let config = try LuaHost(bridge: NullBridge()).load(configURL: file)

    let list = config.bindRecords.filter { $0.source == .lua && $0.mode == "main" && $0.trigger == .press && $0.action != "function" }.map {
        Shortcut(keys: $0.keys, action: $0.action, description: $0.options.description, repeating: $0.options.repeating, hidden: $0.options.hidden)
    }
    try validateShortcuts(list)
    // The binds are written with `mod` already: the line that says that `mod` moves them would be wrong.
    let lua = withoutBinds(full).components(separatedBy: "\n").map {
        $0.hasPrefix("-- Change `mod` above") ? "-- The keys of shortcuts.toml were made with this `mod`; run `wm init --force` to make them with another one." : $0
    }.joined(separator: "\n")
    return InitFiles(lua: lua, shortcuts: renderShortcuts(list))
}

/// When a file exists already: `false`, and nothing is written, unless `force`. `url` is the config path, and the shortcuts file is next to it.
public func writeInitFiles(_ files: InitFiles, to url: URL, force: Bool) throws -> Bool {
    let shortcuts = shortcutsURL(for: url)
    let exists = [url, shortcuts].contains { FileManager.default.fileExists(atPath: $0.path) }
    if exists, !force { return false }
    _ = try writeInitConfig(files.lua, to: url, force: true)
    _ = try writeInitConfig(files.shortcuts, to: shortcuts, force: true)
    return true
}

// MARK: Taking the binds out of the Lua text

private func isBindCall(_ line: String) -> Bool {
    let text = line.trimmingCharacters(in: .whitespaces)
    return text.hasPrefix("bind(") || text.hasPrefix("wm.bind(") || text.hasPrefix("app(")
}

/// A bind that runs a Lua function cannot be in the TOML file: it stays.
private func staysInLua(_ line: String) -> Bool { line.contains("cycle(") }

private func isTopLevel(_ line: String) -> Bool { !(line.first?.isWhitespace ?? true) }

private func code(_ line: String) -> String {
    line.trimmingCharacters(in: .whitespaces).hasPrefix("--") ? "" : line.components(separatedBy: " --")[0]
}

/// The Lua text without the top-level `bind` calls, and without the `for` and `if` blocks that hold nothing else.
func withoutBinds(_ text: String) -> String {
    let lines = text.components(separatedBy: "\n")
    var out: [String] = []
    var comments: [String] = []
    var i = 0
    while i < lines.count {
        let line = lines[i]
        if line.hasPrefix("--") {
            comments.append(line)
            i += 1
            continue
        }
        var end = i
        var droppable = isTopLevel(line) && isBindCall(line) && !staysInLua(line)
        if isTopLevel(line), line.hasPrefix("for ") || line.hasPrefix("if ") {
            if line.hasSuffix(" end") {
                droppable = line.contains("bind(") && !staysInLua(line)
            } else if let close = lines[i...].firstIndex(of: "end") {
                end = close
                let body = lines[(i + 1)..<close].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("--") }
                droppable = !body.isEmpty && body.allSatisfy { isBindCall($0) && !staysInLua($0) }
            }
        }
        if droppable {
            comments.removeAll()
        } else {
            out += comments
            comments.removeAll()
            out += lines[i...end]
        }
        i = end + 1
    }
    out += comments
    return dropUnusedHelpers(out).joined(separator: "\n").replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
}

/// A one-line `local` that nothing uses any more (`terminal`, `app`, `bind`...).
private func dropUnusedHelpers(_ lines: [String]) -> [String] {
    var lines = lines
    for name in ["bind", "app", "alt", "ctrl", "terminal"] {
        let pattern = "\\b\(name)\\b"
        guard let index = lines.firstIndex(where: { $0.hasPrefix("local \(name) =") || $0.hasPrefix("local function \(name)(") }) else { continue }
        let used = lines.enumerated().contains { $0.offset != index && code($0.element).range(of: pattern, options: .regularExpression) != nil }
        if !used { lines.remove(at: index) }
    }
    return lines
}
