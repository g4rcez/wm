import Core
import Foundation
import Testing
@testable import Scripting

@Suite("parseChordSequence")
struct ChordSequenceTests {
    @Test func singleChordGivesOneStep() throws {
        #expect(try parseChordSequence("alt-h") == [Chord(modifiers: [.option], key: "h")])
    }

    @Test func twoSteps() throws {
        #expect(try parseChordSequence("ctrl-p>h") == [Chord(modifiers: [.control], key: "p"), Chord(modifiers: [], key: "h")])
    }

    @Test func spacesAroundSeparatorsAreIgnored() throws {
        #expect(try parseChordSequence("alt-space > t > n") == [
            Chord(modifiers: [.option], key: "space"), Chord(modifiers: [], key: "t"), Chord(modifiers: [], key: "n"),
        ])
    }

    @Test(arguments: [">h", "ctrl-p>", "ctrl-p>>h", "ctrl-p> >h", ">"])
    func emptyStepIsAnError(text: String) {
        let error = #expect(throws: ChordError.self) { try parseChordSequence(text) }
        #expect(error?.message.contains("invalid key sequence '\(text)': a step is empty") == true)
    }

    @Test func badKeyInsideNamesTheKey() {
        let error = #expect(throws: ChordError.self) { try parseChordSequence("ctrl-p>foo") }
        #expect(error?.message.contains("unknown key 'foo'") == true)
    }
}

@Suite("Key sequences in config", .serialized)
struct SequenceConfigTests {
    let host = LuaHost(bridge: FakeBridge())
    let dir: ConfigDir

    init() throws { dir = try ConfigDir() }

    private func load(_ script: String) throws -> LoadedConfig {
        try host.load(configURL: dir.write("init.lua", script))
    }

    @Test func sequencesAreSeparateFromSingleChords() throws {
        let config = try load("""
        wm.bind("alt-a", "focus left")
        wm.bind("ctrl-p>h", "focus left")
        wm.bind("alt-space > t > n", "")
        wm.mode("windows", {
          ["x"] = "close",
          ["g>g"] = "focus first",
          ["g>e"] = function() end,
        })
        """)

        #expect(config.binds["main"]?.count == 1)
        #expect(config.binds["main"]?[try parseChord("alt-a")] == .command("focus left"))
        #expect(config.sequences["main"]?.count == 2)
        #expect(config.sequences["main"]?[try parseChordSequence("ctrl-p>h")] == .command("focus left"))
        #expect(config.sequences["main"]?[try parseChordSequence("alt-space>t>n")] == .command("noop"))
        #expect(config.binds["windows"]?.count == 1)
        #expect(config.sequences["windows"]?[try parseChordSequence("g>g")] == .command("focus first"))
        guard case .function? = config.sequences["windows"]?[try parseChordSequence("g>e")] else {
            Issue.record("g>e is not a function bind")
            return
        }
    }

    @Test func noSequencesGivesAnEmptyDictionary() throws {
        #expect(try load("wm.bind('alt-a', 'x')").sequences == [:])
    }

    @Test func rebindingTheSameSequenceReplacesIt() throws {
        let config = try load("""
        wm.bind("ctrl-p>h", "first")
        wm.bind("ctrl-p > h", "second")
        """)

        #expect(config.sequences["main"] == [try parseChordSequence("ctrl-p>h"): .command("second")])
    }

    @Test func definingAModeAgainDropsItsOldSequences() throws {
        let config = try load("""
        wm.mode("m", { ["a>b"] = "first" })
        wm.mode("m", { ["a"] = "second" })
        """)

        #expect(config.sequences["m"] == nil)
        #expect(config.binds["m"] == [try parseChord("a"): .command("second")])
    }

    @Test func sameChordsInDifferentModesDoNotConflict() throws {
        let config = try load("""
        wm.bind("ctrl-p", "x")
        wm.mode("m", { ["ctrl-p>h"] = "y" })
        """)

        #expect(config.binds["main"]?.count == 1)
        #expect(config.sequences["m"]?.count == 1)
    }

    @Test(arguments: [
        // A chord bound by itself and also the first step of a sequence, in both orders.
        ("wm.bind('ctrl-p', 'x')\nwm.bind('ctrl-p>h', 'y')",
         "mode 'main': 'ctrl-p' is bound by itself and is also the first step of the sequence 'ctrl-p>h'"),
        ("wm.bind('ctrl-p>h', 'y')\nwm.bind('ctrl-p', 'x')",
         "mode 'main': 'ctrl-p' is bound by itself and is also the first step of the sequence 'ctrl-p>h'"),
        // The same inside a mode, where the table order is not defined.
        ("wm.mode('m', { ['a'] = 'x', ['a>b'] = 'y' })",
         "mode 'm': 'a' is bound by itself and is also the first step of the sequence 'a>b'"),
        // A sequence that is the start of a longer one, in both orders.
        ("wm.bind('a>b', 'x')\nwm.bind('a>b>c', 'y')",
         "mode 'main': the sequence 'a>b' is the start of the sequence 'a>b>c'"),
        ("wm.bind('a>b>c', 'y')\nwm.bind('a>b', 'x')",
         "mode 'main': the sequence 'a>b' is the start of the sequence 'a>b>c'"),
        ("wm.mode('m', { ['a>b'] = 'x', ['a>b>c'] = 'y' })",
         "mode 'm': the sequence 'a>b' is the start of the sequence 'a>b>c'"),
        // Names are canonical, so spelling does not hide a conflict.
        ("wm.bind('control-p', 'x')\nwm.bind('ctrl + p > h', 'y')",
         "mode 'main': 'ctrl-p' is bound by itself and is also the first step of the sequence 'ctrl-p>h'"),
    ])
    func conflictsNameBothBindingsAndTheMode(script: String, expected: String) throws {
        let error = #expect(throws: ConfigError.self) { try load(script) }
        #expect(error?.message.contains(expected) == true)
        #expect(error?.message.contains("init.lua:") == true)
    }

    @Test(arguments: [
        ("wm.bind('ctrl-p>', 'x')", "mode 'main': invalid key sequence 'ctrl-p>': a step is empty"),
        ("wm.bind('>h', 'x')", "mode 'main': invalid key sequence '>h': a step is empty"),
        ("wm.mode('m', { ['a>foo'] = 'x' })", "mode 'm': invalid chord 'foo': unknown key 'foo'"),
    ])
    func badSequencesAreConfigErrors(script: String, expected: String) throws {
        let error = #expect(throws: ConfigError.self) { try load(script) }
        #expect(error?.message.contains(expected) == true)
    }
}

@Suite("prefix config", .serialized)
struct PrefixConfigTests {
    let host = LuaHost(bridge: FakeBridge())
    let dir: ConfigDir

    init() throws { dir = try ConfigDir() }

    @Test func defaultsStayWithoutAPrefixTable() throws {
        let config = try host.load(configURL: dir.write("init.lua", "wm.config { layout = 'scrolling' }"))
        #expect(config.settings.prefix == PrefixSettings())
    }

    @Test func allKeysAreRead() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.config {
          prefix = {
            timeout = 2.5,
            menubar = false,
            label = {
              enabled = false,
              position = "top-right",
              offset = { x = 10, y = -20 },
              font_size = 32,
              background = "#00000080",
              foreground = "#ff0000",
            },
          },
        }
        """))
        let prefix = config.settings.prefix

        #expect(prefix.menuBar == false)
        #expect(prefix.label.enabled == false)
        #expect(prefix.label.position == .topRight)
        #expect(prefix.label.offsetX == 10)
        #expect(prefix.label.offsetY == -20)
        #expect(prefix.label.fontSize == 32)
        #expect(prefix.label.background == Color(red: 0, green: 0, blue: 0, alpha: 128.0 / 255))
        #expect(prefix.label.foreground == Color(red: 1, green: 0, blue: 0))
    }

    @Test func missingKeysKeepTheirValue() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.config { prefix = { label = { position = "center", offset = { x = 4 } } } }
        """))
        let prefix = config.settings.prefix

        #expect(prefix.label.position == .center)
        #expect(prefix.label.offsetX == 4)
        #expect(prefix.label.offsetY == 0)
    }

    @Test(arguments: [
        ("wm.config { prefix = { label = { position = 'middle' } } }", "'prefix.label.position' must be one of \"top-left\", \"top-center\""),
        ("wm.config { prefix = { colour = 1 } }", "wm.config: unknown key 'prefix.colour'"),
        ("wm.config { prefix = { label = { colour = '#fff' } } }", "wm.config: unknown key 'prefix.label.colour'"),
        ("wm.config { prefix = { timeout = 0 } }", "'prefix.timeout' must be at least 0.1"),
        ("wm.config { prefix = { timeout = 'soon' } }", "'prefix.timeout' must be a number"),
        ("wm.config { prefix = { menubar = 1 } }", "'prefix.menubar' must be true or false"),
        ("wm.config { prefix = { label = { enabled = 'yes' } } }", "'prefix.label.enabled' must be true or false"),
        ("wm.config { prefix = { label = { font_size = 7 } } }", "'prefix.label.font_size' must be between 8 and 96"),
        ("wm.config { prefix = { label = { font_size = 97 } } }", "'prefix.label.font_size' must be between 8 and 96"),
        ("wm.config { prefix = { label = { offset = { z = 1 } } } }", "unknown key 'prefix.label.offset.z'"),
        ("wm.config { prefix = { label = { offset = { x = 'a' } } } }", "'prefix.label.offset.x' must be a number"),
        ("wm.config { prefix = { label = { background = 'red' } } }", "'prefix.label.background' must be a color"),
        ("wm.config { prefix = 3 }", "'prefix' must be a table"),
    ])
    func errorsNameTheKey(script: String, expected: String) throws {
        let error = #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.write("init.lua", script))
        }
        #expect(error?.message.contains(expected) == true)
        #expect(error?.message.contains("init.lua:1:") == true)
    }
}

@Suite("wm.dispatch options", .serialized)
struct DispatchOptionTests {
    let bridge = FakeBridge()
    let host: LuaHost
    let dir: ConfigDir

    init() throws {
        host = LuaHost(bridge: bridge)
        dir = try ConfigDir()
    }

    @Test func windowIsPassedToTheBridge() throws {
        bridge.dispatchResults["close"] = (0, "done", "")
        _ = try host.load(configURL: dir.write("init.lua", """
        local a = wm.dispatch("close")
        local b = wm.dispatch("close", { window = 42 })
        local c = wm.dispatch("close", {})
        local d = wm.dispatch("close", { window = 0 })
        local e = wm.dispatch("close", { window = 7.0 })
        wm.log(a, b, c, d, e)
        """))

        #expect(bridge.dispatched == ["close", "close", "close", "close", "close"])
        #expect(bridge.dispatchedWindows == [nil, 42, nil, 0, 7])
        #expect(bridge.logs == ["done done done done done"])
    }

    @Test func failureWithAWindowStillReturnsNilAndStderr() throws {
        bridge.dispatchResults["focus"] = (1, "", "no such window")
        _ = try host.load(configURL: dir.write("init.lua", """
        local out, err = wm.dispatch("focus", { window = 9 })
        wm.log(tostring(out), err)
        """))

        #expect(bridge.dispatchedWindows == [9])
        #expect(bridge.logs == ["nil no such window"])
    }

    @Test(arguments: [
        ("wm.dispatch('x', { windw = 1 })", "wm.dispatch: unknown option 'windw'"),
        ("wm.dispatch('x', { window = -1 })", "'window' must be a whole number >= 0"),
        ("wm.dispatch('x', { window = 1.5 })", "'window' must be a whole number >= 0"),
        ("wm.dispatch('x', { window = '7' })", "'window' must be a whole number >= 0"),
        ("wm.dispatch('x', { window = 4294967296 })", "'window' must be a whole number >= 0"),
        ("wm.dispatch('x', 7)", "the options must be a table"),
        ("wm.dispatch('x', 'window')", "the options must be a table"),
    ])
    func badOptionsAreErrors(script: String, expected: String) throws {
        let error = #expect(throws: ConfigError.self) {
            try host.load(configURL: dir.write("init.lua", script))
        }
        #expect(error?.message.contains(expected) == true)
        #expect(error?.message.contains("init.lua:1:") == true)
        #expect(bridge.dispatched == [])
    }
}
