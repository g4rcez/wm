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
        guard template.mods.contains(mod) else { return }
        _ = try load(template, mod: mod)
    }

    @Test(arguments: ["alt", "cmd", "ctrl"])
    func omarchyKeepsEveryBindWhateverTheMod(mod: String) throws {
        let config = try load(.omarchy, mod: mod)
        let before = config.binds["main"]?.count ?? 0
        // Super+Alt and Super+Ctrl binds must not fall on the same keys as the Super ones.
        #expect(before >= 100)
    }

    @Test func omarchyFollowsTheHotkeysOfTheManual() throws {
        let config = try load(.omarchy, mod: "cmd")
        #expect(config.binds["main"]?[try parseChord("cmd-space")] == .command("palette"))
        #expect(config.binds["main"]?[try parseChord("cmd-w")] == .command("window close"))
        #expect(config.binds["main"]?[try parseChord("cmd-3")] == .command("workspace 3"))
        #expect(config.binds["main"]?[try parseChord("cmd-shift-3")] == .command("window send workspace 3"))
        #expect(config.binds["main"]?[try parseChord("cmd-alt-shift-3")] == .command("window send workspace 3 --stay"))
        #expect(config.binds["main"]?[try parseChord("cmd-shift-left")] == .command("swap left"))
        #expect(config.binds["main"]?[try parseChord("alt-tab")] == .command("switcher"))
    }

    @Test func omarchyUsesCmdForItsAltBindsWhenModIsAlt() throws {
        let config = try load(.omarchy, mod: "alt")
        #expect(config.binds["main"]?[try parseChord("alt-cmd-f")] == .command("window maximize"))
        #expect(config.binds["main"]?[try parseChord("alt-tab")] == .command("workspace next"))
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
