import Foundation
import Scripting
import Testing
@testable import Cheatsheet

struct CheatsheetTests {
    private func bind(_ keys: String, _ command: String, description: String? = nil, mode: String = "main", trigger: BindTrigger = .press, hidden: Bool = false) -> CheatBind {
        CheatBind(mode: mode, keys: keys, command: command, description: description, trigger: trigger, hidden: hidden)
    }

    private func texts(_ row: CheatRow) -> [[String]] { row.steps.map { $0.map(\.text) } }

    @Test func aBindIsOneRowInTheSectionOfItsCommand() {
        let sheet = buildCheatsheet([
            bind("alt-h", "focus left", description: "Focus left"),
            bind("alt-w", "window close", description: "Close the window"),
            bind("alt-return", "exec open -a Ghostty"),
        ])
        #expect(sheet.pages.map(\.mode) == ["main"])
        #expect(sheet.pages[0].sections.map(\.title) == ["Focus & move", "Windows", "Apps & scripts"])
        let apps = sheet.pages[0].sections[2].rows[0]
        #expect(apps.title == "Run open -a Ghostty")
        #expect(texts(apps) == [["⌥", "RETURN"].map { $0 == "RETURN" ? "Return" : $0 }])
    }

    @Test func hiddenNoopAndReleaseBindsAreLeftOut() {
        let sheet = buildCheatsheet([
            bind("alt-a", "focus left", hidden: true), bind("alt-b", "noop"), bind("alt-c", "focus up", trigger: .release),
            bind("alt-d", "focus down"),
        ])
        #expect(sheet.pages[0].rowCount == 1)
    }

    @Test func aHoldBindShowsOnlyWhenTheKeyHasNoPlainBind() {
        let sheet = buildCheatsheet([
            bind("alt-a", "focus left"), bind("alt-a", "focus right", trigger: .hold), bind("alt-b", "focus up", trigger: .hold),
        ])
        #expect(sheet.pages[0].rowCount == 2)
    }

    @Test func universalBindsAreOnTheMainPageAndEveryModeHasAPage() {
        let sheet = buildCheatsheet([
            bind("alt-a", "focus left", mode: "*"), bind("h", "resize width +50", mode: "resize"), bind("alt-r", "mode resize"),
        ])
        #expect(sheet.pages.map(\.mode) == ["main", "resize"])
        #expect(sheet.pages[0].rowCount == 2)
        #expect(sheet.pageIndex(of: "resize") == 1)
        #expect(sheet.pageIndex(of: "nothing") == 0)
    }

    @Test func fourDirectionsJoinIntoOneRow() {
        let sheet = buildCheatsheet(["left", "right", "up", "down"].map { bind("hyper-\($0)", "focus \($0)", description: "Focus \($0)") })
        let rows = sheet.pages[0].sections[0].rows
        #expect(rows.count == 1)
        #expect(rows[0].title == "Focus direction")
        #expect(texts(rows[0]) == [["✦", "←↑↓→"]])
    }

    @Test func vimKeysJoinInTheOrderOfTheConfig() {
        let sheet = buildCheatsheet([("h", "left"), ("j", "down"), ("k", "up"), ("l", "right")].map { bind("alt-\($0.0)", "focus \($0.1)") })
        let rows = sheet.pages[0].sections[0].rows
        #expect(rows.count == 1)
        #expect(rows[0].title == "Focus direction")
        #expect(texts(rows[0]) == [["⌥", "H", "J", "K", "L"]])
    }

    @Test func twoDirectionsStayApart() {
        let sheet = buildCheatsheet([bind("alt-h", "focus left"), bind("alt-l", "focus right")])
        #expect(sheet.pages[0].rowCount == 2)
    }

    @Test func differentDescriptionsStayApart() {
        let sheet = buildCheatsheet([
            bind("alt-h", "focus left", description: "Go west"), bind("alt-j", "focus down", description: "Go south"),
            bind("alt-k", "focus up", description: "Go north"),
        ])
        #expect(sheet.pages[0].rowCount == 3)
    }

    @Test func nineWorkspaceKeysJoinIntoARange() {
        let sheet = buildCheatsheet((1...9).map { bind("hyper-\($0)", "workspace \($0)", description: "Go to workspace \($0)") })
        let rows = sheet.pages[0].sections[0].rows
        #expect(rows.count == 1)
        #expect(rows[0].title == "Go to workspace N")
        #expect(texts(rows[0]) == [["✦", "1–9"]])
    }

    @Test func aSequenceHasOneStepPerChord() {
        let sheet = buildCheatsheet([bind("ctrl-p>h", "focus left")])
        #expect(texts(sheet.pages[0].sections[0].rows[0]) == [["⌃", "P"], ["H"]])
    }

    @Test func aKeyThatIsNotAChordShowsAsItWasWritten() {
        let sheet = buildCheatsheet([bind("alt-scroll left", "workspace prev", mode: "gesture")])
        #expect(texts(sheet.pages[0].sections[0].rows[0]) == [["alt-scroll left"]])
    }

    @Test func theLegendListsOnlyTheModifiersInUse() {
        let sheet = buildCheatsheet([bind("hyper-a", "focus left"), bind("cmd-b", "focus right")])
        #expect(sheet.legend.map(\.symbol) == ["✦", "⌘"])
        #expect(sheet.legendText == "✦ hyper  ·  ⌘ cmd")
    }

    @Test func theFilterNeedsEveryWordAndDropsEmptySections() {
        let sheet = buildCheatsheet([bind("alt-h", "focus left", description: "Focus left"), bind("alt-w", "window close", description: "Close it")])
        let page = sheet.pages[0]
        #expect(page.filtered(by: "").rowCount == 2)
        #expect(page.filtered(by: "close").sections.map(\.title) == ["Windows"])
        #expect(page.filtered(by: "WINDOW close").rowCount == 1)
        #expect(page.filtered(by: "close focus").rowCount == 0)
        #expect(page.filtered(by: "⌥ w").rowCount == 1)
    }

    @Test func columnsGetAboutTheSameHeight() {
        let sections = [3, 1, 1, 2].map { CheatSection(title: "s\($0)", rows: Array(repeating: CheatRow(title: "", command: "", steps: [], note: ""), count: $0)) }
        let columns = packColumns(sections, count: 2)
        #expect(columns.map { $0.map(\.rows.count) } == [[3, 2], [1, 1]])
        #expect(packColumns(sections, count: 0).count == 1)
    }

    @Test func theJSONOfListBindsReads() {
        let json = #"[{"mode":"main","keys":"alt-h","trigger":"press","command":"focus left","description":"Left","hidden":true,"universal":false},{"mode":"x"}]"#
        #expect(CheatBind.decode(json: Data(json.utf8)) == [bind("alt-h", "focus left", description: "Left", hidden: true)])
        #expect(CheatBind.decode(json: Data("nonsense".utf8)).isEmpty)
    }

    @Test func theCliSheetIsOneBindPerLineWithNamedModifiers() {
        let sheet = buildCheatsheet([bind("alt-shift-h", "focus swap left", description: "Swap left"), bind("hyper-w>h", "focus left")])
        let text = renderPlainCheatsheet(sheet)
        #expect(!text.contains("\u{1B}"))
        #expect(text.contains("alt+shift+H"))
        #expect(text.contains("hyper+W > H"))
        #expect(text.contains("# Swap left  [focus swap left]"))
    }

    @Test func plainTextHasNoEscapeCodesAndKeepsTheLinesShort() {
        let sheet = buildCheatsheet((1...9).map { bind("hyper-\($0)", "workspace \($0)") } + [bind("alt-w", "window close", description: "Close the window")])
        let text = renderStatic(sheet, width: 80, palette: CheatPalette(enabled: false))
        #expect(!text.contains("\u{1B}"))
        #expect(text.contains("[✦] [1–9]"))
        #expect(text.contains("Close the window"))
        for line in text.split(separator: "\n") { #expect(line.count <= 80, "\(line)") }
    }

    @Test func theScreenHasExactlyTheHeightAndScrolls() {
        let binds = (0..<60).map { bind("alt-\(["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"][$0 % 10])", "exec echo \($0)", description: "Echo \($0)") }
        let sheet = buildCheatsheet(binds)
        let palette = CheatPalette(enabled: false)
        let first = renderScreen(sheet, page: 0, query: "", scroll: 0, width: 100, height: 20, palette: palette)
        #expect(first.lines.count == 20)
        #expect(first.maxScroll > 0)
        let last = renderScreen(sheet, page: 0, query: "", scroll: 10_000, width: 100, height: 20, palette: palette)
        #expect(last.lines.count == 20)
        #expect(last.lines != first.lines)
        let filtered = renderScreen(sheet, page: 0, query: "zzz", scroll: 0, width: 100, height: 20, palette: palette)
        #expect(filtered.lines.count == 20)
        #expect(filtered.lines.joined().contains("no key matches"))
    }
}
