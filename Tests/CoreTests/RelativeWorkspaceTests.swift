import Testing
@testable import Core

struct RelativeWorkspaceTests {
    private let used: Set<String> = ["1", "2", "10", "web"]

    @Test func orderIsNumbersByValueThenNames() {
        #expect(RelativeWorkspace.ordered(["web", "10", "2", "1", "mail"]) == ["1", "2", "10", "mail", "web"])
    }

    @Test func nextAndPrevWalkTheWorkspacesInUse() {
        #expect(RelativeWorkspace.resolve("next", from: "2", used: used) == "10")
        #expect(RelativeWorkspace.resolve("prev", from: "2", used: used) == "1")
    }

    @Test func nextAndPrevWrapAround() {
        #expect(RelativeWorkspace.resolve("next", from: "web", used: used) == "1")
        #expect(RelativeWorkspace.resolve("prev", from: "1", used: used) == "web")
    }

    @Test func theCurrentWorkspaceCountsEvenWhenItHoldsNothing() {
        #expect(RelativeWorkspace.resolve("next", from: "5", used: used) == "10")
    }

    @Test func aLoneWorkspaceIsItsOwnNeighbour() {
        #expect(RelativeWorkspace.resolve("next", from: "3", used: []) == "3")
    }

    @Test func emptyIsTheLowestFreeNumber() {
        #expect(RelativeWorkspace.resolve("empty", from: "2", used: used) == "3")
        #expect(RelativeWorkspace.resolve("empty", from: "4", used: ["1", "2", "3"]) == "5")
    }

    @Test func specialWorkspacesAreNotPartOfTheCycle() {
        #expect(RelativeWorkspace.resolve("next", from: "1", used: ["1", "special:term", "2"]) == "2")
    }

    @Test func otherWordsAreNotRelative() {
        #expect(RelativeWorkspace.resolve("back", from: "1", used: used) == nil)
    }
}
