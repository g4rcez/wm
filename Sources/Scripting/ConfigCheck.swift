import Foundation

/// A bridge that does nothing, to load a config without acting on it: `wm.exec` and `wm.dispatch` do not run anything, and
/// `wm.query` finds nothing.
public final class NoopBridge: HostBridge, @unchecked Sendable {
    public init() {}
    public func dispatch(_ command: String, window: UInt32?) -> (exitCode: Int32, stdout: String, stderr: String) { (0, "", "") }
    public func query(_ what: String) -> LuaValue { .nil }
    public func exec(_ command: String) {}
    public func log(_ message: String) {}
}

public struct ConfigSummary: Equatable, Sendable {
    public var binds: Int
}

/// `wm config check`: runs the config file in a fresh Lua state and says whether it loads. Nothing is applied.
public func checkConfig(at url: URL) -> Result<ConfigSummary, ConfigError> {
    guard FileManager.default.fileExists(atPath: url.path) else {
        return .failure(ConfigError(message: "there is no config file at \(url.path)"))
    }
    do {
        let loaded = try LuaHost(bridge: NoopBridge()).load(configURL: url)
        return .success(ConfigSummary(binds: loaded.bindRecords.count))
    } catch let error as ConfigError {
        return .failure(error)
    } catch {
        return .failure(ConfigError(message: "\(error)"))
    }
}
