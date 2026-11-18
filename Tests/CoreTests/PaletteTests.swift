import CoreGraphics
import Testing
@testable import Core

struct PaletteTests {
    // MARK: Query

    @Test func aGreaterThanSignPicksTheCommands() {
        #expect(PaletteQuery.parse(">layout") == PaletteQuery(mode: .commands, text: "layout"))
        #expect(PaletteQuery.parse("> layout set") == PaletteQuery(mode: .commands, text: "layout set"))
    }

    @Test func aSlashPicksTheMenuItems() {
        #expect(PaletteQuery.parse("/save as") == PaletteQuery(mode: .menu, text: "save as"))
    }

    @Test func withoutAPrefixTheDefaultModeSearches() {
        #expect(PaletteQuery.parse("  notes") == PaletteQuery(mode: .all, text: "notes"))
        #expect(PaletteQuery.parse("notes", default: .windows) == PaletteQuery(mode: .windows, text: "notes"))
        #expect(PaletteQuery.parse("") == PaletteQuery(mode: .all, text: ""))
    }

    // MARK: Matching

    @Test func theLettersOfAQueryMatchInOrderAnywhere() {
        #expect(fuzzyScore("ff", "Firefox") != nil)
        #expect(fuzzyScore("FRFX", "Firefox") != nil)
        #expect(fuzzyScore("xz", "Firefox") == nil)
        #expect(fuzzyScore("xf", "Firefox") == nil)
    }

    @Test func anEmptyQueryMatchesEverything() {
        #expect(fuzzyScore("", "Firefox") == 0)
    }

    @Test func aPrefixBeatsLettersSpreadOverTheText() throws {
        let prefix = try #require(fuzzyScore("saf", "Safari"))
        let spread = try #require(fuzzyScore("saf", "Software Update Fan"))
        #expect(prefix > spread)
    }

    @Test func theStartOfAWordScoresMoreThanTheMiddle() throws {
        let start = try #require(fuzzyScore("ta", "Mission Tab"))
        let middle = try #require(fuzzyScore("ta", "Mission Data"))
        #expect(start > middle)
    }

    // MARK: Ranking

    private let entries = [
        PaletteEntry(kind: .windows, title: "Disk Safari Fan", detail: "Notes", key: "1"),
        PaletteEntry(kind: .apps, title: "Safari", detail: "/Applications/Safari.app", key: "2"),
        PaletteEntry(kind: .apps, title: "Terminal", detail: "/System/Applications/Utilities/Terminal.app", key: "3"),
        PaletteEntry(kind: .commands, title: "layout set <scrolling|tiling>", detail: "Switch the layout", key: "layout set"),
    ]

    @Test func theBestMatchComesFirstAndNonMatchesGoAway() {
        let found = rank(entries, query: PaletteQuery(mode: .all, text: "saf"))
        #expect(found.map(\.key) == ["2", "1"])
    }

    @Test func withoutTextTheModeKeepsItsEntriesInOrder() {
        #expect(rank(entries, query: PaletteQuery(mode: .all, text: "")).map(\.key) == ["1", "2", "3"])
        #expect(rank(entries, query: PaletteQuery(mode: .commands, text: "")).map(\.key) == ["layout set"])
    }

    @Test func theCommandsAreOnlyFoundInTheCommandsMode() {
        #expect(rank(entries, query: PaletteQuery(mode: .all, text: "layout")).isEmpty)
        #expect(rank(entries, query: PaletteQuery(mode: .commands, text: "layout")).map(\.key) == ["layout set"])
    }

    @Test func aMatchInTheDetailStillFindsTheEntry() {
        #expect(rank(entries, query: PaletteQuery(mode: .windows, text: "notes")).map(\.key) == ["1"])
    }

    @Test func theAppsModeListsAppsAndWindowsButTheWindowsModeOnlyWindows() {
        #expect(rank(entries, query: PaletteQuery(mode: .apps, text: "")).map(\.key) == ["1", "2", "3"])
        #expect(rank(entries, query: PaletteQuery(mode: .windows, text: "")).map(\.key) == ["1"])
    }

    @Test func tabsAreFoundInTheAllListOnlyWithTextAndTheTabsListHoldsTabsAndWindows() {
        let tab = PaletteEntry(kind: .tabs, title: "Safari tips", detail: "https://example.com", key: "t")
        #expect(rank(entries + [tab], query: PaletteQuery(mode: .all, text: "")).map(\.key) == ["1", "2", "3"])
        #expect(rank(entries + [tab], query: PaletteQuery(mode: .all, text: "tips")).map(\.key) == ["t"])
        #expect(rank(entries + [tab], query: PaletteQuery(mode: .apps, text: "tips")).isEmpty)
        #expect(rank(entries + [tab], query: PaletteQuery(mode: .tabs, text: "")).map(\.key) == ["1", "t"])
        #expect(rank(entries + [tab], query: PaletteQuery(mode: .tabs, text: "saf")).map(\.key) == ["t", "1"])
    }

    // MARK: Running apps

    @Test func anAppIsFollowedByItsWindowsAndTheAppWithTheNewestWindowComesFirst() {
        let apps = [PaletteApp(pid: 10, name: "Mail"), PaletteApp(pid: 20, name: "Alacritty"), PaletteApp(pid: 30, name: "Dock")]
        let windows = [
            PaletteWindow(id: 1, pid: 10, title: "Inbox", place: "workspace 1"),
            PaletteWindow(id: 2, pid: 20, title: "zsh", place: "workspace 2"),
            PaletteWindow(id: 3, pid: 20, title: "vim", place: "workspace 2"),
        ]
        let list = paletteAppGroups(apps: apps, windows: windows, recent: [3, 1, 2])
        #expect(list.map(\.key) == ["20", "3", "2", "10", "30"])
        #expect(list.map(\.kind) == [.apps, .windows, .windows, .apps, .apps])
    }

    @Test func anAppWithOneWindowIsOneRowWithTheTitleOfTheWindow() {
        let apps = [PaletteApp(pid: 10, name: "Mail"), PaletteApp(pid: 20, name: "Notes")]
        let windows = [
            PaletteWindow(id: 1, pid: 10, title: "Inbox", place: "workspace 1 · mark:mail"),
            PaletteWindow(id: 2, pid: 20, title: "notes", place: "workspace 2"),
        ]
        let list = paletteAppGroups(apps: apps, windows: windows, recent: [1, 2])
        #expect(list.map(\.title) == ["Mail", "Notes"])
        #expect(list.map(\.detail) == ["Inbox · workspace 1 · mark:mail", "workspace 2"])
        #expect(list.map(\.key) == ["10", "20"])
    }

    // MARK: Command pictures

    @Test func aCommandGetsTheGlyphOfItsLongestKnownPath() {
        #expect(commandGlyph(for: ["focus", "left"]) == .focus(.left))
        #expect(commandGlyph(for: ["move", "<dir>"]) == .move(.right))
        #expect(commandGlyph(for: ["focus", "back"]) == .focusBack)
        #expect(commandGlyph(for: ["window", "send", "workspace", "2"]) == .sendWorkspace)
        #expect(commandGlyph(for: ["layout", "set", "tiling"]) == .layoutTiling)
        #expect(commandGlyph(for: ["layout", "set", "scrolling"]) == .layoutScrolling)
        #expect(commandGlyph(for: ["layout", "set", "master"]) == .layoutMaster)
        #expect(commandGlyph(for: ["layout", "master", "ratio"]) == .layoutMaster)
        #expect(commandGlyph(for: ["window", "close"]) == .close)
        #expect(commandGlyph(for: ["batch"]) == .generic)
    }

    // MARK: Position

    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func withoutASavedPositionThePaletteOpensCenteredNearTheTop() {
        #expect(paletteTopCenter(nil, in: screen, width: 760) == CGPoint(x: 500, y: 624))
    }

    @Test func aSavedPositionIsAFractionOfTheScreen() {
        #expect(paletteTopCenter(PalettePosition(x: 0.5, y: 0.1), in: screen, width: 760) == CGPoint(x: 500, y: 720))
        let second = CGRect(x: 1000, y: 0, width: 2000, height: 1000)
        #expect(paletteTopCenter(PalettePosition(x: 0.25, y: 0.5), in: second, width: 900) == CGPoint(x: 1500, y: 500))
    }

    @Test func aSavedPositionThatDoesNotFitIsPulledBackInsideTheScreen() {
        #expect(paletteTopCenter(PalettePosition(x: 0.99, y: 0.5), in: screen, width: 900) == CGPoint(x: 550, y: 400))
        #expect(paletteTopCenter(PalettePosition(x: 0.5, y: 0.99), in: screen, width: 760) == CGPoint(x: 500, y: 100))
        #expect(paletteTopCenter(PalettePosition(x: 0.5, y: -0.5), in: screen, width: 760) == CGPoint(x: 500, y: 800))
    }

    @Test func aMovedPaletteIsSavedAsFractions() {
        #expect(palettePosition(topCenter: CGPoint(x: 250, y: 600), in: screen) == PalettePosition(x: 0.25, y: 0.25))
    }
}
