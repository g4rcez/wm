import Foundation
import Testing
@testable import Core

struct SwallowTests {
    private func settings(_ configure: (inout SwallowSettings) -> Void = { _ in }) -> SwallowSettings {
        var settings = SwallowSettings()
        settings.enabled = true
        configure(&settings)
        return settings
    }

    private let ghostty = "com.mitchellh.ghostty"
    private let terminalA = Swallow.Candidate(id: 1, pid: 100, bundleID: "com.mitchellh.ghostty", appName: "Ghostty")
    private let terminalB = Swallow.Candidate(id: 2, pid: 100, bundleID: "com.mitchellh.ghostty", appName: "Ghostty")
    private let otherApp = Swallow.Candidate(id: 3, pid: 200, bundleID: "com.apple.Safari", appName: "Safari")

    private func host(
        app: String = "io.mpv", name: String = "mpv", ancestors: [Int32] = [50, 100, 1], candidates: [Swallow.Candidate],
        focused: WindowID? = nil, settings: SwallowSettings
    ) -> WindowID? {
        Swallow.host(bundleID: app, appName: name, ancestors: { ancestors }, candidates: candidates, focused: focused, settings: settings)
    }

    @Test func aProgramStartedInATerminalTakesItsWindow() {
        #expect(host(candidates: [terminalA], settings: settings()) == 1)
    }

    @Test func itIsOffUntilTheConfigTurnsItOn() {
        #expect(host(candidates: [terminalA], settings: SwallowSettings()) == nil)
    }

    @Test func theFocusedWindowOfTheTerminalIsTheHost() {
        #expect(host(candidates: [terminalA, terminalB], focused: 2, settings: settings()) == 2)
    }

    @Test func withoutFocusOnTheTerminalTheMostRecentWindowIsTheHost() {
        #expect(host(candidates: [terminalB, terminalA], focused: 3, settings: settings()) == 2)
        #expect(host(candidates: [terminalB, terminalA], focused: nil, settings: settings()) == 2)
    }

    @Test func aWindowThatDoesNotComeFromTheTerminalIsNotSwallowed() {
        #expect(host(ancestors: [50, 1], candidates: [terminalA], settings: settings()) == nil)
        #expect(host(candidates: [otherApp], settings: settings()) == nil)
    }

    @Test func aTerminalDoesNotSwallowAnotherTerminal() {
        #expect(host(app: "com.apple.Terminal", name: "Terminal", candidates: [terminalA], settings: settings()) == nil)
        #expect(host(app: "x", name: "GHOSTTY", candidates: [terminalA], settings: settings { $0.terminals = ["ghostty"] }) == nil)
    }

    @Test func anAppInTheExceptionsDoesNotSwallow() {
        #expect(host(candidates: [terminalA], settings: settings { $0.exceptions = ["IO.MPV"] }) == nil)
        #expect(host(candidates: [terminalA], settings: settings { $0.exceptions = ["mpv"] }) == nil)
    }

    @Test func onlyTheListedTerminalsCanBeSwallowed() {
        #expect(host(candidates: [terminalA], settings: settings { $0.terminals = ["com.apple.Terminal"] }) == nil)
        #expect(host(candidates: [terminalA], settings: settings { $0.terminals = ["Ghostty"] }) == 1)
    }

    @Test func theProcessTableIsNotReadWithoutATerminalWindow() {
        var read = false
        let result = Swallow.host(
            bundleID: "io.mpv", appName: "mpv", ancestors: { read = true; return [100] }, candidates: [otherApp], focused: nil,
            settings: settings())
        #expect(result == nil)
        #expect(!read)
    }
}
