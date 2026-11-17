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

    @Test func theViewportTakesTheGivenFractionOfTheWorkArea() {
        #expect(SpecialWorkspace.viewport(in: CGRect(x: 0, y: 0, width: 1000, height: 600), size: 0.8) == CGRect(x: 100, y: 60, width: 800, height: 480))
        #expect(SpecialWorkspace.viewport(in: CGRect(x: 0, y: 0, width: 1000, height: 600), size: 1) == CGRect(x: 0, y: 0, width: 1000, height: 600))
    }

    @Test func aNormalWindowHidesTheSpecialWorkspaceOfItsOwnMonitor() {
        let hiding = SpecialWorkspace.monitorsHiding(
            onFocusOf: 1, shown: [1: "special:term", 2: "special:notes"], otherMonitors: false) { _ in true }
        #expect(hiding == [1])
    }

    @Test func withTheSettingItHidesTheSpecialWorkspacesOfEveryMonitor() {
        let hiding = SpecialWorkspace.monitorsHiding(
            onFocusOf: 1, shown: [1: "special:term", 2: "special:notes"], otherMonitors: true) { _ in true }
        #expect(hiding == [1, 2])
    }

    @Test func anEmptySpecialWorkspaceStays() {
        let hiding = SpecialWorkspace.monitorsHiding(
            onFocusOf: 1, shown: [1: "special:term", 2: "special:notes"], otherMonitors: true) { $0 == "special:notes" }
        #expect(hiding == [2])
    }

    @Test func nothingHidesWhenNoSpecialWorkspaceIsShown() {
        #expect(SpecialWorkspace.monitorsHiding(onFocusOf: 1, shown: [:], otherMonitors: true) { _ in true } == [])
    }
}
