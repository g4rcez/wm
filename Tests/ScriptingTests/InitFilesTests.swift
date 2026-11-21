import Common
import Foundation
import Testing
@testable import Scripting

/// `wm init` puts the binds in shortcuts.toml; the config that results must bind what the Lua template (`--lua`) binds.
@Suite("wm init files", .serialized)
struct InitFilesTests {
    let host = LuaHost(bridge: FakeBridge())

    private func records(_ config: LoadedConfig) -> Set<String> {
        Set(config.bindRecords.map { "\($0.mode)|\($0.keys)|\($0.trigger.rawValue)|\($0.action)|\($0.options.description ?? "")" })
    }

    @Test(arguments: InitTemplate.allCases, ["alt", "cmd", "ctrl", "hyper"])
    func theFilesBindWhatTheLuaTemplateBinds(template: InitTemplate, mod: String) throws {
        guard template.mods.contains(mod) else { return }
        let lua = try ConfigDir()
        let split = try ConfigDir()
        let full = try host.load(configURL: lua.write("init.lua", initConfig(template, mod: mod)))
        let files = try initFiles(template, mod: mod)
        _ = try split.write("shortcuts.toml", files.shortcuts)
        let loaded = try host.load(configURL: split.write("init.lua", files.lua))

        #expect(records(loaded) == records(full))
        #expect(loaded.settings == full.settings)
    }

    @Test func theLuaFileKeepsNoBindsThatTheTomlHas() throws {
        let files = try initFiles(.omarchy, mod: "cmd")

        #expect(files.lua.contains("wm.shortcuts()"))
        #expect(!files.lua.contains("bind(\"w\""))
        #expect(!files.lua.contains("for n = 1, 9"))
        #expect(files.shortcuts.contains("keys = \"cmd-w\""))
        #expect(files.shortcuts.contains("keys = \"cmd-3\""))
    }

    @Test func existingFilesAreKeptWithoutForce() throws {
        let dir = try ConfigDir()
        let url = try dir.write("init.lua", "-- mine\n")
        let files = try initFiles(.i3, mod: "alt")

        #expect(try writeInitFiles(files, to: url, force: false) == false)
        #expect(try String(contentsOf: url, encoding: .utf8) == "-- mine\n")
        #expect(try writeInitFiles(files, to: url, force: true) == true)
        #expect(FileManager.default.fileExists(atPath: shortcutsURL(for: url).path))
    }
}
