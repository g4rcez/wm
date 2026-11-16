import Scripting

/// Fan-out of window manager events to Lua handlers and `wm subscribe` clients.
@MainActor
final class EventHub {
    typealias Sink = @MainActor (_ name: String, _ payload: [String: LuaValue]) -> Void
    private var sinks: [Sink] = []

    func add(_ sink: @escaping Sink) {
        sinks.append(sink)
    }

    func emit(_ name: String, _ payload: [String: LuaValue] = [:]) {
        for sink in sinks { sink(name, payload) }
    }
}
