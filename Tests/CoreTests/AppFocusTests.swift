import Testing
@testable import Core

struct AppFocusTests {
    @Test func theNextWindowOfTheAppFollowsWhenTheFocusIsOnTheApp() {
        #expect(windowToRaise(ofApp: [7, 3, 9], focused: 3, recent: [9, 3, 7]) == 7)
        #expect(windowToRaise(ofApp: [7, 3, 9], focused: 7, recent: []) == 9)
    }

    @Test func theListWrapsAroundTheEnd() {
        #expect(windowToRaise(ofApp: [7, 3, 9], focused: 9, recent: []) == 3)
        #expect(windowToRaise(ofApp: [5], focused: 5, recent: []) == 5)
    }

    @Test func fromAnotherAppTheMostRecentWindowOfTheAppComesFirst() {
        #expect(windowToRaise(ofApp: [7, 3, 9], focused: 100, recent: [100, 9, 3, 7]) == 9)
        #expect(windowToRaise(ofApp: [7, 3, 9], focused: nil, recent: [7]) == 7)
    }

    @Test func windowsThatNeverHadTheFocusGoByTheLowestId() {
        #expect(windowToRaise(ofApp: [7, 3, 9], focused: 100, recent: []) == 3)
    }

    @Test func anAppWithoutWindowsGivesNothing() {
        #expect(windowToRaise(ofApp: [], focused: 1, recent: [1]) == nil)
    }
}
