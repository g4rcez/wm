import Common
import Core
import Foundation

/// Sets an unreadable file aside as `.bak` before the next save replaces it, and says so for the log line: ", kept as <path>".
func keptAs(_ url: URL) -> String {
    setAsideUnreadableFile(at: url).map { ", kept as \($0.path)" } ?? ""
}

/// The file of `wm window remember`: `memory.json` next to `state.json`. It holds no window ids, so a reboot or a reset of the
/// state does not lose it.
enum MemoryStore {
    static var url: URL { StateStore.url.deletingLastPathComponent().appendingPathComponent("memory.json") }

    /// An empty memory when there is no file, or when it cannot be used (another version, damaged).
    static func load(from url: URL = url) -> WindowMemory {
        guard let data = try? Data(contentsOf: url) else { return WindowMemory() }
        do {
            let memory = try JSONDecoder().decode(WindowMemory.self, from: data)
            guard memory.version == WindowMemory.currentVersion else {
                Log.write(.warn, "ignoring \(url.path): version \(memory.version)\(keptAs(url))", source: "memory", prefix: "wmd")
                return WindowMemory()
            }
            return memory
        } catch {
            Log.write(.warn, "ignoring \(url.path): \(error)\(keptAs(url))", source: "memory", prefix: "wmd")
            return WindowMemory()
        }
    }

    static func write(_ memory: WindowMemory, to url: URL = url) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try StateStore.write(try encoder.encode(memory), to: url)
    }
}

/// The file of the places of floating windows that closed: `float-memory.json` next to `memory.json`.
enum FloatMemoryStore {
    static var url: URL { StateStore.url.deletingLastPathComponent().appendingPathComponent("float-memory.json") }

    static func load(from url: URL = url) -> FloatMemory {
        guard let data = try? Data(contentsOf: url) else { return FloatMemory() }
        guard let memory = try? JSONDecoder().decode(FloatMemory.self, from: data), memory.version == FloatMemory.currentVersion else {
            Log.write(.warn, "ignoring \(url.path)\(keptAs(url))", source: "memory", prefix: "wmd")
            return FloatMemory()
        }
        return memory
    }

    static func write(_ memory: FloatMemory, to url: URL = url) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try StateStore.write(try encoder.encode(memory), to: url)
    }
}
