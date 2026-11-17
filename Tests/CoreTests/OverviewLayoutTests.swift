import CoreGraphics
import Testing
@testable import Core

struct OverviewLayoutTests {
    private func row(_ frames: [WindowID: CGRect], screen: CGSize = CGSize(width: 500, height: 500)) -> OverviewRowInput {
        OverviewRowInput(frames: frames, viewports: [], screen: screen)
    }

    private func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.01 && abs(a.minY - b.minY) < 0.01 && abs(a.width - b.width) < 0.01 && abs(a.height - b.height) < 0.01
    }

    @Test func aWorkspaceIsScaledToTheHeightOfItsStageAndCentred() {
        // Panel 1000 wide: the stage is 828 wide and 232 high, so the content has 800 x 204: the scale is 204 / 500.
        let geometry = OverviewLayout.compute([row([1: CGRect(x: 0, y: 0, width: 500, height: 500)])], panelWidth: 1000, maxPanelHeight: 900)
        let card = geometry.cards[1]!
        #expect(close(card, CGRect(x: 456, y: 90, width: 204, height: 204)))
    }

    @Test func aWideStripShrinksToTheWidthOfItsStage() {
        // Content 5000 x 500 does not fit 800 wide at the height scale, so the width decides: 800 / 5000 = 0.16.
        let geometry = OverviewLayout.compute([row([1: CGRect(x: 0, y: 0, width: 5000, height: 500)])], panelWidth: 1000, maxPanelHeight: 900)
        let card = geometry.cards[1]!
        #expect(close(card, CGRect(x: 158, y: 152, width: 800, height: 80)))
    }

    @Test func theRowsFollowEachOtherDownThePanelWithAGap() {
        let geometry = OverviewLayout.compute([row([1: CGRect(x: 0, y: 0, width: 10, height: 10)]), row([:])], panelWidth: 1000, maxPanelHeight: 900)
        #expect(geometry.rows[0].stage == CGRect(x: 144, y: 76, width: 828, height: 232))
        #expect(geometry.rows[1].stage == CGRect(x: 144, y: 322, width: 828, height: 232))
        #expect(geometry.rows[1].label == CGRect(x: 28, y: 322, width: 116, height: 232))
    }

    @Test func thePanelIsAsTallAsItsRowsNeed() {
        let geometry = OverviewLayout.compute([row([:]), row([:])], panelWidth: 1000, maxPanelHeight: 900)
        #expect(geometry.panel == CGSize(width: 1000, height: 76 + 232 + 14 + 232 + 24))
        #expect(geometry.contentHeight == geometry.rowsViewportHeight)
    }

    @Test func rowsShrinkBeforeTheyScroll() {
        // 4 rows of 232 need 970 high; 600 leaves 500 for the rows: (500 - 3 * 14) / 4 = 114.5 each.
        let geometry = OverviewLayout.compute((0..<4).map { _ in row([:]) }, panelWidth: 1000, maxPanelHeight: 600)
        #expect(geometry.rows[0].stage.height == 114.5)
        #expect(geometry.panel.height == 600)
        #expect(geometry.contentHeight == geometry.rowsViewportHeight)
    }

    @Test func manyRowsScrollAtTheMinimumHeight() {
        let geometry = OverviewLayout.compute((0..<10).map { _ in row([:]) }, panelWidth: 1000, maxPanelHeight: 600)
        #expect(geometry.rows[0].stage.height == 96)
        #expect(geometry.panel.height == 600)
        #expect(geometry.rowsViewportHeight == 500)
        #expect(geometry.contentHeight == 1086)
    }

    @Test func anEmptyWorkspaceIsDrawnWithTheShapeOfItsScreen() {
        let geometry = OverviewLayout.compute([row([:], screen: CGSize(width: 1000, height: 500))], panelWidth: 1000, maxPanelHeight: 900)
        // 1000 x 500 at 204 / 500 is 408 x 204.
        #expect(close(geometry.rows[0].content, CGRect(x: 354, y: 90, width: 408, height: 204)))
    }

    @Test func theOnScreenPartIsScaledWithTheWindows() {
        let input = OverviewRowInput(
            frames: [1: CGRect(x: 0, y: 0, width: 1000, height: 500), 2: CGRect(x: 1000, y: 0, width: 1000, height: 500)],
            viewports: [CGRect(x: 0, y: 0, width: 1000, height: 500)], screen: CGSize(width: 1000, height: 500))
        let geometry = OverviewLayout.compute([input], panelWidth: 1000, maxPanelHeight: 900)
        // 2000 x 500: the width gives 0.4, the height 0.408. The width decides.
        #expect(close(geometry.cards[2]!, CGRect(x: 558, y: 92, width: 400, height: 200)))
        #expect(close(geometry.rows[0].viewports[0], geometry.cards[1]!))
    }
}
