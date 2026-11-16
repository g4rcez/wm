import CoreGraphics
import Testing
@testable import Core

struct SpecialWorkspaceTests {
    @Test func noArgumentIsTheDefaultSpecialWorkspace() {
        #expect(SpecialWorkspace.name(nil) == "special")
    }

    @Test func aShortNameGetsThePrefix() {
        #expect(SpecialWorkspace.name("term") == "special:term")
    }

    @Test func aFullNameStaysAsItIs() {
        #expect(SpecialWorkspace.name("special:term") == "special:term")
        #expect(SpecialWorkspace.name("special") == "special")
    }

    @Test func anEmptyNameIsInvalid() {
        #expect(SpecialWorkspace.name("") == nil)
        #expect(SpecialWorkspace.name("special:") == nil)
    }

    @Test func onlyNamesWithThePrefixAreSpecial() {
        #expect(SpecialWorkspace.isSpecial("special") == true)
        #expect(SpecialWorkspace.isSpecial("special:term") == true)
        #expect(SpecialWorkspace.isSpecial("3") == false)
        #expect(SpecialWorkspace.isSpecial("specials") == false)
    }

    @Test func toggleShowsAHiddenSpecialWorkspace() {
        #expect(SpecialWorkspace.toggle("special:term", on: 1, shown: [:]) == [1: "special:term"])
    }

    @Test func toggleHidesTheOneThatIsShownOnThatMonitor() {
        #expect(SpecialWorkspace.toggle("special:term", on: 1, shown: [1: "special:term", 2: "special:notes"]) == [2: "special:notes"])
    }

    @Test func toggleReplacesAnotherSpecialWorkspaceOnThatMonitor() {
        #expect(SpecialWorkspace.toggle("special:term", on: 1, shown: [1: "special:notes"]) == [1: "special:term"])
    }

    @Test func toggleMovesOneThatIsShownOnAnotherMonitor() {
        #expect(SpecialWorkspace.toggle("special:term", on: 1, shown: [2: "special:term"]) == [1: "special:term"])
    }

    @Test func theViewportLeavesFivePercentOnEachSide() {
        #expect(SpecialWorkspace.viewport(in: CGRect(x: 0, y: 0, width: 1000, height: 600)) == CGRect(x: 50, y: 30, width: 900, height: 540))
    }
}
