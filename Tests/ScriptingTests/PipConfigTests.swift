import Core
import Foundation
import Testing
@testable import Scripting

@Suite("Pip config", .serialized)
struct PipConfigTests {
    private let host = LuaHost(bridge: FakeBridge())
    private let dir: ConfigDir

    init() throws { dir = try ConfigDir() }

    private func load(_ script: String) throws -> LoadedConfig {
        try host.load(configURL: dir.write("init.lua", script))
    }

    @Test func pipReadsItsKeys() throws {
        let config = try load("wm.config { pip = { corner = 'top-left', size = 0.4, fps = 15, hide_when_visible = false } }")
        let pip = config.settings.pip
        #expect(pip.corner == .topLeft)
        #expect(pip.size == 0.4)
        #expect(pip.fps == 15)
        #expect(!pip.hideWhenVisible)
    }

    @Test(arguments: [
        ("wm.config { pip = { corner = 'middle' } }", "pip.corner"),
        ("wm.config { pip = { size = 0.9 } }", "pip.size"),
        ("wm.config { pip = { fps = 0 } }", "pip.fps"),
    ])
    func badValuesAreErrors(script: String, expected: String) {
        let error = #expect(throws: ConfigError.self) { try load(script) }
        #expect(error?.message.contains(expected) == true)
    }
}
