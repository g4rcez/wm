import Common
import Foundation
import Testing
@testable import Scripting

/// Every template has to load as a real config, with the main key as alt and as hyper.
@Suite("wm init templates", .serialized)
struct InitTemplateLoadTests {
    let host = LuaHost(bridge: FakeBridge())
    let dir: ConfigDir

    init() throws { dir = try ConfigDir() }

    private func load(_ template: InitTemplate, mod: String) throws -> LoadedConfig {
        try host.load(configURL: dir.write("init.lua", initConfig(template, mod: mod)))
    }

    @Test(arguments: InitTemplate.allCases, ["alt", "cmd", "ctrl", "hyper"])
    func everyTemplateLoads(template: InitTemplate, mod: String) throws {
        _ = try load(template, mod: mod)
    }

    @Test func osxBindsTheSpacesKeys() throws {
        let config = try load(.osx, mod: "ctrl")
        #expect(config.binds["main"]?[try parseChord("ctrl-3")] == .command("workspace 3"))
        #expect(config.binds["main"]?[try parseChord("ctrl-right")] == .command("workspace next"))
        #expect(config.binds["main"]?[try parseChord("cmd-tab")] == .command("switcher"))
    }

    @Test func windowsSnapsWithTheArrows() throws {
        let config = try load(.windows, mod: "alt")
        #expect(config.binds["main"]?[try parseChord("alt-left")] == .command("window snap left"))
        #expect(config.binds["main"]?[try parseChord("alt-f4")] == .command("window close"))
    }

    @Test func i3FocusesWithJKLSemicolonAndHasAResizeMode() throws {
        let config = try load(.i3, mod: "alt")
        #expect(config.binds["main"]?[try parseChord("alt-semicolon")] == .command("focus right"))
        #expect(config.binds["resize"]?[try parseChord("esc")] == .command("mode main"))
    }

    @Test func hyprlandUsesZeroForWorkspaceTen() throws {
        let config = try load(.hyprland, mod: "alt")
        #expect(config.binds["main"]?[try parseChord("alt-0")] == .command("workspace 10"))
        #expect(config.binds["main"]?[try parseChord("alt-shift-s")] == .command("window send workspace special:magic"))
    }

    @Test func niriSendsTheColumnToAWorkspace() throws {
        let config = try load(.niri, mod: "alt")
        #expect(config.binds["main"]?[try parseChord("alt-ctrl-2")] == .command("window send workspace 2 --column"))
    }

    @Test func hyperTurnsCapsLockOn() throws {
        #expect(try load(.niri, mod: "hyper").settings.binds.capsLockHyper == true)
        #expect(try load(.niri, mod: "alt").settings.binds.capsLockHyper == false)
    }
}
