import Testing
@testable import Core

struct WorkspaceBalanceTests {
    private func windows(_ places: [String]) -> [(id: WindowID, workspace: String)] {
        places.enumerated().map { (id: WindowID($0.offset + 1), workspace: $0.element) }
    }

    private func result(_ places: [String], pool: [String]) -> [String: Int] {
        let plan = WorkspaceBalance.plan(windows: windows(places), pool: pool)
        var counts: [String: Int] = [:]
        for (index, place) in places.enumerated() { counts[plan[WindowID(index + 1)] ?? place, default: 0] += 1 }
        return counts
    }

    @Test func oneWindowForEachWorkspaceWhenThereAreEnough() {
        let counts = result(["1", "1", "1"], pool: ["1", "2", "3", "4"])
        #expect(counts.values.allSatisfy { $0 == 1 })
        #expect(counts.count == 3)
    }

    @Test func extraWindowsAreSpreadByAtMostOne() {
        let counts = result(Array(repeating: "1", count: 7), pool: ["1", "2", "3"])
        #expect(counts.values.sorted() == [2, 2, 3])
    }

    @Test func aBalancedSetDoesNotMove() {
        #expect(WorkspaceBalance.plan(windows: windows(["1", "2", "3"]), pool: ["1", "2", "3"]).isEmpty)
        #expect(WorkspaceBalance.plan(windows: windows(["1", "1", "2", "2"]), pool: ["1", "2"]).isEmpty)
    }

    @Test func theFewestWindowsMove() {
        let plan = WorkspaceBalance.plan(windows: windows(["1", "1", "1", "1", "2"]), pool: ["1", "2"])
        #expect(plan.count == 1)
        #expect(plan.values.first == "2")
    }

    @Test func aWindowOutsideThePoolMoves() {
        let plan = WorkspaceBalance.plan(windows: windows(["9", "1"]), pool: ["1", "2"])
        #expect(plan == [1: "2"])
    }

    @Test func nothingToDoWithoutWindowsOrWorkspaces() {
        #expect(WorkspaceBalance.plan(windows: [], pool: ["1"]).isEmpty)
        #expect(WorkspaceBalance.plan(windows: windows(["1"]), pool: []).isEmpty)
    }
}

struct WorkspaceLimitTests {
    @Test(arguments: ["", " ", "  \t"])
    func aWorkspaceNeedsAName(name: String) {
        #expect(WorkspaceLimit.problem(name, limit: nil) == "a workspace needs a name")
        #expect(WorkspaceLimit.problem(name, limit: 9) == "a workspace needs a name")
    }

    @Test func withALimitTheNumbersAreOneToTheLimit() {
        #expect(WorkspaceLimit.problem("0", limit: 9)?.contains("1 to 9") == true)
        #expect(WorkspaceLimit.problem("-1", limit: 9)?.contains("1 to 9") == true)
        #expect(WorkspaceLimit.problem("10", limit: 9)?.contains("above the limit of 9") == true)
        #expect(WorkspaceLimit.problem("1", limit: 9) == nil)
        #expect(WorkspaceLimit.problem("9", limit: 9) == nil)
    }

    @Test func namesThatAreNotNumbersAndAnyNumberWithoutALimitAreFine() {
        #expect(WorkspaceLimit.problem("web", limit: 9) == nil)
        #expect(WorkspaceLimit.problem("0", limit: nil) == nil)
        #expect(WorkspaceLimit.problem("42", limit: nil) == nil)
    }

    @Test func aNumberAboveTheLimitIsRefused() {
        #expect(WorkspaceLimit.exceeds("7", limit: 6))
        #expect(!WorkspaceLimit.exceeds("6", limit: 6))
    }

    @Test func namesAndNoLimitAreFree() {
        #expect(!WorkspaceLimit.exceeds("web", limit: 6))
        #expect(!WorkspaceLimit.exceeds("0", limit: 6))
        #expect(!WorkspaceLimit.exceeds("99", limit: nil))
    }
}
