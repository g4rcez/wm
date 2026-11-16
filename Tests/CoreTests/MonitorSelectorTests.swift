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
}
