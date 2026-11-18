import Foundation
import Testing
@testable import Scripting

/// `wm.shortcuts()` in a real config: the binds of `shortcuts.toml` and who wins when `init.lua` binds the same keys.
@Suite("wm.shortcuts", .serialized)
struct ShortcutsLoadTests {
    let host = LuaHost(bridge: FakeBridge())
    let dir: ConfigDir

    init() throws { dir = try ConfigDir() }

    private func load(_ init_lua: String, toml: String? = nil) throws -> LoadedConfig {
        if let toml { try dir.write("shortcuts.toml", toml) }
        return try host.load(configURL: dir.write("init.lua", init_lua))
    }

    private let file = """
        [[shortcut]]
        keys = "alt-h"
        action = "focus left"
        description = "Focus left"

        [[shortcut]]
        keys = "hyper-k"
        remap = "up"

        [[shortcut]]
        keys = "alt-r"
        mode = "resize"
        action = "mode main"
        long_press = 0.8
        """

    @Test func bindsTheShortcutsOfTheFile() throws {
        let config = try load("wm.shortcuts()", toml: file)

        #expect(config.shortcutsImported)
        #expect(config.binds["main"]?[try parseChord("alt-h")] == .command("focus left"))
        #expect(config.binds["main"]?[try parseChord("hyper-k")] == .remap(try parseChord("up")))
        #expect(config.longPressBinds["resize"]?[try parseChord("alt-r")] == .command("mode main"))
        #expect(config.longPressTimeouts["resize"]?[try parseChord("alt-r")] == 0.8)
        #expect(config.bindRecords.first { $0.keys == "alt-h" }?.source == .shortcuts)
        #expect(config.bindRecords.first { $0.keys == "alt-h" }?.options.description == "Focus left")
        #expect(config.overrides.isEmpty)
    }

    @Test func aMissingFileIsNoBinds() throws {
        let config = try load("wm.shortcuts()")

        #expect(config.shortcutsImported)
        #expect(config.bindRecords.isEmpty)
    }

    @Test func aConfigThatDoesNotCallItIsNotImported() throws {
        let config = try load("wm.bind('alt-x', 'noop')", toml: file)

        #expect(!config.shortcutsImported)
        #expect(config.binds["main"]?[try parseChord("alt-h")] == nil)
    }

    @Test func aBindOfInitLuaAfterTheCallWins() throws {
        let config = try load("wm.shortcuts()\nwm.bind('alt-h', 'focus right')", toml: file)

        #expect(config.binds["main"]?[try parseChord("alt-h")] == .command("focus right"))
        #expect(config.overrides == [BindOverride(mode: "main", keys: "alt-h", trigger: .press, kept: .lua, replacedAction: "focus left")])
        #expect(config.bindRecords.first { $0.keys == "alt-h" }?.source == .lua)
    }

    @Test func aBindOfInitLuaBeforeTheCallLoses() throws {
        let config = try load("wm.bind('alt-h', 'focus right')\nwm.shortcuts()", toml: file)

        #expect(config.binds["main"]?[try parseChord("alt-h")] == .command("focus left"))
        #expect(config.overrides == [BindOverride(mode: "main", keys: "alt-h", trigger: .press, kept: .shortcuts, replacedAction: "focus right")])
    }

    @Test func twoBindsOfInitLuaAreNotAnOverride() throws {
        let config = try load("wm.bind('alt-x', 'a')\nwm.bind('alt-x', 'b')")

        #expect(config.overrides.isEmpty)
    }

    @Test func aBrokenFileFailsTheLoadWithTheLine() throws {
        let toml = "[[shortcut]]\nkeys = \"alt-h\"\naction = nope"

        #expect(throws: (any Error).self) { try load("wm.shortcuts()", toml: toml) }
        do { _ = try load("wm.shortcuts()", toml: toml) } catch {
            #expect("\(error)".contains("shortcuts.toml line 3: 'nope' is not a string, boolean or number"))
        }
    }

    @Test func aSequenceInTheFileThatStartsAChordOfInitLuaNamesTheFile() throws {
        let toml = "[[shortcut]]\nkeys = \"alt-p>h\"\naction = \"focus left\""

        do { _ = try load("wm.shortcuts()\nwm.bind('alt-p', 'noop')", toml: toml) } catch {
            #expect("\(error)".contains("is also the first step of the sequence 'alt-p>h'"))
            #expect("\(error)".contains("(one of the binds is in shortcuts.toml)"))
            return
        }
        Issue.record("the config loaded")
    }

    @Test func checkConfigReportsTheOverrides() throws {
        try dir.write("shortcuts.toml", file)
        let url = try dir.write("init.lua", "wm.shortcuts()\nwm.bind('alt-h', 'focus right')")

        #expect(checkConfig(at: url) == .success(ConfigSummary(
            binds: 3, shortcutsImported: true,
            overrides: [BindOverride(mode: "main", keys: "alt-h", trigger: .press, kept: .lua, replacedAction: "focus left")])))
    }

    @Test func anOverrideIsDescribedForDoctorAndMatchesTheShortcutIdentity() throws {
        let override = BindOverride(mode: "main", keys: "alt-h", trigger: .press, kept: .lua, replacedAction: "focus left")

        #expect(override.description == "main: alt-h (init.lua replaces shortcuts.toml: focus left)")
        #expect(override.identity == Shortcut(keys: "Alt-H", action: "x").identity)
    }
}
