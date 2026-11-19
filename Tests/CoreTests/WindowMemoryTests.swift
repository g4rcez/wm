import CoreGraphics
import Foundation
import Testing
@testable import Core

struct WindowMemoryTests {
    private func entry(_ app: String, title: String? = nil, workspace: String = "1") -> MemorizedWindow {
        MemorizedWindow(app: app, appName: app, title: title, workspace: workspace)
    }

    @Test func rememberingAnAppAgainReplacesItsEntry() {
        var memory = WindowMemory()
        memory.remember(entry("kitty", workspace: "2"))
        memory.remember(entry("kitty", workspace: "5"))
        #expect(memory.windows.count == 1)
        #expect(memory.windows[0].workspace == "5")
    }

    @Test func anAppEntryAndATitleEntryLiveSideBySide() {
        var memory = WindowMemory()
        memory.remember(entry("kitty", workspace: "2"))
        memory.remember(entry("kitty", title: "mail", workspace: "7"))
        #expect(memory.windows.count == 2)
    }

    @Test func theExactTitleWinsAndOtherTitlesFallBackToTheAppEntry() {
        var memory = WindowMemory()
        memory.remember(entry("kitty", workspace: "2"))
        memory.remember(entry("kitty", title: "mail", workspace: "7"))
        #expect(memory.match(app: "kitty", title: "mail")?.workspace == "7")
        #expect(memory.match(app: "kitty", title: "build")?.workspace == "2")
        #expect(memory.match(app: "safari", title: "mail") == nil)
    }

    @Test func aTitleEntryNeverMatchesAnotherTitle() {
        var memory = WindowMemory()
        memory.remember(entry("kitty", title: "mail", workspace: "7"))
        #expect(memory.match(app: "kitty", title: "build") == nil)
    }

    @Test func forgettingRemovesOnlyTheNamedEntry() {
        var memory = WindowMemory()
        memory.remember(entry("kitty", workspace: "2"))
        memory.remember(entry("kitty", title: "mail", workspace: "7"))
        let first = memory.forget(app: "kitty", title: "mail")
        #expect(first)
        #expect(memory.windows.map(\.workspace) == ["2"])
        let again = memory.forget(app: "kitty", title: "mail")
        #expect(!again)
        let last = memory.forget(app: "kitty", title: nil)
        #expect(last)
        #expect(memory.windows.isEmpty)
    }

    @Test func aFrameKeepsItsPlaceInAnotherSizeOfArea() {
        let area = CGRect(x: 100, y: 50, width: 1000, height: 800)
        let frame = CGRect(x: 350, y: 250, width: 500, height: 400)
        let relative = WindowMemory.relative(frame, in: area)
        #expect(relative == RelativeFrame(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        #expect(WindowMemory.absolute(relative, in: area) == frame)
        #expect(WindowMemory.absolute(relative, in: CGRect(x: 0, y: 0, width: 2000, height: 1000)) == CGRect(x: 500, y: 250, width: 1000, height: 500))
    }

    @Test func aFrameThatLeavesTheAreaIsMovedBackInside() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let outside = RelativeFrame(x: 0.9, y: -0.2, width: 0.5, height: 0.5)
        #expect(WindowMemory.absolute(outside, in: area) == CGRect(x: 500, y: 0, width: 500, height: 400))
        let tooBig = RelativeFrame(x: 0, y: 0, width: 3, height: 3)
        #expect(WindowMemory.absolute(tooBig, in: area) == area)
    }

    @Test func theMemoryRoundTripsThroughJSONAndOldEntriesLoad() throws {
        var memory = WindowMemory()
        memory.remember(MemorizedWindow(
            app: "kitty", appName: "kitty", title: "mail", workspace: "3", monitor: "LG UltraFine", floating: true,
            frame: RelativeFrame(x: 0.1, y: 0.1, width: 0.5, height: 0.5), maximized: false, pseudo: nil,
            columnWidth: 0.6, strip: .vertical, marks: ["mail"]))
        let data = try JSONEncoder().encode(memory)
        #expect(try JSONDecoder().decode(WindowMemory.self, from: data) == memory)
        // An entry that has only the required parts.
        let minimal = Data(#"{"version":1,"windows":[{"app":"a","appName":"A","workspace":"1","floating":false,"maximized":false,"marks":[]}]}"#.utf8)
        let loaded = try JSONDecoder().decode(WindowMemory.self, from: minimal)
        #expect(loaded.windows.first?.workspace == "1")
        #expect(loaded.windows.first?.frame == nil)
    }

    @Test func aStickyWindowIsKeptAndAnOldEntryStillLoads() throws {
        let entry = MemorizedWindow(app: "chat", appName: "Chat", workspace: "2", floating: true, sticky: true)
        let data = try JSONEncoder().encode(WindowMemory(windows: [entry]))
        #expect(try JSONDecoder().decode(WindowMemory.self, from: data).windows.first?.sticky == true)
        #expect(entry.summary == "Chat: workspace 2, floating, sticky")
        let old = Data(#"{"version":1,"windows":[{"app":"a","appName":"A","workspace":"1","floating":false,"maximized":false,"marks":[]}]}"#.utf8)
        #expect(try JSONDecoder().decode(WindowMemory.self, from: old).windows.first?.sticky == nil)
    }

    @Test func theSummaryNamesWhatWasKept() {
        let floating = MemorizedWindow(
            app: "kitty", appName: "Kitty", workspace: "3", monitor: "LG UltraFine", floating: true,
            frame: RelativeFrame(x: 0.1, y: 0.15, width: 0.62, height: 0.68))
        #expect(floating.summary == "Kitty: workspace 3 on LG UltraFine, floating 62% x 68%")
        #expect(floating.mode == "floating")
        #expect(floating.frameText == "62% x 68% at 10%, 15%")
        let tiled = MemorizedWindow(app: "mail", appName: "Mail", workspace: "2", columnWidth: 0.6, strip: .vertical, marks: ["mail", "inbox"])
        #expect(tiled.summary == "Mail: workspace 2, tiled, column 60%, vertical strip, marks: mail, inbox")
        #expect(tiled.frameText == "-")
        #expect(MemorizedWindow(app: "a", appName: "A", workspace: "1", maximized: true).mode == "maximized")
        #expect(MemorizedWindow(app: "a", appName: "A", workspace: "1", pseudo: CGSize(width: 800, height: 600)).mode == "pseudo")
    }

    private func rex() -> WindowMemory {
        var memory = WindowMemory()
        memory.remember(MemorizedWindow(app: "com.superlogical.rex", appName: "Rex Beta", workspace: "2", floating: true))
        memory.remember(MemorizedWindow(app: "com.superlogical.rex", appName: "Rex Beta", title: "mail", workspace: "3"))
        memory.remember(entry("kitty"))
        return memory
    }

    @Test func forgettingAnAppWithoutATitleKeepsItsTitleEntries() {
        var memory = rex()
        let removed = memory.forget(appNamed: "com.superlogical.rex", title: nil)
        #expect(removed.count == 1)
        #expect(removed[0].floating)
        #expect(memory.windows.map(\.title) == ["mail", nil])
    }

    @Test func forgettingFindsTheAppByItsNameWhateverTheCase() {
        var memory = rex()
        #expect(memory.forget(appNamed: "rex BETA", title: "mail").count == 1)
        #expect(memory.windows.count == 2)
        #expect(memory.forget(appNamed: "Kitty", title: nil).count == 1)
    }

    @Test func forgettingWithAllTitlesRemovesEveryEntryOfTheAppOnly() {
        var memory = rex()
        #expect(memory.forget(appNamed: "Rex Beta", title: nil, allTitles: true).count == 2)
        #expect(memory.windows.map(\.app) == ["kitty"])
    }

    @Test func forgettingAnUnknownAppOrTitleRemovesNothing() {
        var memory = rex()
        #expect(memory.forget(appNamed: "safari", title: nil).isEmpty)
        #expect(memory.forget(appNamed: "kitty", title: "mail").isEmpty)
        #expect(memory.windows.count == 3)
    }

    @Test func hasEntriesSeesAnAppByBundleIdOrName() {
        let memory = rex()
        #expect(memory.hasEntries(ofApp: "com.superlogical.rex"))
        #expect(memory.hasEntries(ofApp: "rex beta"))
        #expect(!memory.hasEntries(ofApp: "safari"))
    }

    @Test func clearRemovesEverythingAndCountsIt() {
        var memory = rex()
        #expect(memory.clear() == 3)
        #expect(memory.windows.isEmpty)
        #expect(memory.clear() == 0)
    }
}
