import Testing
@testable import Core

struct FloatGroupsTests {
    @Test func aDropMakesAGroupAndTheDroppedWindowShows() {
        var groups = FloatGroups()
        groups.join(2, with: 1)
        #expect(groups.group(of: 1) == [1, 2])
        #expect(groups.shownMember(of: 1) == 2)
        #expect(groups.waiting == [1])
    }

    @Test func aWindowJoinsAfterTheTarget() {
        var groups = FloatGroups()
        groups.join(2, with: 1)
        groups.join(3, with: 1)
        #expect(groups.group(of: 3) == [1, 3, 2])
        #expect(groups.waiting == [1, 2])
    }

    @Test func leavingShowsTheNextAndAGroupOfOneEnds() {
        var groups = FloatGroups()
        groups.join(2, with: 1)
        groups.join(3, with: 2)
        #expect(groups.shownMember(of: 1) == 3)
        groups.leave(3)
        #expect(groups.group(of: 1) == [1, 2])
        #expect(groups.shownMember(of: 1) == 2)
        groups.leave(1)
        #expect(groups.group(of: 2) == nil)
        #expect(groups.waiting.isEmpty)
    }

    @Test func cyclingWrapsAround() {
        var groups = FloatGroups()
        groups.join(2, with: 1)
        groups.join(3, with: 2)
        #expect(groups.cycle(1, by: 1) == 1)
        #expect(groups.cycle(1, by: -1) == 3)
        #expect(groups.cycle(9, by: 1) == nil)
    }

    @Test func joiningAnotherGroupLeavesTheOldOne() {
        var groups = FloatGroups()
        groups.join(2, with: 1)
        groups.join(4, with: 3)
        groups.join(2, with: 3)
        #expect(groups.group(of: 1) == nil)
        #expect(groups.group(of: 3) == [3, 2, 4])
    }

    @Test func aWindowCanBeShownDirectly() {
        var groups = FloatGroups()
        groups.join(2, with: 1)
        groups.show(1)
        #expect(groups.waiting == [2])
    }
}
