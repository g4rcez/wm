import Testing
@testable import Core

struct PaletteTabsTests {
    @Test func safariTabsAreNamedByTheirPlaceInTheWindow() {
        let json = #"[{"id":"7","tabs":[{"id":"1","title":"Docs","url":"https://a.test"},{"id":"2","title":"","url":"https://b.test"}]}]"#
        #expect(
            browserTabs(json: json, bundleID: "com.apple.Safari") == [
                PaletteTab(source: .browser(bundleID: "com.apple.Safari", window: "7", tab: "1"), title: "Docs", detail: "https://a.test"),
                PaletteTab(source: .browser(bundleID: "com.apple.Safari", window: "7", tab: "2"), title: "https://b.test", detail: "https://b.test"),
            ])
    }

    @Test func theBrowserScriptGivesOneTabForEachTabOfEachWindow() {
        let json = #"[{"id":"7","tabs":[{"id":"11","title":"Swift","url":"https://swift.org/"},{"id":"12","title":"","url":"chrome://newtab/"}]},{"id":"8","tabs":[]}]"#
        #expect(
            browserTabs(json: json, bundleID: "net.imput.helium") == [
                PaletteTab(source: .browser(bundleID: "net.imput.helium", window: "7", tab: "11"), title: "Swift", detail: "https://swift.org/"),
                PaletteTab(source: .browser(bundleID: "net.imput.helium", window: "7", tab: "12"), title: "chrome://newtab/", detail: "chrome://newtab/"),
            ])
    }

    @Test func textThatIsNotTheJSONOfASourceGivesNothing() {
        #expect(browserTabs(json: "", bundleID: "net.imput.helium").isEmpty)
        #expect(browserTabs(json: #"{"error":"denied"}"#, bundleID: "net.imput.helium").isEmpty)
        #expect(rexSessions(json: "no server").isEmpty)
        #expect(rexTabs(json: "").isEmpty)
    }

    @Test func theSessionsOfRexAreTheirIdentifiers() {
        let json = #"{"sessions":[{"session_id":"session:01a1","label":"work"},{"session_id":"session:02b2","label":"notes"}]}"#
        #expect(rexSessions(json: json) == ["session:01a1", "session:02b2"])
    }

    @Test func aTabOfRexHasTheLabelOfItsWindowAndTheNameOfItsSession() {
        let json = """
            {"revision":4,"session_id":"session:01a1","label":"work","active_window_id":"window:0aa0",
             "windows":[{"window_id":"window:0aa0","label":"1: zsh · zetta","focused_block_id":"block:1","layers":[]},
                        {"window_id":"window:0bb0","label":"2: nvim","focused_block_id":"block:2","layers":[]}]}
            """
        #expect(
            rexTabs(json: json) == [
                PaletteTab(source: .rex(session: "session:01a1", window: "window:0aa0"), title: "1: zsh · zetta", detail: "work"),
                PaletteTab(source: .rex(session: "session:01a1", window: "window:0bb0"), title: "2: nvim", detail: "work"),
            ])
    }

    @Test func aWindowOfTmuxHasItsNameAndTheSessionProgramAndDirectory() {
        let output = "$0\t@0\tmain\t1\teditor\tnvim\t/Users/me/code\n$1\t@4\tops\t2\tlogs\ttail\t/var/log\n"
        #expect(
            tmuxWindows(output) == [
                PaletteTab(source: .tmux(session: "$0", window: "@0"), title: "editor", detail: "main:1 · nvim · /Users/me/code"),
                PaletteTab(source: .tmux(session: "$1", window: "@4"), title: "logs", detail: "ops:2 · tail · /var/log"),
            ])
    }

    @Test func aLineOfTmuxWithFewerFieldsIsLeftOut() {
        #expect(tmuxWindows("no server running on /private/tmp/tmux-501/default\n").isEmpty)
        #expect(tmuxWindows("").isEmpty)
    }

    @Test func theClientsOfTmuxHaveTheirTerminalProcessAndSession() {
        #expect(
            tmuxClients("/dev/ttys003\t4242\t$0\n/dev/ttys007\t5151\t$1\nbroken\n") == [
                TmuxClient(tty: "/dev/ttys003", pid: 4242, session: "$0"),
                TmuxClient(tty: "/dev/ttys007", pid: 5151, session: "$1"),
            ])
    }

    @Test func theClientOfTheSessionShowsTheWindowElseTheFirstClient() {
        let clients = [TmuxClient(tty: "/dev/ttys003", pid: 4242, session: "$0"), TmuxClient(tty: "/dev/ttys007", pid: 5151, session: "$1")]
        #expect(tmuxClient(for: "$1", among: clients) == TmuxClient(tty: "/dev/ttys007", pid: 5151, session: "$1"))
        #expect(tmuxClient(for: "$9", among: clients) == TmuxClient(tty: "/dev/ttys003", pid: 4242, session: "$0"))
        #expect(tmuxClient(for: "$0", among: []) == nil)
    }
}
