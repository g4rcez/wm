import Testing
@testable import Core

struct MonitorSelectorTests {
    @Test func aNumberNamesAMonitorByPositionStartingAtOne() {
        #expect(MonitorSelector.matches("1", index: 0, name: "Built-in Retina Display"))
        #expect(MonitorSelector.matches("2", index: 1, name: "LG UltraFine"))
        #expect(!MonitorSelector.matches("2", index: 0, name: "Built-in Retina Display"))
    }

    @Test func aWordMatchesPartOfTheNameIgnoringCase() {
        #expect(MonitorSelector.matches("retina", index: 3, name: "Built-in Retina Display"))
        #expect(MonitorSelector.matches("ULTRAFINE", index: 0, name: "LG UltraFine"))
        #expect(!MonitorSelector.matches("dell", index: 0, name: "LG UltraFine"))
    }

    @Test func mainIsTheMonitorWithTheMenuBar() {
        #expect(MonitorSelector.matches("main", index: 1, name: "LG", mainIndex: 1))
        #expect(!MonitorSelector.matches("main", index: 0, name: "DELL", mainIndex: 1))
    }

    @Test func otherRolesFollowFromLeftToRightWithoutTheMainMonitor() {
        // Monitors from the left: DELL, LG (main), BENQ.
        #expect(MonitorSelector.matches("secondary", index: 0, name: "DELL", mainIndex: 1))
        #expect(MonitorSelector.matches("tertiary", index: 2, name: "BENQ", mainIndex: 1))
        #expect(!MonitorSelector.matches("secondary", index: 2, name: "BENQ", mainIndex: 1))
    }

    @Test func aRoleWordWinsOverAPartOfAName() {
        #expect(!MonitorSelector.matches("main", index: 1, name: "Main Street Display", mainIndex: 0))
    }

    @Test func aMonitorHasTheRoleThatASelectorWouldUse() {
        // Monitors from the left: DELL, LG (main), BENQ, a fourth one.
        #expect(MonitorSelector.roleName(index: 1, mainIndex: 1) == "main")
        #expect(MonitorSelector.roleName(index: 0, mainIndex: 1) == "secondary")
        #expect(MonitorSelector.roleName(index: 2, mainIndex: 1) == "tertiary")
        #expect(MonitorSelector.roleName(index: 3, mainIndex: 1) == nil)
    }
}
