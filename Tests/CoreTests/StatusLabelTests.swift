import Testing
@testable import Core

struct StatusLabelTests {
    private func status(_ name: String, _ layout: LayoutKind? = .tiling, _ count: Int = 1) -> WorkspaceStatus {
        WorkspaceStatus(name: name, layout: layout, count: count)
    }

    private func text(_ all: [WorkspaceStatus], current: WorkspaceStatus, floating: Bool = false, _ settings: MenuBarSettings = MenuBarSettings()) -> String {
        StatusLabel.text(workspaces: all, current: current, floating: floating, settings: settings)
    }

    @Test func theLayoutOfTheWorkspaceGivesTheMode() {
        #expect(text([], current: status("1")) == "T:1")
        #expect(text([], current: status("5", .scrolling)) == "S:5")
        #expect(text([], current: status("2", .master)) == "M:2")
    }

    @Test func aFloatingFocusedWindowWinsOverTheLayout() {
        #expect(text([], current: status("9", .scrolling), floating: true) == "F:9")
        #expect(text([], current: status("9", nil), floating: true) == "F:9")
    }

    @Test func theWorkspacesWithWindowsAreListedInNumericOrder() {
        let all = [status("10"), status("2"), status("1"), status("9", .scrolling)]
        #expect(text(all, current: status("2")) == "1 T:2 9 10")
    }

    @Test func theCurrentWorkspaceIsListedEvenWhenEmpty() {
        let all = [status("1"), status("5")]
        #expect(text(all, current: status("3", .tiling, 0)) == "1 T:3 5")
    }

    @Test func aWorkspaceWithoutWindowsIsLeftOut() {
        let all = [status("1"), status("2", .tiling, 0), status("3")]
        #expect(text(all, current: status("1")) == "T:1 3")
    }

    @Test func namesThatAreNotNumbersComeAfterTheNumbersInAsciiOrder() {
        let all = [status("web"), status("Mail"), status("3"), status("1")]
        #expect(text(all, current: status("1")) == "T:1 3 Mail web")
    }

    @Test func onlyTheCurrentWorkspaceWhenTheSettingSaysSo() {
        var settings = MenuBarSettings()
        settings.workspaces = .current
        #expect(text([status("1"), status("2")], current: status("2"), settings) == "T:2")
    }

    @Test func theTemplatesAndTheSeparatorAreTheUsers() {
        var settings = MenuBarSettings()
        settings.current = "[{name}:{count}]"
        settings.other = "{mode}{name}"
        settings.separator = " | "
        #expect(text([status("1", .scrolling, 3), status("2", .tiling, 2)], current: status("2", .tiling, 2), settings) == "S1 | [2:2]")
    }

    @Test func aLongNameIsCut() {
        #expect(text([], current: status("special-notes")) == "T:specia")
    }

    @Test func onlyTheWorkspaceInFocusIsMarkedForTheBackground() {
        let all = [status("1"), status("5", .scrolling)]
        let pieces = StatusLabel.segments(workspaces: all, current: status("3"), floating: false, settings: MenuBarSettings())
        #expect(pieces == [
            StatusSegment("1"), StatusSegment(" "), StatusSegment("T:3", isCurrent: true), StatusSegment(" "), StatusSegment("5"),
        ])
    }

    @Test func noSeparatorGivesNoSeparatorPiece() {
        var settings = MenuBarSettings()
        settings.separator = ""
        let pieces = StatusLabel.segments(workspaces: [status("1")], current: status("2"), floating: false, settings: settings)
        #expect(pieces.map(\.text) == ["1", "T:2"])
    }

    @Test func noWorkspaceGivesNoText() {
        #expect(StatusLabel.segments(workspaces: [status("1")], current: status(""), floating: false, settings: MenuBarSettings()).isEmpty)
        #expect(text([status("1")], current: status("")) == "")
    }

    @Test func anUnknownPlaceholderIsFound() {
        #expect(StatusLabel.unknownPlaceholder(in: "{mode}:{name} {count}") == nil)
        #expect(StatusLabel.unknownPlaceholder(in: "{mode} {nme}") == "nme")
        #expect(StatusLabel.unknownPlaceholder(in: "no braces") == nil)
    }
}
