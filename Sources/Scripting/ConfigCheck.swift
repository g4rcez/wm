import Foundation

/// A bridge that does nothing, to load a config without acting on it: `wm.exec` and `wm.dispatch` do not run anything, and
/// `wm.query` finds nothing.
public final class NoopBridge: HostBridge, @unchecked Sendable {
    public init() {}
    public func dispatch(_ command: String, window: UInt32?) -> (exitCode: Int32, stdout: String, stderr: String) { (0, "", "") }
    public func query(_ what: String) -> LuaValue { .nil }
    public func exec(_ command: String) {}
    public func exec(_ command: String, options: ExecOptions) {}
    public func log(_ message: String) {}
}

public struct ConfigSummary: Equatable, Sendable {
    public var binds: Int
    /// `init.lua` calls `wm.shortcuts()`.
    public var shortcutsImported = false
    /// Binds that replaced a bind from the other source.
    public var overrides: [BindOverride] = []

    public init(binds: Int, shortcutsImported: Bool = false, overrides: [BindOverride] = []) {
        self.binds = binds
        self.shortcutsImported = shortcutsImported
        self.overrides = overrides
    }
}

/// `wm config check`: runs the config file in a fresh Lua state and says whether it loads. Nothing is applied.
public func checkConfig(at url: URL) -> Result<ConfigSummary, ConfigError> {
    guard FileManager.default.fileExists(atPath: url.path) else {
        return .failure(ConfigError(message: "there is no config file at \(url.path)"))
    }
    do {
        let loaded = try LuaHost(bridge: NoopBridge()).load(configURL: url)
        return .success(ConfigSummary(binds: loaded.bindRecords.count, shortcutsImported: loaded.shortcutsImported, overrides: loaded.overrides))
    } catch let error as ConfigError {
        return .failure(error)
    } catch {
        return .failure(ConfigError(message: "\(error)"))
    }
}

/// The binds that a config defines, without a daemon: `wm cheatsheet tui` uses it when wm does not run.
public func loadBindRecords(at url: URL) -> Result<[BindRecord], ConfigError> {
    guard FileManager.default.fileExists(atPath: url.path) else {
        return .failure(ConfigError(message: "there is no config file at \(url.path)"))
    }
    do {
        return .success(try LuaHost(bridge: NoopBridge()).load(configURL: url).bindRecords)
    } catch let error as ConfigError {
        return .failure(error)
    } catch {
        return .failure(ConfigError(message: "\(error)"))
    }
}
