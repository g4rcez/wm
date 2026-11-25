import Testing
@testable import Core

struct SessionTests {
    private func saved(_ key: Int, _ app: String, _ title: String) -> RestoreCandidate {
        RestoreCandidate(key: key, bundleID: app, title: title, order: key)
    }

    private func open(_ id: WindowID, _ app: String, _ title: String) -> OpenWindow {
        OpenWindow(id: id, bundleID: app, title: title)
    }

    @Test func aWindowWithTheSavedTitleKeepsItsPlace() {
        let matches = matchOpenWindows(
            [open(1, "term", "new tab"), open(2, "term", "logs")],
            to: [saved(0, "term", "logs"), saved(1, "term", "editor")])
        #expect(matches == [2: 0, 1: 1])
    }

    @Test func windowsOfAnAppWithOtherTitlesGoInSavedOrder() {
        let matches = matchOpenWindows(
            [open(7, "term", "b"), open(3, "term", "a")], to: [saved(0, "term", "x"), saved(1, "term", "y")])
        #expect(matches == [3: 0, 7: 1])
    }

    @Test func extraWindowsAndOtherAppsStayUnmatched() {
        let matches = matchOpenWindows(
            [open(1, "term", ""), open(2, "term", ""), open(3, "mail", "")], to: [saved(0, "term", "")])
        #expect(matches == [1: 0])
    }

    @Test(arguments: ["dev", "work-2", "a.b_c"])
    func names(name: String) {
        #expect(isValidSessionName(name))
    }

    @Test(arguments: ["", ".hidden", "-x", "a/b", "../x", "with space", "é", String(repeating: "a", count: 65)])
    func badNames(name: String) {
        #expect(!isValidSessionName(name))
    }
}
