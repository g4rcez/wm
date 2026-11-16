import Foundation

/// Runs the user's Lua config. All Lua access happens on one private serial queue.
public final class LuaHost: @unchecked Sendable {
    public static let apiVersion = "0.1.0"

    private let bridge: HostBridge
    private let queue = DispatchQueue(label: "wm.lua")
    private static let queueKey = DispatchSpecificKey<Void>()
    // Only touched on `queue`.
    private var current: LuaState?
    private var lastGeneration = 0

    public init(bridge: HostBridge) {
        self.bridge = bridge
        queue.setSpecific(key: Self.queueKey, value: ())
    }

    /// Runs the config file in a fresh Lua state and blocks until it ends. The new state replaces the old one
    /// only on success; on an error the old state (its handlers and function binds) keeps working.
    public func load(configURL: URL) throws -> LoadedConfig {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            throw ConfigError(message: "the config cannot be reloaded from inside a Lua callback")
        }
        return try queue.sync {
            lastGeneration += 1
            let state = try LuaState(bridge: bridge, generation: lastGeneration)
            let config = try state.run(configURL: configURL)
            current = state
            return config
        }
    }

    /// Runs a function bind later on the Lua thread. An id from an older state is ignored.
    public func call(function id: Int) {
        queue.async { [self] in
            guard let state = current, id >> 32 == state.generation else { return }
            state.call(ref: Int32(truncatingIfNeeded: id))
        }
    }

    /// Calls the `wm.on` handlers of `event` later on the Lua thread.
    public func fire(event: String, payload: [String: LuaValue]) {
        queue.async { [self] in
            current?.fire(event: event, payload: payload)
        }
    }

    /// Waits until the work queued so far has run. For tests.
    func flush() {
        queue.sync {}
    }
}
