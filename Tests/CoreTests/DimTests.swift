import Testing
@testable import Core

struct DimTests {
    @Test func everyShownWindowButTheFocusedOneIsDimmed() {
        #expect(windowsToDim(shown: [3, 1, 2], parked: [], focused: 2, exempt: []) == [1, 3])
    }

    @Test func parkedAndExemptWindowsStayAsTheyAre() {
        #expect(windowsToDim(shown: [1, 2, 3, 4], parked: [2], focused: 1, exempt: [3]) == [4])
    }

    @Test func withNoFocusEveryShownWindowIsDimmed() {
        #expect(windowsToDim(shown: [1, 2], parked: [], focused: nil, exempt: []) == [1, 2])
    }

    @Test func isOffByDefault() {
        #expect(!Settings().dim.enabled)
    }
}
