import CLua
import Core
import Foundation

// The C macros are not imported into Swift.
private let registryIndex: Int32 = -1_001_000 // LUA_REGISTRYINDEX
private let maskCount: Int32 = 1 << 3 // LUA_MASKCOUNT
private let timeLimit: Int64 = 2_000_000_000
private let deadlineKey = "wm.deadline"

private let prelude = """
local native, version = ...
local wm = { version = version }

local function expect(ok, message)
  if not ok then error(message, 3) end
end
local function done(ok, err)
  if not ok then error(err, 3) end
end

function wm.config(options)
  expect(type(options) == "table", "wm.config expects a table")
  done(native.config(options))
end

function wm.bind(chord, action, options)
  expect(type(chord) == "string", "wm.bind expects a chord string like 'alt-h' or a sequence like 'ctrl-p>h'")
  expect(options == nil or type(options) == "table", "wm.bind: the options must be a table like { description = '...' }")
  done(native.bind("main", chord, action, options))
end

function wm.mode(name, binds)
  expect(type(name) == "string" and name ~= "", "wm.mode expects a mode name")
  expect(type(binds) == "table", "wm.mode expects a table of chord = action")
  done(native.reset_mode(name))
  for chord, action in pairs(binds) do
    -- A table is an action with options: { "focus left", description = "...", repeating = false }.
    if type(action) == "table" then
      local options = {}
      for key, value in pairs(action) do
        if key ~= 1 then options[key] = value end
      end
      done(native.bind(name, chord, action[1], options))
    else
      done(native.bind(name, chord, action))
    end
  end
end

function wm.gesture(spec)
  expect(type(spec) == "table", "wm.gesture expects a table like { mods = 'alt', direction = 'left', command = 'workspace prev' }")
  local options = {}
  for key, value in pairs(spec) do
    if key ~= "command" then options[key] = value end
  end
  done(native.gesture(options, spec.command))
end

function wm.rule(spec)
  expect(type(spec) == "table", "wm.rule expects a table")
  done(native.rule(spec))
end

function wm.workspace(name, spec)
  expect(type(name) == "string" or type(name) == "number", "wm.workspace expects a workspace name")
  expect(type(spec) == "table", "wm.workspace expects a table as its 2nd argument")
  done(native.workspace(tostring(name), spec))
end

function wm.on(event, filter, handler)
  if handler == nil then filter, handler = nil, filter end
  expect(type(event) == "string" and event ~= "", "wm.on expects an event name")
  expect(filter == nil or type(filter) == "table", "wm.on: the filter must be a table")
  expect(type(handler) == "function", "wm.on expects a function")
  done(native.on(event, filter, handler))
end

function wm.dispatch(command, options)
  expect(type(command) == "string", "wm.dispatch expects a command string")
  expect(options == nil or type(options) == "table", "wm.dispatch: the options must be a table like { window = 123 }")
  local window
  if options ~= nil then
    for key in pairs(options) do
      expect(key == "window", "wm.dispatch: unknown option '" .. tostring(key) .. "'")
    end
    window = options.window
    -- A selector ("app:Notes", "title:^Inbox", "pid:412", "focused") goes to the command as `--window "<selector>"`.
    if type(window) == "string" and (window == "focused" or window:match("^app:.") or window:match("^title:.") or window:match("^pid:%d+$")) then
      command = '--window "' .. window .. '" ' .. command
      window = nil
    end
    expect(window == nil or (type(window) == "number" and window >= 0 and window <= 4294967295 and window == math.floor(window)),
      "wm.dispatch: 'window' must be a whole number >= 0, or a selector like 'app:Notes'")
  end
  return native.dispatch(command, window)
end

function wm.query(kind)
  expect(type(kind) == "string", "wm.query expects a string")
  return native.query(kind)
end

function wm.exec(command)
  expect(type(command) == "string", "wm.exec expects a command string")
  native.exec(command)
end

function wm.log(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  native.log(table.concat(parts, " "))
end

-- Would end the whole app.
function os.exit()
  error("os.exit is disabled in the wm config", 2)
end

_G.wm = wm
"""

/// One Lua state with the `wm` API. All methods run on the host's Lua queue.
final class LuaState {
    private struct Handler {
        let event: String
        let filter: [String: LuaValue]
        let ref: Int32
    }

    let generation: Int
    fileprivate let bridge: HostBridge
    fileprivate let L: OpaquePointer
    fileprivate var settings = Settings()
    fileprivate var binds: [String: [Chord: BindAction]] = ["main": [:]]
    fileprivate var sequences: [String: [[Chord]: BindAction]] = [:]
    fileprivate var releaseBinds: [String: [Chord: BindAction]] = [:]
    fileprivate var longPressBinds: [String: [Chord: BindAction]] = [:]
    fileprivate var noRepeat: [String: Set<Chord>] = [:]
    fileprivate var bindRecords: [BindRecord] = []
    fileprivate var gestures: [Gesture] = []
    fileprivate var rules: [WindowRule] = []
    fileprivate var workspaceLayouts: [String: LayoutKind] = [:]
    fileprivate var workspaceRules: [String: WorkspaceRule] = [:]
    private var handlers: [Handler] = []
    /// `wm.config`, `wm.bind`, `wm.mode`, `wm.rule` and `wm.workspace` work only while the config file runs.
    fileprivate var loading = true

    init(bridge: HostBridge, generation: Int) throws {
        guard let state = luaL_newstate() else { throw ConfigError(message: "cannot create a Lua state") }
        self.L = state
        self.bridge = bridge
        self.generation = generation
        luaL_openlibs(L)
        try installAPI()
    }

    deinit { lua_close(L) }

    func run(configURL: URL) throws -> LoadedConfig {
        let directory = configURL.deletingLastPathComponent().path
        let setup = "local dir = ...; package.path = dir .. '/?.lua;' .. dir .. '/?/init.lua;' .. package.path"
        guard luaL_loadstring(L, setup) == LUA_OK else { throw ConfigError(message: popError()) }
        lua_pushstring(L, directory)
        if let message = protectedCall(arguments: 1) { throw ConfigError(message: message) }

        guard luaL_loadfilex(L, configURL.path, nil) == LUA_OK else { throw ConfigError(message: popError()) }
        if let message = protectedCall(arguments: 0) { throw ConfigError(message: message) }

        loading = false
        return LoadedConfig(
            settings: settings, binds: binds, rules: rules, workspaceLayouts: workspaceLayouts, workspaceRules: workspaceRules,
            sequences: sequences,
            releaseBinds: releaseBinds, longPressBinds: longPressBinds, noRepeat: noRepeat, bindRecords: bindRecords,
            gestures: gestures)
    }

    func call(ref: Int32) {
        lua_rawgeti(L, registryIndex, lua_Integer(ref))
        if let message = protectedCall(arguments: 0) { bridge.log("function failed: \(message)") }
    }

    func fire(event: String, payload: [String: LuaValue]) {
        for handler in handlers where handler.event == event && handler.filter.allSatisfy({ payload[$0.key] == $0.value }) {
            lua_rawgeti(L, registryIndex, lua_Integer(handler.ref))
            pushValue(L, .table(payload))
            if let message = protectedCall(arguments: 1) {
                bridge.log("handler for event '\(event)' failed: \(message)")
            }
        }
    }

    func functionID(ref: Int32) -> Int { generation << 32 | Int(ref) }

    // MARK: Calls

    /// Calls the function below the arguments. Returns the error message, or `nil` on success.
    private func protectedCall(arguments: Int32) -> String? {
        lua_sethook(L, timeoutHook, maskCount, 10_000)
        lua_pushinteger(L, now() + timeLimit)
        lua_setfield(L, registryIndex, deadlineKey)
        guard lua_pcallk(L, arguments, 0, 0, 0, nil) != LUA_OK else { return nil }
        return popError()
    }

    private func popError() -> String {
        defer { lua_settop(L, -2) }
        if lua_type(L, -1) == LUA_TSTRING { return readString(L, -1) ?? "unknown error" }
        return "error object is a \(String(cString: lua_typename(L, lua_type(L, -1)))) value"
    }

    // MARK: API

    private func installAPI() throws {
        guard luaL_loadstring(L, prelude) == LUA_OK else { throw ConfigError(message: popError()) }
        let functions: [(String, lua_CFunction)] = [
            ("config", nativeConfig), ("bind", nativeBind), ("gesture", nativeGesture), ("reset_mode", nativeResetMode), ("rule", nativeRule), ("workspace", nativeWorkspace),
            ("on", nativeOn), ("dispatch", nativeDispatch), ("query", nativeQuery), ("exec", nativeExec), ("log", nativeLog),
        ]
        lua_createtable(L, 0, Int32(functions.count))
        let owner = Unmanaged.passUnretained(self).toOpaque()
        for (name, function) in functions {
            lua_pushlightuserdata(L, owner)
            lua_pushcclosure(L, function, 1)
            lua_setfield(L, -2, name)
        }
        lua_pushstring(L, LuaHost.apiVersion)
        if let message = protectedCall(arguments: 2) { throw ConfigError(message: message) }
    }

    /// A chord cannot be bound by itself and also start a sequence, and a sequence cannot start a longer one.
    /// The check looks both ways, so the order of the `wm.bind` calls does not matter.
    fileprivate func checkConflicts(mode: String, chords: [Chord]) throws {
        func name(_ chords: [Chord]) -> String { chords.map(\.description).joined(separator: ">") }
        func conflict(_ message: String) -> ConfigError { ConfigError(message: "mode '\(mode)': \(message)") }
        let existing = (sequences[mode] ?? [:]).keys.filter { $0 != chords }

        if chords.count == 1 {
            if let sequence = existing.filter({ $0[0] == chords[0] }).min(by: { name($0) < name($1) }) {
                throw conflict("'\(name(chords))' is bound by itself and is also the first step of the sequence '\(name(sequence))'")
            }
            return
        }
        if binds[mode]?[chords[0]] != nil {
            throw conflict("'\(name([chords[0]]))' is bound by itself and is also the first step of the sequence '\(name(chords))'")
        }
        if let longer = existing.filter({ $0.starts(with: chords) }).min(by: { name($0) < name($1) }) {
            throw conflict("the sequence '\(name(chords))' is the start of the sequence '\(name(longer))'")
        }
        if let shorter = existing.filter({ chords.starts(with: $0) }).min(by: { name($0) < name($1) }) {
            throw conflict("the sequence '\(name(shorter))' is the start of the sequence '\(name(chords))'")
        }
    }

    fileprivate func addHandler(event: String, filter: [String: LuaValue], ref: Int32) {
        handlers.append(Handler(event: event, filter: filter, ref: ref))
    }
}

// MARK: - Native functions
//
// These never call `lua_error`: a longjmp across Swift frames is unsafe. They return `true`, or `nil, message`,
// and the Lua prelude raises the error with the position of the user's call.

private func owner(_ L: OpaquePointer?) -> LuaState {
    Unmanaged<LuaState>.fromOpaque(lua_touserdata(L, registryIndex - 1)!).takeUnretainedValue()
}

private func reply(_ L: OpaquePointer?, loadingOnly name: String? = nil, _ body: (LuaState) throws -> Void) -> Int32 {
    let state = owner(L)
    do {
        if let name, !state.loading { throw ConfigError(message: "\(name) can only be called while the config file loads") }
        try body(state)
        lua_pushboolean(L, 1)
        return 1
    } catch {
        lua_pushnil(L)
        lua_pushstring(L, "\(error)")
        return 2
    }
}

private func nativeConfig(_ L: OpaquePointer?) -> Int32 {
    reply(L, loadingOnly: "wm.config") { state in
        var settings = state.settings
        try applyConfig(readValue(L, 1), to: &settings)
        state.settings = settings
    }
}

private func nativeBind(_ L: OpaquePointer?) -> Int32 {
    reply(L, loadingOnly: "wm.bind") { state in
        guard let mode = readString(L, 1), lua_type(L, 1) == LUA_TSTRING else { throw ConfigError(message: "wm.bind: the mode name must be a string") }
        guard lua_type(L, 2) == LUA_TSTRING, let text = readString(L, 2) else {
            throw ConfigError(message: "mode '\(mode)': a chord must be a string like \"alt-h\"")
        }
        let chords: [Chord]
        do { chords = try parseChordSequence(text) } catch { throw ConfigError(message: "mode '\(mode)': \(error)") }
        var options = BindOptions()
        var trigger = BindTrigger.press
        switch lua_type(L, 4) {
        case LUA_TNIL, LUA_TNONE:
            break
        case LUA_TTABLE:
            let fields = try Fields(readValue(L, 4), owner: "wm.bind", allowed: ["description", "repeating", "release", "long_press", "universal", "hidden"])
            options.description = try fields.string("description")
            options.repeating = try fields.bool("repeating")
            options.universal = try fields.bool("universal") ?? false
            options.hidden = try fields.bool("hidden") ?? false
            let release = try fields.bool("release") ?? false, longPress = try fields.bool("long_press") ?? false
            if release && longPress { throw ConfigError(message: "mode '\(mode)': '\(text)' cannot be both 'release' and 'long_press'") }
            trigger = release ? .release : longPress ? .longPress : .press
            if trigger != .press, chords.count > 1 {
                throw ConfigError(message: "mode '\(mode)': '\(text)' is a key sequence; 'release' and 'long_press' need a single chord")
            }
            if trigger != .press, options.repeating != nil {
                throw ConfigError(message: "mode '\(mode)': 'repeating' applies to binds that run when the key goes down, not to '\(text)'")
            }
        default:
            throw ConfigError(message: "mode '\(mode)': the options for '\(text)' must be a table")
        }
        let target = options.universal ? universalMode : mode
        if trigger == .press { try state.checkConflicts(mode: target, chords: chords) }

        let action: BindAction
        switch lua_type(L, 3) {
        case LUA_TSTRING:
            let command = readString(L, 3) ?? ""
            action = .command(command.trimmingCharacters(in: .whitespaces).isEmpty ? "noop" : command)
        case LUA_TFUNCTION:
            lua_pushvalue(L, 3)
            action = .function(state.functionID(ref: luaL_ref(L, registryIndex)))
        default:
            throw ConfigError(message: "mode '\(mode)': the action for chord '\(text)' must be a command string or a function")
        }
        switch trigger {
        case .press:
            if chords.count == 1 {
                state.binds[target, default: [:]][chords[0]] = action
                if options.repeating == false {
                    state.noRepeat[target, default: []].insert(chords[0])
                } else {
                    state.noRepeat[target]?.remove(chords[0])
                }
            } else {
                state.sequences[target, default: [:]][chords] = action
            }
        case .release:
            state.releaseBinds[target, default: [:]][chords[0]] = action
        case .longPress:
            state.longPressBinds[target, default: [:]][chords[0]] = action
        }
        // The canonical text, so the label can read the chords back: `alt-h`, `ctrl-p>h`.
        let keys = chords.map(\.description).joined(separator: ">")
        let described: String
        switch action {
        case .command(let command): described = command
        case .function: described = "function"
        }
        state.bindRecords.removeAll { $0.mode == target && $0.keys == keys && $0.trigger == trigger }
        state.bindRecords.append(BindRecord(mode: target, keys: keys, trigger: trigger, action: described, options: options))
    }
}

private func nativeGesture(_ L: OpaquePointer?) -> Int32 {
    reply(L, loadingOnly: "wm.gesture") { state in
        let fields = try Fields(readValue(L, 1), owner: "wm.gesture", allowed: ["mods", "direction", "threshold", "description"])
        guard let mods = try fields.string("mods") else { throw ConfigError(message: "wm.gesture: needs 'mods', for example mods = \"alt\"") }
        let modifiers: Modifiers
        do { modifiers = try parseModifiers(mods) } catch { throw ConfigError(message: "wm.gesture: 'mods' \(error)") }
        guard let name = try fields.choice("direction", GestureDirection.allCases.map(\.rawValue)), let direction = GestureDirection(rawValue: name) else {
            throw ConfigError(message: "wm.gesture: needs a 'direction' (left, right, up or down)")
        }
        let threshold = try fields.number("threshold", min: 10, max: 2000) ?? 100
        let action: BindAction
        switch lua_type(L, 2) {
        case LUA_TSTRING:
            let command = readString(L, 2) ?? ""
            guard !command.trimmingCharacters(in: .whitespaces).isEmpty else { throw ConfigError(message: "wm.gesture: 'command' must not be empty") }
            action = .command(command)
        case LUA_TFUNCTION:
            lua_pushvalue(L, 2)
            action = .function(state.functionID(ref: luaL_ref(L, registryIndex)))
        default:
            throw ConfigError(message: "wm.gesture: needs a 'command', a command string or a function")
        }
        let description = try fields.string("description")
        state.gestures.removeAll { $0.modifiers == modifiers && $0.direction == direction }
        state.gestures.append(Gesture(modifiers: modifiers, direction: direction, action: action, threshold: threshold, description: description))
        // `wm list binds` shows it next to the keys.
        var keys: [String] = []
        if modifiers.contains(.control) { keys.append("ctrl") }
        if modifiers.contains(.option) { keys.append("alt") }
        if modifiers.contains(.shift) { keys.append("shift") }
        if modifiers.contains(.command) { keys.append("cmd") }
        keys.append("scroll")
        let shown = keys.joined(separator: "-") + " " + direction.rawValue
        let text: String
        switch action {
        case .command(let command): text = command
        case .function: text = "function"
        }
        state.bindRecords.removeAll { $0.mode == "gesture" && $0.keys == shown }
        state.bindRecords.append(BindRecord(mode: "gesture", keys: shown, trigger: .press, action: text, options: BindOptions(description: description)))
    }
}

private func nativeResetMode(_ L: OpaquePointer?) -> Int32 {
    reply(L, loadingOnly: "wm.mode") { state in
        let mode = readString(L, 1) ?? ""
        if mode == universalMode { throw ConfigError(message: "wm.mode: '*' is reserved for binds with universal = true") }
        state.binds[mode] = [:]
        state.sequences[mode] = nil
        state.releaseBinds[mode] = nil
        state.longPressBinds[mode] = nil
        state.noRepeat[mode] = nil
        state.bindRecords.removeAll { $0.mode == mode }
    }
}

private func nativeRule(_ L: OpaquePointer?) -> Int32 {
    reply(L, loadingOnly: "wm.rule") { state in
        state.rules.append(try parseRule(readValue(L, 1)))
    }
}

private func nativeWorkspace(_ L: OpaquePointer?) -> Int32 {
    reply(L, loadingOnly: "wm.workspace") { state in
        let name = readString(L, 1) ?? ""
        let rule = try parseWorkspaceRule(name: name, readValue(L, 2))
        state.workspaceRules[name] = rule
        state.workspaceLayouts[name] = rule.layout
    }
}

private func nativeOn(_ L: OpaquePointer?) -> Int32 {
    reply(L) { state in
        var filter: [String: LuaValue] = [:]
        switch try readValue(L, 2) {
        case .nil: break
        case .table(let table):
            for (key, value) in table {
                switch value {
                case .string, .number, .bool: break
                default: throw ConfigError(message: "wm.on: filter '\(key)' must be a string, number or boolean")
                }
            }
            filter = table
        default:
            throw ConfigError(message: "wm.on: the filter must be a table of key = value")
        }
        lua_pushvalue(L, 3)
        state.addHandler(event: readString(L, 1) ?? "", filter: filter, ref: luaL_ref(L, registryIndex))
    }
}

private func nativeDispatch(_ L: OpaquePointer?) -> Int32 {
    let window = lua_type(L, 2) == LUA_TNUMBER ? UInt32(exactly: lua_tointegerx(L, 2, nil)) : nil
    let result = owner(L).bridge.dispatch(readString(L, 1) ?? "", window: window)
    if result.exitCode == 0 {
        lua_pushstring(L, result.stdout)
        return 1
    }
    lua_pushnil(L)
    lua_pushstring(L, result.stderr.isEmpty ? "command failed with exit code \(result.exitCode)" : result.stderr)
    return 2
}

private func nativeQuery(_ L: OpaquePointer?) -> Int32 {
    pushValue(L, owner(L).bridge.query(readString(L, 1) ?? ""))
    return 1
}

private func nativeExec(_ L: OpaquePointer?) -> Int32 {
    owner(L).bridge.exec(readString(L, 1) ?? "")
    return 0
}

private func nativeLog(_ L: OpaquePointer?) -> Int32 {
    owner(L).bridge.log(readString(L, 1) ?? "")
    return 0
}

// MARK: - Value conversion

private func readString(_ L: OpaquePointer?, _ index: Int32) -> String? {
    var length = 0
    guard let bytes = lua_tolstring(L, index, &length) else { return nil }
    return String(decoding: UnsafeRawBufferPointer(start: bytes, count: length), as: UTF8.self)
}

/// Converts the Lua value at `index` for settings and rules. A table with keys 1...n becomes an array.
/// Leaves extra values on the stack when it throws: call it only inside a native function.
private func readValue(_ L: OpaquePointer?, _ index: Int32, depth: Int = 0) throws -> LuaValue {
    let index = lua_absindex(L, index)
    switch lua_type(L, index) {
    case LUA_TNIL, LUA_TNONE:
        return .nil
    case LUA_TBOOLEAN:
        return .bool(lua_toboolean(L, index) != 0)
    case LUA_TNUMBER:
        return .number(lua_tonumberx(L, index, nil))
    case LUA_TSTRING:
        return .string(readString(L, index) ?? "")
    case LUA_TTABLE:
        guard depth < 16, lua_checkstack(L, 4) != 0 else { throw ConfigError(message: "table is nested too deeply") }
        var integerKeys: [Int: LuaValue] = [:]
        var named: [String: LuaValue] = [:]
        lua_pushnil(L)
        while lua_next(L, index) != 0 {
            let value = try readValue(L, -1, depth: depth + 1)
            switch lua_type(L, -2) {
            case LUA_TSTRING:
                named[readString(L, -2) ?? ""] = value
            case LUA_TNUMBER where lua_isinteger(L, -2) != 0:
                integerKeys[Int(lua_tointegerx(L, -2, nil))] = value
            default:
                throw ConfigError(message: "table keys must be strings or whole numbers")
            }
            lua_settop(L, -2)
        }
        guard named.isEmpty, !integerKeys.isEmpty, integerKeys.keys.min()! == 1, integerKeys.keys.max()! == integerKeys.count else {
            return .table(named.merging(integerKeys.map { (String($0.key), $0.value) }) { first, _ in first })
        }
        return .array((1...integerKeys.count).map { integerKeys[$0]! })
    default:
        let name = String(cString: lua_typename(L, lua_type(L, index)))
        throw ConfigError(message: "a \(name) value is not allowed here")
    }
}

private func pushValue(_ L: OpaquePointer?, _ value: LuaValue) {
    guard lua_checkstack(L, 4) != 0 else {
        lua_pushnil(L)
        return
    }
    switch value {
    case .nil:
        lua_pushnil(L)
    case .bool(let flag):
        lua_pushboolean(L, flag ? 1 : 0)
    case .number(let number):
        // Whole numbers become Lua integers so that `tostring(7)` is "7", not "7.0".
        if number == number.rounded(), abs(number) < 9e15 {
            lua_pushinteger(L, lua_Integer(number))
        } else {
            lua_pushnumber(L, number)
        }
    case .string(let text):
        lua_pushstring(L, text)
    case .array(let items):
        lua_createtable(L, Int32(items.count), 0)
        for (offset, item) in items.enumerated() {
            pushValue(L, item)
            lua_rawseti(L, -2, lua_Integer(offset + 1))
        }
    case .table(let table):
        lua_createtable(L, 0, Int32(table.count))
        for (key, item) in table {
            pushValue(L, item)
            lua_setfield(L, -2, key)
        }
    }
}

// MARK: - Time limit

private func now() -> Int64 { Int64(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) }

private func deadlinePassed(_ L: OpaquePointer?) -> Bool {
    lua_getfield(L, registryIndex, deadlineKey)
    let deadline = lua_tointegerx(L, -1, nil)
    lua_settop(L, -2)
    return now() > deadline
}

/// Count hook. After the deadline it fires on every instruction, so a script cannot catch the error
/// with `pcall` and keep looping. It holds no Swift objects because `lua_error` jumps out with longjmp.
private func timeoutHook(_ L: OpaquePointer?, _ debug: UnsafeMutablePointer<lua_Debug>?) {
    guard deadlinePassed(L) else { return }
    lua_sethook(L, timeoutHook, maskCount, 1)
    lua_pushstring(L, "script ran longer than 2 seconds and was aborted")
    _ = lua_error(L)
}
