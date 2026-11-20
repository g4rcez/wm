import CLua
import Core
import Foundation

// The C macros are not imported into Swift.
private let registryIndex: Int32 = -1_001_000 // LUA_REGISTRYINDEX
private let maskCount: Int32 = 1 << 3 // LUA_MASKCOUNT
private let timeLimit: Int64 = 2_000_000_000
private let deadlineKey = "wm.deadline"

private let prelude = """
local native, version, templates = ...
local wm = { version = version, templates = templates }
-- True once the config file has run (`wm.floating._install` sets it): `wm.profile` is for the config only.
local configLoaded = false

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

-- Binds the [[shortcut]] entries of shortcuts.toml (next to this file; the Shortcuts window writes it). A `wm.bind` made
-- after this call for the same keys replaces the shortcut, so call it first to let the config win, or last to let the file win.
function wm.shortcuts()
  local list, err = native.shortcuts()
  if not list then error(err, 2) end
  for _, shortcut in ipairs(list) do
    done(native.bind(shortcut.mode, shortcut.keys, shortcut.action, shortcut.options, "shortcuts"))
  end
end

-- Types `target` when `chord` is pressed: the key goes down, repeats and comes up with it.
function wm.remap(chord, target, options)
  expect(type(chord) == "string", "wm.remap expects a chord string like 'hyper-k'")
  expect(type(target) == "string", "wm.remap expects the key to type, like 'left' or 'cmd-right'")
  expect(options == nil or type(options) == "table", "wm.remap: the options must be a table like { description = '...' }")
  done(native.bind("main", chord, { remap = target }, options))
end

function wm.press(chord)
  expect(type(chord) == "string", "wm.press expects a key like 'play' or 'cmd-shift-4'")
  return native.dispatch("key press " .. chord, nil)
end

function wm.mode(name, binds, options)
  expect(type(name) == "string" and name ~= "", "wm.mode expects a mode name")
  expect(type(binds) == "table", "wm.mode expects a table of chord = action")
  expect(options == nil or type(options) == "table", "wm.mode: the options must be a table like { once = true }")
  done(native.reset_mode(name, options or {}))
  for chord, action in pairs(binds) do
    -- A table is an action with options: { "focus left", description = "...", repeating = false },
    -- or a remap: { remap = "left", description = "..." }.
    if type(action) == "table" then
      local options = {}
      for key, value in pairs(action) do
        if key ~= 1 and key ~= "remap" then options[key] = value end
      end
      if action.remap ~= nil then
        done(native.bind(name, chord, { remap = action.remap }, options))
      else
        done(native.bind(name, chord, action[1], options))
      end
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

function wm.exec(command, options)
  expect(type(command) == "string", "wm.exec expects a command string")
  expect(options == nil or type(options) == "table", "wm.exec expects a table as its 2nd argument")
  done(native.exec(command, options))
end

function wm.log(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  native.log(table.concat(parts, " "))
end

-- Windows that start floating and centered without a rule of your own: popups and picture-in-picture windows of browsers,
-- Finder, Preview and small utilities. `wm.floating.defaultRules` is the list, in the shape of `wm.rule`, and every rule has a
-- `name`. The rules are added after the config has run, so a `wm.rule` of yours for the same window wins. Turn one off with
-- `wm.floating.disable("finder")`, all of them with `wm.floating.enabled = false`, or change the list itself.
wm.floating = {
  enabled = true,
  disabled = {},
  defaultRules = {
    -- A browser window has the name of the browser at the end of its title; a picture-in-picture window (Google Meet), the popup
    -- of an extension (Bitwarden) and an about:blank popup do not. An empty title is a dialog, and it floats already.
    { name = "helium-popups", app = "net.imput.helium", title = "^(?!.* - Helium).+", float = true, center = true },
    { name = "chrome-popups", app = "com.google.Chrome", title = "^(?!.* - Google Chrome).+", float = true, center = true },
    { name = "brave-popups", app = "com.brave.Browser", title = "^(?!.*Brave).+", float = true, center = true },
    { name = "chromium-popups", app = "org.chromium.Chromium", title = "^(?!.* - Chromium).+", float = true, center = true },
    -- Edge puts a zero-width space inside "Microsoft Edge" and Firefox uses a long dash ("... — Mozilla Firefox"), so these two only
    -- look for the name of the browser anywhere in the title. Firefox also names its picture-in-picture window "Picture-in-Picture".
    { name = "edge-popups", app = "com.microsoft.edgemac", title = "^(?!.*Edge).+", float = true, center = true },
    { name = "firefox-popups", app = "org.mozilla.firefox", title = "^(?!.*Firefox).+", float = true, center = true },
    { name = "finder", app = "com.apple.finder", float = true, center = true },
    { name = "preview", app = "com.apple.Preview", float = true, center = true },
    { name = "calculator", app = "com.apple.calculator", float = true, center = true },
    { name = "activity-monitor", app = "com.apple.ActivityMonitor", float = true, center = true },
    { name = "archive-utility", app = "com.apple.archiveutility", float = true, center = true },
    { name = "quicktime-player", app = "com.apple.QuickTimePlayerX", float = true, center = true },
    { name = "system-settings", app = "com.apple.systempreferences", float = true, center = true },
    { name = "raycast-settings", app = "com.raycast.macos", float = true, center = true },
  },
}

-- Turns default rules off by name: `wm.floating.disable("finder", "preview")` or `wm.floating.disable { "finder", "preview" }`.
function wm.floating.disable(...)
  local names = ...
  if type(names) ~= "table" then names = { ... } end
  for _, name in ipairs(names) do
    expect(type(name) == "string", "wm.floating.disable expects the names of default rules, like 'finder'")
    wm.floating.disabled[name] = true
  end
end

-- Runs when the config file has run (the app calls it): adds the default rules that are still on.
function wm.floating._install()
  configLoaded = true
  if not wm.floating.enabled then return end
  local known = {}
  for _, rule in ipairs(wm.floating.defaultRules) do
    if type(rule) == "table" and rule.name ~= nil then known[rule.name] = true end
  end
  local unknown = {}
  for name in pairs(wm.floating.disabled) do
    if not known[name] then unknown[#unknown + 1] = name end
  end
  table.sort(unknown)
  if #unknown > 0 then
    error("wm.floating.disable: there is no default rule named '" .. unknown[1] .. "' (see wm.floating.defaultRules)", 0)
  end
  for _, rule in ipairs(wm.floating.defaultRules) do
    if not (type(rule) == "table" and rule.name ~= nil and wm.floating.disabled[rule.name]) then wm.rule(rule) end
  end
end

-- Display profiles: `wm.profile(name, { monitors = { "DELL", "main" }, apply = function(monitors) ... end })`. A profile fits when the
-- number of connected monitors equals the number of selectors and every selector names a different monitor (a role, a number from
-- the left or part of the name, as in `wm.rule`). The first profile that fits, in the order of the calls, runs `apply` when the
-- displays change and when the config loads. It does not run again while it is the one that fits.
local profiles, appliedProfile = {}, nil

local function monitorMatches(selector, monitor)
  local text = tostring(selector):lower()
  if text == "main" or text == "secondary" or text == "tertiary" then return monitor.role == text end
  if text:match("^%d+$") then return tonumber(text) == monitor.index end
  return tostring(monitor.name):lower():find(text, 1, true) ~= nil
end

local function profileFits(profile, monitors)
  if #monitors ~= #profile.monitors then return false end
  local used = {}
  local function assign(i)
    if i > #profile.monitors then return true end
    for position, monitor in ipairs(monitors) do
      if not used[position] and monitorMatches(profile.monitors[i], monitor) then
        used[position] = true
        if assign(i + 1) then return true end
        used[position] = false
      end
    end
    return false
  end
  return assign(1)
end

local function applyProfile()
  local monitors = native.query("monitors")
  if type(monitors) ~= "table" then return end
  for _, profile in ipairs(profiles) do
    if profileFits(profile, monitors) then
      if profile.name ~= appliedProfile then
        appliedProfile = profile.name
        profile.apply(monitors)
      end
      return
    end
  end
  appliedProfile = nil
end

function wm.profile(name, spec)
  expect(not configLoaded, "wm.profile can only be called while the config file loads")
  expect(type(name) == "string" and name ~= "", "wm.profile expects a profile name")
  expect(type(spec) == "table", "wm.profile expects a table like { monitors = { 'main' }, apply = function(monitors) end }")
  expect(type(spec.monitors) == "table" and #spec.monitors > 0, "wm.profile '" .. name .. "': 'monitors' must be a list of selectors")
  for _, selector in ipairs(spec.monitors) do
    expect(type(selector) == "string" or type(selector) == "number",
      "wm.profile '" .. name .. "': a monitor selector is a role, a number or part of a name")
  end
  expect(type(spec.apply) == "function", "wm.profile '" .. name .. "': 'apply' must be a function")
  for _, profile in ipairs(profiles) do
    expect(profile.name ~= name, "wm.profile '" .. name .. "' is already defined")
  end
  profiles[#profiles + 1] = { name = name, monitors = spec.monitors, apply = spec.apply }
  if #profiles == 1 then
    wm.on("displays_changed", applyProfile)
    wm.on("config_reloaded", applyProfile)
  end
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
    fileprivate var holdBinds: [String: [Chord: BindAction]] = [:]
    /// Chords whose entry in `binds` is the action of a `repeating = true` bind, made because no plain bind exists. A plain
    /// bind, in any order, takes its place.
    fileprivate var pressFromHold: [String: Set<Chord>] = [:]
    fileprivate var noRepeat: [String: Set<Chord>] = [:]
    fileprivate var bindRecords: [BindRecord] = []
    fileprivate var overrides: [BindOverride] = []
    fileprivate var shortcutsImported = false
    /// The config file that runs: `wm.shortcuts()` reads the `shortcuts.toml` next to it.
    fileprivate var configURL: URL?
    fileprivate var gestures: [Gesture] = []
    fileprivate var modeOptions: [String: ModeOptions] = [:]
    fileprivate var longPressTimeouts: [String: [Chord: Double]] = [:]
    fileprivate var rules: [WindowRule] = []
    fileprivate var workspaceLayouts: [String: LayoutKind] = [:]
    fileprivate var workspaceRules: [String: WorkspaceRule] = [:]
    private var handlers: [Handler] = []
    /// The `seconds` of the handlers of the `idle` event.
    fileprivate var idleThresholds: [Double] = []
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
        self.configURL = configURL
        let directory = configURL.deletingLastPathComponent().path
        let setup = "local dir = ...; package.path = dir .. '/?.lua;' .. dir .. '/?/init.lua;' .. package.path"
        guard luaL_loadstring(L, setup) == LUA_OK else { throw ConfigError(message: popError()) }
        lua_pushstring(L, directory)
        if let message = protectedCall(arguments: 1) { throw ConfigError(message: message) }

        guard luaL_loadfilex(L, configURL.path, nil) == LUA_OK else { throw ConfigError(message: popError()) }
        if let message = protectedCall(arguments: 0) { throw ConfigError(message: message) }
        // The default floating rules go after the rules of the config, so that a rule of the user wins.
        guard luaL_loadstring(L, "wm.floating._install()") == LUA_OK else { throw ConfigError(message: popError()) }
        if let message = protectedCall(arguments: 0) { throw ConfigError(message: message) }

        try readCommands()

        loading = false
        return LoadedConfig(
            settings: settings, binds: binds, rules: rules, workspaceLayouts: workspaceLayouts, workspaceRules: workspaceRules,
            sequences: sequences,
            releaseBinds: releaseBinds, longPressBinds: longPressBinds, holdBinds: holdBinds, noRepeat: noRepeat, bindRecords: bindRecords,
            gestures: gestures, modeOptions: modeOptions, longPressTimeouts: longPressTimeouts,
            overrides: overrides, shortcutsImported: shortcutsImported, idleThresholds: idleThresholds.sorted())
    }

    /// `wm.commands = { ... }` is the same as `wm.config { commands = { ... } }`; it is read after the config file has run.
    private func readCommands() throws {
        lua_getglobal(L, "wm")
        defer { lua_settop(L, -2) }
        lua_getfield(L, -1, "commands")
        defer { lua_settop(L, -2) }
        guard lua_type(L, -1) != LUA_TNIL else { return }
        var settings = settings
        try applyConfig(.table(["commands": readValue(L, -1)]), to: &settings)
        self.settings = settings
    }

    func call(ref: Int32) {
        lua_rawgeti(L, registryIndex, lua_Integer(ref))
        if let message = protectedCall(arguments: 0) { bridge.logError("function failed: \(message)") }
    }

    func fire(event: String, payload: [String: LuaValue]) {
        for handler in handlers where handler.event == event && handler.filter.allSatisfy({ payload[$0.key] == $0.value }) {
            lua_rawgeti(L, registryIndex, lua_Integer(handler.ref))
            pushValue(L, .table(payload))
            if let message = protectedCall(arguments: 1) {
                bridge.logError("handler for event '\(event)' failed: \(message)")
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
            ("config", nativeConfig), ("bind", nativeBind), ("shortcuts", nativeShortcuts), ("gesture", nativeGesture), ("reset_mode", nativeResetMode), ("rule", nativeRule), ("workspace", nativeWorkspace),
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
        pushValue(L, builtInTemplates)
        if let message = protectedCall(arguments: 3) { throw ConfigError(message: message) }
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

/// `wm.templates`: the built-in tile templates by their Lua name, in the shape that `templates` in `wm.config` takes.
private let builtInTemplates: LuaValue = {
    let templates: [(String, SplitTemplate)] = [
        ("two", .two), ("three", .three), ("four", .four), ("five", .five), ("six", .six),
        ("stack_left", .stackLeft), ("stack_right", .stackRight),
        ("two_thirds", .twoThirds), ("three_quarters", .threeQuarters), ("one_quarter", .oneQuarter),
        ("two_rows", .twoRows), ("two_thirds_tall", .twoThirdsTall), ("three_rows", .threeRows),
        ("one_over_two", .oneOverTwo), ("two_over_one", .twoOverOne), ("sidebars", .sidebars),
        ("corner_top_left", .cornerTopLeft), ("corner_bottom_left", .cornerBottomLeft),
        ("centered", .centered),
    ]
    return .table(Dictionary(uniqueKeysWithValues: templates.map { id, template in
        var fields: [String: LuaValue] = [
            "name": .string(template.name), "title": .string(template.title),
            "cells": .array(template.cells.map { .array([.number($0.minX), .number($0.minY), .number($0.width), .number($0.height)]) }),
        ]
        if let key = template.key { fields["key"] = .string(key) }
        if template.area != SplitTemplate.unit {
            let area = template.area
            fields["area"] = .array([.number(area.minX), .number(area.minY), .number(area.width), .number(area.height)])
        }
        return (id, .table(fields))
    }))
}()

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

/// The Lua function at stack `index` as a bind action. It stays in the registry, so it can be called later.
private func functionAction(_ L: OpaquePointer?, at index: Int32, _ state: LuaState) -> BindAction {
    lua_pushvalue(L, index)
    return .function(state.functionID(ref: luaL_ref(L, registryIndex)))
}

extension Gesture {
    /// The line that `wm list binds` shows for the swipe.
    public var bindRecord: BindRecord {
        BindRecord(mode: "gesture", keys: label, trigger: .press, action: action.recordText, options: BindOptions(description: description))
    }
}

private extension BindAction {
    /// What `wm list binds` shows: the command, or `function`.
    var recordText: String {
        switch self {
        case .command(let command): command
        case .function: "function"
        case .remap(let target): "remap \(target)"
        }
    }
}

/// The shortcuts of the `shortcuts.toml` next to the config file, as a Lua array, or `nil, message`.
private func nativeShortcuts(_ L: OpaquePointer?) -> Int32 {
    let state = owner(L)
    do {
        guard state.loading, let configURL = state.configURL else {
            throw ConfigError(message: "wm.shortcuts can only be called while the config file loads")
        }
        let list = try readShortcuts(at: shortcutsURL(for: configURL))
        state.shortcutsImported = true
        pushValue(L, .array(list.map(\.luaValue)))
        return 1
    } catch {
        lua_pushnil(L)
        lua_pushstring(L, "\(error)")
        return 2
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
        var longPressTimeout: Double?
        switch lua_type(L, 4) {
        case LUA_TNIL, LUA_TNONE:
            break
        case LUA_TTABLE:
            let fields = try Fields(readValue(L, 4), owner: "wm.bind", allowed: ["description", "repeating", "release", "long_press", "universal", "submap_universal", "hidden"])
            options.description = try fields.string("description")
            options.repeating = try fields.bool("repeating")
            // `submap_universal` is the name that Hyprland uses.
            options.universal = try fields.bool("universal") ?? fields.bool("submap_universal") ?? false
            options.hidden = try fields.bool("hidden") ?? false
            let release = try fields.bool("release") ?? false
            // `long_press = 0.8` is a long press that waits 0.8 seconds, whatever `binds.long_press_timeout` says.
            var longPress = false
            switch fields.values["long_press"] {
            case nil: break
            case .bool(let flag)?: longPress = flag
            case .number(let seconds)?:
                guard (0.1...3).contains(seconds) else {
                    throw ConfigError(message: "mode '\(mode)': 'long_press' for '\(text)' must be between 0.1 and 3 seconds")
                }
                longPress = true
                longPressTimeout = seconds
            default:
                throw ConfigError(message: "mode '\(mode)': 'long_press' for '\(text)' must be true, false or a number of seconds")
            }
            if release && longPress { throw ConfigError(message: "mode '\(mode)': '\(text)' cannot be both 'release' and 'long_press'") }
            trigger = release ? .release : longPress ? .longPress : .press
            if trigger != .press, chords.count > 1 {
                throw ConfigError(message: "mode '\(mode)': '\(text)' is a key sequence; 'release' and 'long_press' need a single chord")
            }
            if trigger != .press, options.repeating != nil {
                throw ConfigError(message: "mode '\(mode)': 'repeating' applies to binds that run when the key goes down, not to '\(text)'")
            }
            // `repeating = true` on a single chord is a hold bind: it runs for each repeat of the held key. On a sequence it
            // stays as it always was (the option has no effect there).
            if trigger == .press, options.repeating == true, chords.count == 1 { trigger = .hold }
        default:
            throw ConfigError(message: "mode '\(mode)': the options for '\(text)' must be a table")
        }
        let target = options.universal ? universalMode : mode
        // `wm.shortcuts()` passes "shortcuts" as the fifth argument: the bind comes from `shortcuts.toml`.
        let source: BindSource = lua_type(L, 5) == LUA_TSTRING && readString(L, 5) == "shortcuts" ? .shortcuts : .lua
        if trigger == .press || trigger == .hold {
            do { try state.checkConflicts(mode: target, chords: chords) } catch let error as ConfigError {
                // A conflict always shares the first chord. Say when the other bind may be in the TOML file.
                let first = chords[0].description
                let fromFile = source == .shortcuts || state.bindRecords.contains {
                    $0.mode == target && $0.source == .shortcuts && $0.keys.split(separator: ">").first.map(String.init) == first
                }
                throw fromFile ? ConfigError(message: "\(error.message) (one of the binds is in \(shortcutsFileName))") : error
            }
        }

        let action: BindAction
        switch lua_type(L, 3) {
        case LUA_TSTRING:
            let command = readString(L, 3) ?? ""
            action = .command(command.trimmingCharacters(in: .whitespaces).isEmpty ? "noop" : command)
        case LUA_TFUNCTION:
            action = functionAction(L, at: 3, state)
        case LUA_TTABLE:
            let fields = try Fields(readValue(L, 3), owner: "wm.remap", allowed: ["remap"])
            guard let keyText = try fields.string("remap") else { throw ConfigError(message: "mode '\(mode)': the action for chord '\(text)' needs a 'remap' key") }
            guard chords.count == 1, trigger == .press, options.repeating != true else {
                throw ConfigError(message: "mode '\(mode)': '\(text)' is a remap; it needs a single chord that runs when the key goes down")
            }
            let target: Chord
            do { target = try parseChord(keyText, allowMedia: true) } catch { throw ConfigError(message: "mode '\(mode)': remap of '\(text)': \(error)") }
            guard !target.modifiers.contains(.hyper) else {
                throw ConfigError(message: "mode '\(mode)': remap of '\(text)': 'hyper' is not a key that wm can type")
            }
            action = .remap(target)
        default:
            throw ConfigError(message: "mode '\(mode)': the action for chord '\(text)' must be a command string or a function")
        }
        switch trigger {
        case .press:
            if chords.count == 1 {
                state.binds[target, default: [:]][chords[0]] = action
                state.pressFromHold[target]?.remove(chords[0])
                if options.repeating == false {
                    state.noRepeat[target, default: []].insert(chords[0])
                } else {
                    state.noRepeat[target]?.remove(chords[0])
                }
            } else {
                state.sequences[target, default: [:]][chords] = action
            }
        case .hold:
            state.holdBinds[target, default: [:]][chords[0]] = action
            // Without a plain bind, the same action runs when the key goes down.
            if state.binds[target]?[chords[0]] == nil || state.pressFromHold[target]?.contains(chords[0]) == true {
                state.binds[target, default: [:]][chords[0]] = action
                state.pressFromHold[target, default: []].insert(chords[0])
            }
        case .release:
            state.releaseBinds[target, default: [:]][chords[0]] = action
        case .longPress:
            state.longPressBinds[target, default: [:]][chords[0]] = action
            state.longPressTimeouts[target, default: [:]][chords[0]] = longPressTimeout
        }
        // The canonical text, so the label can read the chords back: `alt-h`, `ctrl-p>h`.
        let keys = chords.map(\.description).joined(separator: ">")
        if let previous = state.bindRecords.first(where: { $0.mode == target && $0.keys == keys && $0.trigger == trigger }), previous.source != source {
            state.overrides.append(BindOverride(mode: target, keys: keys, trigger: trigger, kept: source, replacedAction: previous.action))
        }
        state.bindRecords.removeAll { $0.mode == target && $0.keys == keys && $0.trigger == trigger }
        state.bindRecords.append(BindRecord(mode: target, keys: keys, trigger: trigger, action: action.recordText, options: options, source: source))
    }
}

private func nativeGesture(_ L: OpaquePointer?) -> Int32 {
    reply(L, loadingOnly: "wm.gesture") { state in
        let fields = try Fields(readValue(L, 1), owner: "wm.gesture", allowed: ["mods", "fingers", "zone", "direction", "threshold", "description"])
        let fingers = try fields.integer("fingers", min: 3)
        if let fingers, fingers > 4 { throw ConfigError(message: "wm.gesture: 'fingers' must be 3 or 4") }
        let mods = try fields.string("mods")
        let zone = try fields.choice("zone", GestureZone.allCases.map(\.rawValue)).flatMap(GestureZone.init(rawValue:)) ?? .anywhere
        if zone == .titleBar {
            guard mods == nil, fingers == nil else { throw ConfigError(message: "wm.gesture: a gesture with zone = \"title_bar\" takes no 'mods' and no 'fingers'") }
        } else {
            guard mods != nil || fingers != nil else {
                throw ConfigError(message: "wm.gesture: needs 'mods', for example mods = \"alt\", or 'fingers' (3 or 4)")
            }
        }
        var modifiers: Modifiers = []
        if let mods {
            do { modifiers = try parseModifiers(mods) } catch { throw ConfigError(message: "wm.gesture: 'mods' \(error)") }
        }
        guard let name = try fields.choice("direction", GestureDirection.allCases.map(\.rawValue)), let direction = GestureDirection(rawValue: name) else {
            throw ConfigError(message: "wm.gesture: needs a 'direction' (left, right, up or down; pinch-in or pinch-out with zone = \"title_bar\")")
        }
        if direction.isPinch, zone != .titleBar { throw ConfigError(message: "wm.gesture: 'direction' \(direction.rawValue) needs zone = \"title_bar\"") }
        let threshold = try fields.number("threshold", min: 10, max: 2000) ?? 100
        let action: BindAction
        switch lua_type(L, 2) {
        case LUA_TSTRING:
            let command = readString(L, 2) ?? ""
            guard !command.trimmingCharacters(in: .whitespaces).isEmpty else { throw ConfigError(message: "wm.gesture: 'command' must not be empty") }
            action = .command(command)
        case LUA_TFUNCTION:
            action = functionAction(L, at: 2, state)
        default:
            throw ConfigError(message: "wm.gesture: needs a 'command', a command string or a function")
        }
        let description = try fields.string("description")
        state.gestures.removeAll { $0.modifiers == modifiers && $0.fingers == fingers && $0.zone == zone && $0.direction == direction }
        let gesture = Gesture(modifiers: modifiers, fingers: fingers, zone: zone, direction: direction, action: action, threshold: threshold, description: description)
        state.gestures.append(gesture)
        // `wm list binds` shows it next to the keys.
        state.bindRecords.removeAll { $0.mode == "gesture" && $0.keys == gesture.label }
        state.bindRecords.append(gesture.bindRecord)
    }
}

private func nativeResetMode(_ L: OpaquePointer?) -> Int32 {
    reply(L, loadingOnly: "wm.mode") { state in
        let mode = readString(L, 1) ?? ""
        if mode == universalMode { throw ConfigError(message: "wm.mode: '*' is reserved for binds with universal = true") }
        if mode == "back" { throw ConfigError(message: "wm.mode: 'back' is reserved: `mode back` goes to the mode before") }
        let fields = try Fields(readValue(L, 2), owner: "wm.mode", allowed: ["once", "swallow"])
        let options = ModeOptions(once: try fields.bool("once") ?? false, swallow: try fields.bool("swallow") ?? false)
        state.modeOptions[mode] = options == ModeOptions() ? nil : options
        state.longPressTimeouts[mode] = nil
        state.binds[mode] = [:]
        state.sequences[mode] = nil
        state.releaseBinds[mode] = nil
        state.longPressBinds[mode] = nil
        state.holdBinds[mode] = nil
        state.pressFromHold[mode] = nil
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
        let event = readString(L, 1) ?? ""
        if event == "idle" {
            // The idle time is read by wm, so it needs to know the thresholds before the config runs its handlers.
            guard filter.count == 1, case .number(let seconds)? = filter["seconds"], seconds.isFinite, (1...604_800).contains(seconds) else {
                throw ConfigError(message: "wm.on: 'idle' needs a filter { seconds = N } with N from 1 to 604800")
            }
            if !state.idleThresholds.contains(seconds) { state.idleThresholds.append(seconds) }
        }
        lua_pushvalue(L, 3)
        state.addHandler(event: event, filter: filter, ref: luaL_ref(L, registryIndex))
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
    reply(L) { state in
        let command = readString(L, 1) ?? ""
        if let options = try parseExecOptions(readValue(L, 2)) {
            state.bridge.exec(command, options: options)
        } else {
            state.bridge.exec(command)
        }
    }
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
