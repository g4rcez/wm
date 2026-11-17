import Testing
@testable import Core

struct DisplayMemoryTests {
    @Test func aDisplayThatComesBackGetsItsWorkspace() {
        var memory = DisplayMemory()
        memory.lost(7, workspace: "3")
        #expect(memory.returning(7, shown: ["1"]) == "3")
    }

    @Test func aWorkspaceThatAnotherMonitorShowsIsNotTaken() {
        var memory = DisplayMemory()
        memory.lost(7, workspace: "3")
        #expect(memory.returning(7, shown: ["1", "3"]) == nil)
    }

    @Test func aDisplayThatWasNeverLostHasNothingToReturn() {
        var memory = DisplayMemory()
        memory.lost(7, workspace: "3")
        #expect(memory.returning(8, shown: []) == nil)
    }

    @Test func theEntryIsUsedOnce() {
        var memory = DisplayMemory()
        memory.lost(7, workspace: "3")
        _ = memory.returning(7, shown: [])
        #expect(memory.returning(7, shown: []) == nil)
    }
}
