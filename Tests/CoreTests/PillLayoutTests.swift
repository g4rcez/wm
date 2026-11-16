import CoreGraphics
import Testing
@testable import Core

struct PillLayoutTests {
    private func grid(_ count: Int, key: CGFloat = 20, label: CGFloat = 80, maxWidth: CGFloat, maxRows: Int = 3) -> PillLayout.Grid {
        PillLayout.grid(
            keyWidths: Array(repeating: key, count: count), labelWidths: Array(repeating: label, count: count),
            keyGap: 5, columnGap: 20, maxWidth: maxWidth, maxRows: maxRows)
    }

    @Test func everythingInOneRowWhenItFits() {
        // 6 columns of 105 and 5 gaps of 20.
        #expect(grid(6, maxWidth: 730) == PillLayout.Grid(rows: 1, columns: 6, visible: 6, truncated: false))
    }

    @Test func aNarrowerSpaceMakesMoreRows() {
        #expect(grid(6, maxWidth: 729) == PillLayout.Grid(rows: 2, columns: 3, visible: 6, truncated: false))
        #expect(grid(6, maxWidth: 355) == PillLayout.Grid(rows: 2, columns: 3, visible: 6, truncated: false))
        #expect(grid(6, maxWidth: 354) == PillLayout.Grid(rows: 3, columns: 2, visible: 6, truncated: false))
    }

    @Test func aLastRowMayBeShort() {
        // 7 items in 3 rows: 3 columns, the last row has one item.
        #expect(grid(7, maxWidth: 355) == PillLayout.Grid(rows: 3, columns: 3, visible: 7, truncated: false))
    }

    @Test func aColumnIsAsWideAsItsWidestKeyAndLabel() {
        // Two rows of two: column 0 holds items 0 and 2, column 1 holds 1 and 3.
        let shape = PillLayout.grid(
            keyWidths: [20, 20, 40, 20], labelWidths: [50, 100, 30, 10], keyGap: 5, columnGap: 10, maxWidth: 250, maxRows: 2)
        // Column 0: 40 + 5 + 50 = 95. Column 1: 20 + 5 + 100 = 125. Total 95 + 125 + 10 = 230 for two rows.
        #expect(shape == PillLayout.Grid(rows: 2, columns: 2, visible: 4, truncated: false))
        let narrower = PillLayout.grid(
            keyWidths: [20, 20, 40, 20], labelWidths: [50, 100, 30, 10], keyGap: 5, columnGap: 10, maxWidth: 229, maxRows: 2)
        #expect(narrower.truncated)
    }

    @Test func tooWideEvenInTheLastRowLeavesOutTheTail() {
        // 8 items, 2 rows, 4 columns would be 4 * 105 + 3 * 20 = 480; only one column of 105 fits in 200... two need 230.
        let shape = grid(8, maxWidth: 200, maxRows: 2)
        #expect(shape == PillLayout.Grid(rows: 2, columns: 1, visible: 2, truncated: true))
    }

    @Test func noItemsGiveAnEmptyGrid() {
        #expect(grid(0, maxWidth: 100) == PillLayout.Grid(rows: 0, columns: 0, visible: 0, truncated: false))
    }

    @Test func aListIsOneKeyPerLineUntilItIsTooTall() {
        #expect(PillLayout.list(count: 4, maxRows: 10) == PillLayout.Grid(rows: 4, columns: 1, visible: 4, truncated: false, columnMajor: true))
        #expect(PillLayout.list(count: 5, maxRows: 3) == PillLayout.Grid(rows: 3, columns: 2, visible: 5, truncated: false, columnMajor: true))
        #expect(PillLayout.list(count: 0, maxRows: 3).visible == 0)
    }

    @Test func aListIsFilledDownTheColumnsAndAGridAcrossTheRows() {
        let list = PillLayout.list(count: 5, maxRows: 3)
        #expect(list.position(of: 0) == (0, 0))
        #expect(list.position(of: 2) == (2, 0))
        #expect(list.position(of: 3) == (0, 1))
        #expect(list.position(of: 4) == (1, 1))
        let grid = PillLayout.Grid(rows: 2, columns: 3, visible: 6, truncated: false)
        #expect(grid.position(of: 1) == (0, 1))
        #expect(grid.position(of: 3) == (1, 0))
    }

    @Test func theSidePositionsAreTheOnesThatUseAList() {
        #expect(LabelPosition.allCases.filter(\.isSide) == [.topLeft, .topRight, .left, .right, .bottomLeft, .bottomRight])
    }
}
