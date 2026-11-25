import Core
import Foundation
import Testing
@testable import Scripting

@Suite("Dim config", .serialized)
struct DimConfigTests {
    private let host = LuaHost(bridge: FakeBridge())
    private let dir: ConfigDir

    init() throws { dir = try ConfigDir() }

    private func load(_ script: String) throws -> LoadedConfig {
        try host.load(configURL: dir.write("init.lua", script))
    }

    @Test func dimReadsItsKeys() throws {
        let config = try load("wm.config { dim = { enabled = true, amount = 0.5, color = '#102030' } }")
        #expect(config.settings.dim.enabled)
        #expect(config.settings.dim.amount == 0.5)
        #expect(config.settings.dim.color.red == Double(0x10) / 255)
    }

    @Test(arguments: [
        ("wm.config { dim = { amount = 1 } }", "dim.amount"),
        ("wm.config { dim = { opacity = 1 } }", "unknown key 'dim.opacity'"),
        ("wm.rule { app = 'x', dim = 0.5 }", "dim"),
    ])
    func badValuesAreErrors(script: String, expected: String) {
        let error = #expect(throws: ConfigError.self) { try load(script) }
        #expect(error?.message.contains(expected) == true)
    }

    @Test func aWorkspaceTurnsDimmingOnOrOff() throws {
        let config = try load("wm.config { dim = { enabled = true, amount = 0.4 } }\nwm.workspace('media', { dim = false })")
        var settings = config.settings
        try applyWorkspaceOverrides(try #require(config.workspaceRules["media"]?.overrides), to: &settings)
        #expect(!settings.dim.enabled)
        #expect(settings.dim.amount == 0.4)
    }

    @Test func aRuleKeepsAWindowBright() throws {
        let config = try load("wm.rule { app = 'org.videolan.vlc', dim = false }")
        #expect(config.rules.contains { $0.dim == false })
    }

    @Test func dimCanBeSetUntilTheNextReload() throws {
        var settings = Settings()
        try applyRuntimeSetting(path: "dim.enabled", value: "true", to: &settings)
        #expect(settings.dim.enabled)
    }
}
