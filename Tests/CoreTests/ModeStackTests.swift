import Testing
@testable import Core

struct ModeStackTests {
    @Test func startsInMain() {
        #expect(ModeStack().current == "main")
    }

    @Test func backGoesToTheModeBefore() {
        var modes = ModeStack()
        modes.enter("resize")
        modes.enter("sizes")
        #expect(modes.back() == true)
        #expect(modes.current == "resize")
        #expect(modes.back() == true)
        #expect(modes.current == "main")
    }

    @Test func backInMainDoesNothing() {
        var modes = ModeStack()
        #expect(modes.back() == false)
        #expect(modes.current == "main")
    }

    @Test func enteringTheModeThatIsActiveChangesNothing() {
        var modes = ModeStack()
        modes.enter("resize")
        #expect(modes.enter("resize") == false)
        modes.back()
        #expect(modes.current == "main")
    }

    @Test func enteringMainForgetsTheHistory() {
        var modes = ModeStack()
        modes.enter("a")
        modes.enter("b")
        modes.enter("main")
        modes.enter("c")
        modes.back()
        #expect(modes.current == "main")
    }

    @Test func onlyTheLastEightModesAreKept() {
        var modes = ModeStack()
        for index in 1...10 { modes.enter("m\(index)") }
        var seen: [String] = []
        while modes.back() { seen.append(modes.current) }
        // m10 is current; the history holds main, m1 ... m9, and the oldest ones fall off: m2 ... m9 stay.
        #expect(seen == ["m9", "m8", "m7", "m6", "m5", "m4", "m3", "m2", "main"])
    }
}
