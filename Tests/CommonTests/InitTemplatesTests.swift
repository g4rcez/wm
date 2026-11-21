import Foundation
import Testing
@testable import Common

private func tempConfig() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("wm-init-\(UUID().uuidString)/wm/init.lua")
}

@Suite("wm init")
struct InitTemplatesTests {
    @Test func theConfigStartsWithTheChosenMod() {
        #expect(initConfig(.i3, mod: "cmd").hasPrefix("local mod = \"cmd\"\n"))
        #expect(initConfig(.niri, mod: "hyper").hasPrefix("local mod = \"hyper\"\n"))
    }

    @Test func theTemplatesAreNamedAsTheUsageSays() {
        #expect(InitTemplate.allCases.map(\.rawValue) == ["omarchy", "osx", "windows", "i3", "hyprland", "niri"])
        #expect(InitTemplate.allCases.first == .omarchy)
        #expect(InitTemplate.omarchy.defaultMod == "cmd")
        #expect(InitTemplate.omarchy.mods == ["alt", "cmd", "ctrl"])
        #expect(InitTemplate.osx.defaultMod == "ctrl")
        #expect(InitTemplate.niri.defaultMod == "alt")
    }

    @Test func writingCreatesTheFolderAndTheFile() throws {
        let url = tempConfig()
        #expect(try writeInitConfig("-- new\n", to: url, force: false) == true)
        #expect(try String(contentsOf: url, encoding: .utf8) == "-- new\n")
    }

    @Test func anExistingFileStaysWithoutForce() throws {
        let url = tempConfig()
        _ = try writeInitConfig("-- mine\n", to: url, force: false)
        #expect(try writeInitConfig("-- template\n", to: url, force: false) == false)
        #expect(try String(contentsOf: url, encoding: .utf8) == "-- mine\n")
    }

    @Test func forceReplacesAnExistingFile() throws {
        let url = tempConfig()
        _ = try writeInitConfig("-- mine\n", to: url, force: false)
        #expect(try writeInitConfig("-- template\n", to: url, force: true) == true)
        #expect(try String(contentsOf: url, encoding: .utf8) == "-- template\n")
    }

    @Test func theCommandCompletesTheTemplateNames() {
        guard case let .candidates(list) = complete(["init", ""]) else {
            Issue.record("expected candidates")
            return
        }
        #expect(Set(list.map(\.word)) == ["omarchy", "osx", "windows", "i3", "hyprland", "niri"])
    }

    @Test func theHelpShowsTheUsage() {
        #expect(renderHelp(topic: "init")?.contains("wm init [template] [--mod=<alt|cmd|ctrl|hyper>] [--force]") == true)
    }
}
