import Common
import Foundation
import Testing

struct WindowFlagTests {
    @Test func takesTheFlagAndItsIdOffTheFront() throws {
        let parsed = try parseWindowFlag(["--window", "3042", "window", "send", "workspace", "5", "--stay"])
        #expect(parsed.windowId == 3042)
        #expect(parsed.rest == ["window", "send", "workspace", "5", "--stay"])
    }

    @Test func acceptsTheEqualsForm() throws {
        let parsed = try parseWindowFlag(["--window=17", "close"])
        #expect(parsed.windowId == 17)
        #expect(parsed.rest == ["close"])
    }

    @Test func acceptsTheFlagAfterTheCommandToo() throws {
        let parsed = try parseWindowFlag(["window", "send", "workspace", "5", "--window", "3", "--stay"])
        #expect(parsed.windowId == 3)
        #expect(parsed.rest == ["window", "send", "workspace", "5", "--stay"])
        #expect(try parseWindowFlag(["close", "--window=9"]).windowId == 9)
    }

    @Test func leavesArgumentsWithoutTheFlagAlone() throws {
        let parsed = try parseWindowFlag(["focus", "left"])
        #expect(parsed.windowId == nil)
        #expect(parsed.rest == ["focus", "left"])
    }

    @Test func leavesExecAlone() throws {
        let parsed = try parseWindowFlag(["exec", "echo", "--window", "3"])
        #expect(parsed.windowId == nil)
        #expect(parsed.rest == ["exec", "echo", "--window", "3"])
    }

    @Test func rejectsAWordThatIsNeitherAnIdNorASelector() {
        #expect(throws: WindowFlagError(message: "--window needs a window id, or app:<name>, title:<regex>, pid:<n>, focused, got 'abc'")) {
            _ = try parseWindowFlag(["--window", "abc", "close"])
        }
    }

    @Test func takesASelectorInsteadOfAnId() throws {
        let parsed = try parseWindowFlag(["--window", "app:Notes", "window", "close"])
        #expect(parsed.windowId == nil)
        #expect(parsed.selector == "app:Notes")
        #expect(parsed.rest == ["window", "close"])
        #expect(try parseWindowFlag(["window", "close", "--window=title:^Inbox"]).selector == "title:^Inbox")
        #expect(try parseWindowFlag(["--window=focused", "window", "close"]).selector == "focused")
        #expect(try parseWindowFlag(["--window", "pid:412", "window", "close"]).selector == "pid:412")
    }

    @Test(arguments: ["app:", "title:", "pid:", "pid:abc", "class:x", "FOCUSED", ""])
    func rejectsABrokenSelector(text: String) {
        #expect(!isWindowSelector(text))
    }

    @Test func needsAnIdAndACommand() {
        let usage = WindowFlagError(message: "usage: wm --window <window> <command> [args...]")
        #expect(throws: usage) { _ = try parseWindowFlag(["--window", "5"]) }
        #expect(throws: usage) { _ = try parseWindowFlag(["--window=5"]) }
        let needs = WindowFlagError(message: "--window needs a window id, or app:<name>, title:<regex>, pid:<n>, focused")
        #expect(throws: needs) { _ = try parseWindowFlag(["--window"]) }
        #expect(throws: needs) { _ = try parseWindowFlag(["close", "--window"]) }
    }

    @Test func requestWithAWindowIdRoundTripsAndOldJSONStillDecodes() throws {
        let request = ClientRequest(args: ["close"], windowId: 9)
        let data = try JSONEncoder().encode(request)
        #expect(try JSONDecoder().decode(ClientRequest.self, from: data) == request)

        let old = Data(#"{"args":["ping"]}"#.utf8)
        #expect(try JSONDecoder().decode(ClientRequest.self, from: old) == ClientRequest(args: ["ping"]))
    }

    @Test func urlCarriesAWindowSelector() {
        #expect(commandRequest(fromURL: URL(string: "wm://window/close?window=app:Notes")!)
            == ClientRequest(args: ["window", "close"], windowSelector: "app:Notes"))
        #expect(commandRequest(fromURL: URL(string: "wm://window/close?window=nope")!) == nil)
    }

    @Test func urlCarriesTheWindowId() {
        #expect(commandRequest(fromURL: URL(string: "wm://close?window=3042")!) == ClientRequest(args: ["close"], windowId: 3042))
        #expect(commandRequest(fromURL: URL(string: "wm://window/send/workspace/5?args=--stay&window=7")!)
            == ClientRequest(args: ["window", "send", "workspace", "5", "--stay"], windowId: 7))
    }

    @Test func urlWithoutAWindowHasNone() {
        #expect(commandRequest(fromURL: URL(string: "wm://focus?args=left")!) == ClientRequest(args: ["focus", "left"]))
    }

    @Test func urlWithABadWindowOrSchemeIsRejected() {
        #expect(commandRequest(fromURL: URL(string: "wm://close?window=abc")!) == nil)
        #expect(commandRequest(fromURL: URL(string: "https://close?window=3")!) == nil)
    }
}
