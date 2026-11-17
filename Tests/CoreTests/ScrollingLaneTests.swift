import CoreGraphics
import Testing
@testable import Core

// Viewport 1000x800, no gaps, default column width 0.5.
struct ScrollingLaneTests {
    private let context = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1000, height: 800), gaps: Gaps())

    // A reference type, because #expect cannot call mutating methods on a value.
    private final class Holder {
        var engine = ScrollingEngine(settings: Settings())
        init(_ ids: [WindowID]) {
            var previous: WindowID?
            for id in ids {
                engine.insert(id, after: previous)
                previous = id
            }
        }
        var columns: [[WindowID]] { engine.lanes(of: .horizontal) }
        func perform(_ command: LayoutCommand, focused: WindowID, in context: LayoutContext) -> Bool {
            engine.perform(command, focused: focused, in: context)
        }
    }

    // MARK: LaneIndex

    @Test func aLaneIndexCountsFromOneAndClampsToTheLast() {
        #expect(LaneIndex.first.resolve(count: 3) == 0)
        #expect(LaneIndex.last.resolve(count: 3) == 2)
        #expect(LaneIndex.number(2).resolve(count: 3) == 1)
        #expect(LaneIndex.number(9).resolve(count: 3) == 2)
    }

    @Test func aLaneIndexHasNoPlaceInAnEmptyListOrBelowOne() {
        #expect(LaneIndex.first.resolve(count: 0) == nil)
        #expect(LaneIndex.number(0).resolve(count: 3) == nil)
    }

    @Test func aLaneIndexReadsTheWordsOfTheCommands() {
        #expect(LaneIndex(parsing: "first") == .first)
        #expect(LaneIndex(parsing: "last") == .last)
        #expect(LaneIndex(parsing: "4") == .number(4))
        #expect(LaneIndex(parsing: "0") == nil)
        #expect(LaneIndex(parsing: "middle") == nil)
    }

    // MARK: Reading the lanes

    @Test func lanesListTheColumnsInOrder() {
        let holder = Holder([1, 2, 3])
        #expect(holder.columns == [[1], [2], [3]])
        #expect(holder.engine.lanes(of: .vertical) == [])
    }

    @Test func aColumnReportsItsSize() {
        let holder = Holder([1, 2])
        #expect(holder.engine.columnSize(of: 1) == 0.5)
        _ = holder.perform(.columnWidth(.fraction(0.8)), focused: 1, in: context)
        #expect(holder.engine.columnSize(of: 1) == 0.8)
        #expect(holder.engine.columnSize(of: 2) == 0.5)
        #expect(holder.engine.columnSize(of: 99) == nil)
    }

    // MARK: Moving a column

    @Test func aColumnMovesToTheFirstPlace() {
        let holder = Holder([1, 2, 3])
        #expect(holder.perform(.moveColumn(.first), focused: 3, in: context))
        #expect(holder.columns == [[3], [1], [2]])
    }

    @Test func aColumnMovesToANumberedPlace() {
        let holder = Holder([1, 2, 3])
        #expect(holder.perform(.moveColumn(.number(2)), focused: 1, in: context))
        #expect(holder.columns == [[2], [1], [3]])
    }

    @Test func aNumberThatIsTooLargeMovesTheColumnToTheEnd() {
        let holder = Holder([1, 2, 3])
        #expect(holder.perform(.moveColumn(.number(9)), focused: 1, in: context))
        #expect(holder.columns == [[2], [3], [1]])
    }

    @Test func movingAColumnToItsOwnPlaceChangesNothing() {
        let holder = Holder([1, 2, 3])
        #expect(!holder.perform(.moveColumn(.number(2)), focused: 2, in: context))
        #expect(holder.columns == [[1], [2], [3]])
    }

    @Test func aWholeStackMovesWithItsColumn() {
        let holder = Holder([1, 2, 3])
        _ = holder.perform(.stack(.left), focused: 2, in: context)
        #expect(holder.perform(.moveColumn(.last), focused: 1, in: context))
        #expect(holder.columns == [[3], [1, 2]])
    }

    // MARK: Stacking toward a side

    @Test func aWindowJoinsTheColumnOnItsRightAtTheBottom() {
        let holder = Holder([1, 2, 3])
        #expect(holder.perform(.stack(.right), focused: 1, in: context))
        #expect(holder.columns == [[2, 1], [3]])
    }

    @Test func aWindowCannotJoinAColumnPastTheEndOfTheStrip() {
        let holder = Holder([1, 2])
        #expect(!holder.perform(.stack(.right), focused: 2, in: context))
        #expect(!holder.perform(.stack(.left), focused: 1, in: context))
        #expect(holder.columns == [[1], [2]])
    }

    @Test func aWindowLeavesItsStackToTheLeftOrToTheRight() {
        let left = Holder([1, 2])
        _ = left.perform(.stack(.left), focused: 2, in: context)
        #expect(left.perform(.unstack(.left), focused: 2, in: context))
        #expect(left.columns == [[2], [1]])

        let right = Holder([1, 2])
        _ = right.perform(.stack(.left), focused: 2, in: context)
        #expect(right.perform(.unstack(.right), focused: 2, in: context))
        #expect(right.columns == [[1], [2]])
    }

    @Test func aLoneWindowHasNoStackToLeave() {
        let holder = Holder([1, 2])
        #expect(!holder.perform(.unstack(.left), focused: 1, in: context))
    }
}
