import CoreGraphics
import Testing
@testable import Core

// Viewport 1000x800, no gaps. Default settings: columns 0.5 wide, vertical zone on the right 0.25 wide, rows 0.5 high,
// sliver 8 points, parked height 0.9. Columns are 1, 2, 3 ...; rows are 10, 11, 12 ...
struct ScrollingTwoStripTests {
    private let context = LayoutContext(
        viewport: CGRect(x: 0, y: 0, width: 1000, height: 800), gaps: Gaps(), hiddenCorner: CGPoint(x: 4000, y: 3000))

    // A reference type, because #expect cannot call mutating methods on a value.
    private final class Workspace {
        var engine: ScrollingEngine
        init(_ engine: ScrollingEngine) { self.engine = engine }
        var windows: [WindowID] { engine.windows }
        var scrollOffset: CGFloat { engine.scrollOffset }
        var verticalWidth: Double { engine.verticalWidth }
        var verticalScrollOffset: CGFloat { engine.verticalScrollOffset }
        func strip(of window: WindowID) -> Orientation? { engine.strip(of: window) }
        func insert(_ window: WindowID, after anchor: WindowID?) { engine.insert(window, after: anchor) }
        func remove(_ window: WindowID) { engine.remove(window) }
        func perform(_ command: LayoutCommand, focused: WindowID?, in context: LayoutContext) -> Bool {
            engine.perform(command, focused: focused, in: context)
        }
        func frames(in context: LayoutContext, focused: WindowID?) -> [WindowID: CGRect] {
            engine.frames(in: context, focused: focused)
        }
        func neighbor(of window: WindowID, _ direction: Direction, wrap: Bool, in context: LayoutContext) -> WindowID? {
            engine.neighbor(of: window, direction, wrap: wrap, in: context)
        }
        func overview(in context: LayoutContext, focused: WindowID?) -> LayoutOverview {
            engine.overview(in: context, focused: focused)
        }
        func settle(in context: LayoutContext) -> WindowID? { engine.settle(in: context) }
    }

    private func settings(side: Direction = .right) -> Settings {
        var settings = Settings()
        settings.scrolling.singleWindowFit = .keep  // these tests are about widths; a lone column fills by default
        settings.scrolling.vertical.side = side
        return settings
    }

    private func workspace(columns: [WindowID], rows: [WindowID] = [], side: Direction = .right) -> Workspace {
        let workspace = Workspace(ScrollingEngine(settings: settings(side: side)))
        var previous: WindowID?
        for id in columns {
            workspace.insert(id, after: previous)
            previous = id
        }
        previous = nil
        for id in rows {
            workspace.insert(id, after: previous)
            if previous == nil { _ = workspace.perform(.sendToStrip(.vertical), focused: id, in: context) }
            previous = id
        }
        return workspace
    }

    // MARK: Balance

    @Test(arguments: [WindowID?.some(1), nil])
    func balanceGivesTheVerticalZoneItsConfiguredWidthAgain(focused: WindowID?) {
        let workspace = workspace(columns: [1, 2], rows: [10, 11])
        _ = workspace.perform(.balance, focused: nil, in: context)
        let balanced = workspace.frames(in: context, focused: 1)
        let resized = workspace.perform(.resize(.width, 100), focused: 10, in: context)
        #expect(resized)
        #expect(workspace.verticalWidth == 0.35)
        let changed = workspace.perform(.balance, focused: focused, in: context)
        #expect(changed)
        #expect(workspace.verticalWidth == 0.25)
        #expect(workspace.frames(in: context, focused: 1) == balanced)
    }

    // MARK: Zones

    @Test func twoColumnsAndTwoRowsSplitTheAreaThreeToOne() {
        let workspace = workspace(columns: [1, 2], rows: [10, 11])
        #expect(workspace.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 375, height: 800),
            2: CGRect(x: 375, y: 0, width: 375, height: 800),
            10: CGRect(x: 750, y: 0, width: 250, height: 400),
            11: CGRect(x: 750, y: 400, width: 250, height: 400),
        ])
    }

    @Test func theVerticalZoneCanBeOnTheLeft() {
        let workspace = workspace(columns: [1, 2], rows: [10, 11], side: .left)
        #expect(workspace.frames(in: context, focused: 1) == [
            1: CGRect(x: 250, y: 0, width: 375, height: 800),
            2: CGRect(x: 625, y: 0, width: 375, height: 800),
            10: CGRect(x: 0, y: 0, width: 250, height: 400),
            11: CGRect(x: 0, y: 400, width: 250, height: 400),
        ])
    }

    @Test func aWorkspaceWithOnlyRowsUsesTheWholeArea() {
        let workspace = workspace(columns: [], rows: [10, 11])
        #expect(workspace.frames(in: context, focused: 10) == [
            10: CGRect(x: 0, y: 0, width: 1000, height: 400),
            11: CGRect(x: 0, y: 400, width: 1000, height: 400),
        ])
    }

    @Test func gapsAreKeptBetweenTheZones() {
        let gapped = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1000, height: 800), gaps: Gaps(inner: 10, outer: 20))
        let workspace = workspace(columns: [1], rows: [10])
        // Area 20...980 grown by 5 on each side: 970 wide, so 727.5 and 242.5.
        #expect(workspace.frames(in: gapped, focused: 1) == [
            1: CGRect(x: 20, y: 20, width: 353.75, height: 760),
            10: CGRect(x: 747.5, y: 20, width: 232.5, height: 375),
        ])
    }

    @Test func withoutRowsTheFramesAreTheSingleStripFrames() {
        let workspace = workspace(columns: [1, 2, 3], rows: [10])
        _ = workspace.frames(in: context, focused: 3)
        workspace.remove(10)
        #expect(workspace.frames(in: context, focused: 3) == [
            1: CGRect(x: -492, y: 40, width: 500, height: 720),
            2: CGRect(x: 0, y: 0, width: 500, height: 800),
            3: CGRect(x: 500, y: 0, width: 500, height: 800),
        ])
        #expect(workspace.scrollOffset == 500)
    }

    // MARK: Strips

    @Test func sendToStripMovesTheWindowAcrossAndBack() {
        let workspace = workspace(columns: [1, 2])
        #expect(workspace.strip(of: 2) == .horizontal)
        #expect(workspace.perform(.sendToStrip(.vertical), focused: 2, in: context))
        #expect(workspace.strip(of: 2) == .vertical)
        #expect(workspace.strip(of: 1) == .horizontal)
        #expect(!workspace.perform(.sendToStrip(.vertical), focused: 2, in: context))
        #expect(!workspace.perform(.sendToStrip(.horizontal), focused: 1, in: context))
        #expect(workspace.perform(.sendToStrip(.horizontal), focused: 2, in: context))
        #expect(workspace.strip(of: 2) == .horizontal)
        #expect(workspace.windows == [1, 2])
    }

    @Test func aSentWindowOpensANewLaneAfterTheMostVisibleLane() {
        let workspace = workspace(columns: [1, 2], rows: [10, 11])
        _ = workspace.frames(in: context, focused: 1)
        #expect(workspace.perform(.sendToStrip(.vertical), focused: 1, in: context))
        #expect(workspace.windows == [2, 10, 1, 11])
        #expect(workspace.frames(in: context, focused: 1) == [
            2: CGRect(x: 0, y: 0, width: 375, height: 800),
            10: CGRect(x: 750, y: 0, width: 250, height: 400),
            1: CGRect(x: 750, y: 400, width: 250, height: 400),
            11: CGRect(x: 762.5, y: 792, width: 225, height: 400),
        ])
    }

    @Test func theLastWindowOfAStripLeavesAnEmptyStripBehind() {
        let workspace = workspace(columns: [1], rows: [10])
        #expect(workspace.perform(.sendToStrip(.horizontal), focused: 10, in: context))
        #expect(workspace.windows == [1, 10])
        #expect(workspace.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 800),
            10: CGRect(x: 500, y: 0, width: 500, height: 800),
        ])
    }

    @Test func insertOpensInTheStripOfTheAnchor() {
        let workspace = workspace(columns: [1], rows: [10])
        workspace.insert(11, after: 10)
        #expect(workspace.strip(of: 11) == .vertical)
        workspace.insert(2, after: nil)
        #expect(workspace.strip(of: 2) == .horizontal)
        workspace.insert(3, after: 1)
        #expect(workspace.windows == [1, 3, 2, 10, 11])
    }

    // MARK: Parking

    @Test func aColumnParkedNextToTheVerticalZoneGoesToTheHiddenCorner() {
        let workspace = workspace(columns: [1, 2, 3, 4], rows: [10])
        let frames = workspace.frames(in: context, focused: 1)
        #expect(frames[2] == CGRect(x: 375, y: 0, width: 375, height: 800))
        #expect(frames[3] == CGRect(x: 4000, y: 3000, width: 375, height: 800))
        #expect(frames[4] == CGRect(x: 4000, y: 3000, width: 375, height: 800))
    }

    @Test func aColumnParkedOnTheLeftKeepsASliver() {
        let workspace = workspace(columns: [1, 2, 3, 4], rows: [10])
        let frames = workspace.frames(in: context, focused: 4)
        #expect(workspace.scrollOffset == 750)
        #expect(frames[1] == CGRect(x: -367, y: 40, width: 375, height: 720))
        #expect(frames[2] == CGRect(x: -367, y: 40, width: 375, height: 720))
        #expect(frames[3] == CGRect(x: 0, y: 0, width: 375, height: 800))
        #expect(frames[4] == CGRect(x: 375, y: 0, width: 375, height: 800))
    }

    @Test func aColumnParkedOnTheLeftUsesTheCornerWhenTheLeftEdgeHasNoRoom() {
        let blocked = LayoutContext(
            viewport: context.viewport, gaps: Gaps(), hiddenCorner: CGPoint(x: 4000, y: 3000), sliverEdges: [.right, .down])
        let workspace = workspace(columns: [1, 2, 3, 4], rows: [10])
        #expect(workspace.frames(in: blocked, focused: 4)[1] == CGRect(x: 4000, y: 3000, width: 375, height: 800))
    }

    @Test func withTheVerticalZoneOnTheLeftTheRightSideKeepsTheSliverAndTheLeftSideUsesTheCorner() {
        let workspace = workspace(columns: [1, 2, 3, 4], rows: [10], side: .left)
        let first = workspace.frames(in: context, focused: 1)
        #expect(first[3] == CGRect(x: 992, y: 40, width: 375, height: 720))
        let last = workspace.frames(in: context, focused: 4)
        #expect(last[1] == CGRect(x: 4000, y: 3000, width: 375, height: 800))
    }

    @Test func aColumnParkedWithoutAVerticalZoneStillKeepsTheSliverOnTheRight() {
        let workspace = workspace(columns: [1, 2, 3, 4])
        #expect(workspace.frames(in: context, focused: 1)[3] == CGRect(x: 992, y: 40, width: 500, height: 720))
    }

    @Test func aRowAboveTheZoneGoesToTheCornerAndARowBelowKeepsASliverAtTheBottom() {
        let above = workspace(columns: [1], rows: [10, 11, 12])
        let framesAbove = above.frames(in: context, focused: 12)
        #expect(above.verticalScrollOffset == 400)
        #expect(framesAbove[10] == CGRect(x: 4000, y: 3000, width: 250, height: 400))
        #expect(framesAbove[11] == CGRect(x: 750, y: 0, width: 250, height: 400))
        #expect(framesAbove[12] == CGRect(x: 750, y: 400, width: 250, height: 400))

        let below = workspace(columns: [1], rows: [10, 11, 12])
        #expect(below.frames(in: context, focused: 10)[12] == CGRect(x: 762.5, y: 792, width: 225, height: 400))
    }

    @Test func aRowBelowTheZoneUsesTheCornerWhenTheBottomEdgeHasNoRoom() {
        let blocked = LayoutContext(
            viewport: context.viewport, gaps: Gaps(), hiddenCorner: CGPoint(x: 4000, y: 3000), sliverEdges: [.left, .right])
        let workspace = workspace(columns: [1], rows: [10, 11, 12])
        #expect(workspace.frames(in: blocked, focused: 10)[12] == CGRect(x: 4000, y: 3000, width: 250, height: 400))
    }

    @Test func withoutAHiddenCornerParkedWindowsGoToTheBottomRightOfTheViewport() {
        let plain = LayoutContext(viewport: context.viewport, gaps: Gaps())
        let workspace = workspace(columns: [1, 2, 3, 4], rows: [10])
        #expect(workspace.frames(in: plain, focused: 1)[3] == CGRect(x: 999, y: 799, width: 375, height: 800))
    }

    // MARK: Scrolling

    @Test func focusMovingToTheOtherStripKeepsTheScrollOffsetOfThisOne() {
        let workspace = workspace(columns: [1, 2, 3], rows: [10, 11, 12])
        _ = workspace.frames(in: context, focused: 12)
        #expect(workspace.verticalScrollOffset == 400)
        _ = workspace.frames(in: context, focused: 1)
        #expect(workspace.verticalScrollOffset == 400)
        #expect(workspace.scrollOffset == 0)
    }

    @Test func scrollActsOnTheStripOfTheFocusedWindowAndSettleReturnsItsNearestRow() {
        let workspace = workspace(columns: [1, 2], rows: [10, 11, 12])
        _ = workspace.frames(in: context, focused: 10)
        #expect(workspace.perform(.scroll(300), focused: 10, in: context))
        #expect(workspace.verticalScrollOffset == 300)
        #expect(workspace.scrollOffset == 0)
        #expect(workspace.frames(in: context, focused: 10)[10] == CGRect(x: 750, y: -300, width: 250, height: 400))
        #expect(workspace.settle(in: context) == 11)
        #expect(workspace.settle(in: context) == nil)
    }

    // MARK: Neighbours

    @Test func rightFromTheLastColumnEntersTheVerticalZone() {
        let workspace = workspace(columns: [1, 2], rows: [10, 11])
        #expect(workspace.neighbor(of: 1, .right, wrap: false, in: context) == 2)
        #expect(workspace.neighbor(of: 2, .right, wrap: false, in: context) == 10)
        #expect(workspace.neighbor(of: 2, .right, wrap: true, in: context) == 10)
    }

    @Test func leftFromARowEntersTheColumnNextToTheZone() {
        let workspace = workspace(columns: [1, 2], rows: [10, 11])
        #expect(workspace.neighbor(of: 10, .left, wrap: false, in: context) == 2)
        #expect(workspace.neighbor(of: 11, .left, wrap: false, in: context) == 2)
    }

    @Test func crossingPicksTheWindowWithTheLargestOverlap() {
        // Column 2 is a stack of 2 and 3 (400 high each); rows 10 and 11 are 400 high each.
        let workspace = workspace(columns: [1, 2, 3], rows: [10, 11])
        _ = workspace.perform(.stack(.left), focused: 3, in: context)
        #expect(workspace.neighbor(of: 2, .right, wrap: false, in: context) == 10)
        #expect(workspace.neighbor(of: 3, .right, wrap: false, in: context) == 11)
        #expect(workspace.neighbor(of: 10, .left, wrap: false, in: context) == 2)
        #expect(workspace.neighbor(of: 11, .left, wrap: false, in: context) == 3)
    }

    @Test func crossingWithTheVerticalZoneOnTheLeftIsMirrored() {
        let workspace = workspace(columns: [1, 2], rows: [10, 11], side: .left)
        #expect(workspace.neighbor(of: 1, .left, wrap: false, in: context) == 10)
        #expect(workspace.neighbor(of: 10, .right, wrap: false, in: context) == 1)
        #expect(workspace.neighbor(of: 2, .left, wrap: false, in: context) == 1)
        #expect(workspace.neighbor(of: 2, .right, wrap: false, in: context) == nil)
    }

    @Test func upAndDownInsideTheVerticalStripMoveBetweenRowsAndWrap() {
        let workspace = workspace(columns: [1], rows: [10, 11])
        #expect(workspace.neighbor(of: 10, .down, wrap: false, in: context) == 11)
        #expect(workspace.neighbor(of: 11, .up, wrap: false, in: context) == 10)
        #expect(workspace.neighbor(of: 10, .up, wrap: false, in: context) == nil)
        #expect(workspace.neighbor(of: 10, .up, wrap: true, in: context) == 11)
        #expect(workspace.neighbor(of: 11, .down, wrap: true, in: context) == 10)
        #expect(workspace.neighbor(of: 10, .right, wrap: false, in: context) == nil)
    }

    @Test func leftAndRightInsideARowWithTwoWindowsStayInTheRowUntilTheEdge() {
        let workspace = workspace(columns: [1], rows: [10, 11])
        _ = workspace.perform(.stack(.left), focused: 11, in: context)
        #expect(workspace.neighbor(of: 10, .right, wrap: false, in: context) == 11)
        #expect(workspace.neighbor(of: 11, .left, wrap: false, in: context) == 10)
        #expect(workspace.neighbor(of: 10, .left, wrap: false, in: context) == 1)
        #expect(workspace.neighbor(of: 11, .right, wrap: false, in: context) == nil)
        #expect(workspace.neighbor(of: 11, .right, wrap: true, in: context) == 10)
    }

    @Test func withoutRowsNothingCrossesTheEdge() {
        let workspace = workspace(columns: [1, 2])
        #expect(workspace.neighbor(of: 2, .right, wrap: false, in: context) == nil)
        #expect(workspace.neighbor(of: 2, .right, wrap: true, in: context) == 1)
    }

    // MARK: Move

    @Test func movingTowardTheVerticalZoneFromTheLastColumnSendsTheWindowAcross() {
        let workspace = workspace(columns: [1, 2], rows: [10])
        #expect(workspace.perform(.move(.right), focused: 2, in: context))
        #expect(workspace.strip(of: 2) == .vertical)
        #expect(workspace.windows == [1, 10, 2])
    }

    @Test func movingTowardTheVerticalZoneFromAMiddleColumnStillSwaps() {
        let workspace = workspace(columns: [1, 2], rows: [10])
        #expect(workspace.perform(.move(.right), focused: 1, in: context))
        #expect(workspace.windows == [2, 1, 10])
        #expect(workspace.strip(of: 1) == .horizontal)
    }

    @Test func movingAwayFromTheVerticalZoneAtTheFirstColumnDoesNothing() {
        let workspace = workspace(columns: [1, 2], rows: [10])
        #expect(!workspace.perform(.move(.left), focused: 1, in: context))
        #expect(workspace.windows == [1, 2, 10])
    }

    @Test func movingTowardTheHorizontalZoneFromARowSendsTheWindowAcross() {
        let workspace = workspace(columns: [1, 2], rows: [10, 11])
        #expect(workspace.perform(.move(.left), focused: 11, in: context))
        #expect(workspace.strip(of: 11) == .horizontal)
        #expect(workspace.windows == [1, 11, 2, 10])
    }

    @Test func movingTowardTheHorizontalZoneWithTheZoneOnTheLeftIsMirrored() {
        let workspace = workspace(columns: [1, 2], rows: [10], side: .left)
        #expect(!workspace.perform(.move(.left), focused: 10, in: context))
        #expect(workspace.perform(.move(.right), focused: 10, in: context))
        #expect(workspace.strip(of: 10) == .horizontal)
    }

    @Test func movingTowardAVerticalZoneOnTheLeftFromTheFirstColumnSendsTheWindowAcross() {
        let workspace = workspace(columns: [1, 2], rows: [10], side: .left)
        #expect(!workspace.perform(.move(.right), focused: 2, in: context))
        #expect(workspace.perform(.move(.left), focused: 1, in: context))
        #expect(workspace.strip(of: 1) == .vertical)
    }

    @Test func movingUpAndDownSwapsRowsAndMovingSidewaysReordersInsideTheRow() {
        let workspace = workspace(columns: [1], rows: [10, 11])
        #expect(workspace.perform(.move(.down), focused: 10, in: context))
        #expect(workspace.windows == [1, 11, 10])
        #expect(!workspace.perform(.move(.down), focused: 10, in: context))
        _ = workspace.perform(.stack(.left), focused: 10, in: context)
        #expect(workspace.windows == [1, 11, 10])
        #expect(workspace.perform(.move(.left), focused: 10, in: context))
        #expect(workspace.windows == [1, 10, 11])
    }

    // MARK: Resize

    @Test func resizingTheWidthOfARowChangesTheWidthOfTheVerticalZone() {
        let workspace = workspace(columns: [1, 2], rows: [10])
        #expect(workspace.perform(.resize(.width, 250), focused: 10, in: context))
        #expect(workspace.verticalWidth == 0.5)
        #expect(workspace.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 250, height: 800),
            2: CGRect(x: 250, y: 0, width: 250, height: 800),
            10: CGRect(x: 500, y: 0, width: 500, height: 400),
        ])
    }

    @Test func theWidthOfTheVerticalZoneIsClampedAndNeedsAHorizontalZone() {
        let workspace = workspace(columns: [1], rows: [10])
        #expect(workspace.perform(.resize(.width, 5000), focused: 10, in: context))
        #expect(workspace.verticalWidth == 0.9)
        #expect(!workspace.perform(.resize(.width, 5000), focused: 10, in: context))
        #expect(workspace.perform(.resize(.width, -5000), focused: 10, in: context))
        #expect(workspace.verticalWidth == 0.1)

        let alone = self.workspace(columns: [], rows: [10])
        #expect(!alone.perform(.resize(.width, 100), focused: 10, in: context))
    }

    @Test func resizingTheHeightOfARowChangesTheRowAndNotTheZone() {
        let workspace = workspace(columns: [1], rows: [10, 11])
        #expect(workspace.perform(.resize(.height, 200), focused: 10, in: context))
        #expect(workspace.verticalWidth == 0.25)
        let frames = workspace.frames(in: context, focused: 10)
        #expect(frames[10] == CGRect(x: 750, y: 0, width: 250, height: 600))
        #expect(frames[11] == CGRect(x: 750, y: 600, width: 250, height: 400))
        #expect(workspace.perform(.resize(.smart, -200), focused: 10, in: context))
        #expect(workspace.frames(in: context, focused: 10)[10]?.height == 400)
    }

    @Test func resizingAColumnStillUsesTheWidthOfItsOwnZone() {
        let workspace = workspace(columns: [1, 2], rows: [10])
        #expect(workspace.perform(.resize(.width, 375), focused: 1, in: context))
        #expect(workspace.frames(in: context, focused: 1)[1] == CGRect(x: 0, y: 0, width: 750, height: 800))
    }

    @Test func draggingTheEdgeOfARowThatFacesTheHorizontalZoneChangesTheZoneWidth() {
        let workspace = workspace(columns: [1], rows: [10, 11])
        #expect(workspace.perform(.resizeEdge(.left, 250), focused: 10, in: context))
        #expect(workspace.frames(in: context, focused: 1)[10] == CGRect(x: 500, y: 0, width: 500, height: 400))
        #expect(!workspace.perform(.resizeEdge(.right, 100), focused: 10, in: context))
    }

    @Test func draggingTheEdgeFacingTheZoneIsMirroredWhenTheVerticalZoneIsOnTheLeft() {
        let workspace = workspace(columns: [1], rows: [10], side: .left)
        #expect(!workspace.perform(.resizeEdge(.left, 100), focused: 10, in: context))
        #expect(workspace.perform(.resizeEdge(.right, 250), focused: 10, in: context))
        #expect(workspace.frames(in: context, focused: 1)[10] == CGRect(x: 0, y: 0, width: 500, height: 400))
    }

    @Test func draggingEitherEndOfARowAlongTheStripChangesItsHeight() {
        let workspace = workspace(columns: [1], rows: [10, 11])
        #expect(workspace.perform(.resizeEdge(.down, 200), focused: 10, in: context))
        #expect(workspace.frames(in: context, focused: 10)[10]?.height == 600)
        #expect(workspace.perform(.resizeEdge(.up, -200), focused: 11, in: context))
        #expect(workspace.frames(in: context, focused: 10)[11]?.height == 200)
    }

    @Test func draggingTheDividerInsideARowMovesWidthBetweenItsTwoWindows() {
        let workspace = workspace(columns: [1], rows: [10, 11])
        _ = workspace.perform(.stack(.left), focused: 11, in: context)
        #expect(workspace.perform(.resizeEdge(.right, 125), focused: 10, in: context))
        #expect(workspace.frames(in: context, focused: 10) == [
            1: CGRect(x: 0, y: 0, width: 375, height: 800),
            10: CGRect(x: 750, y: 0, width: 225, height: 400),
            11: CGRect(x: 975, y: 0, width: 25, height: 400),
        ])
    }

    @Test func draggingAnEdgeOfAColumnStillWidensItInsideItsZone() {
        let workspace = workspace(columns: [1, 2], rows: [10])
        #expect(workspace.perform(.resizeEdge(.right, 375), focused: 1, in: context))
        #expect(workspace.frames(in: context, focused: 1)[1] == CGRect(x: 0, y: 0, width: 750, height: 800))
    }

    // MARK: Other lane commands

    @Test func balanceFitsOnlyTheLanesOfTheFocusedStrip() {
        let workspace = workspace(columns: [1, 2], rows: [10, 11, 12, 13])
        #expect(workspace.perform(.balance, focused: 10, in: context))
        let frames = workspace.frames(in: context, focused: 10)
        #expect(frames[10] == CGRect(x: 750, y: 0, width: 250, height: 200))
        #expect(frames[13] == CGRect(x: 750, y: 600, width: 250, height: 200))
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 375, height: 800))
    }

    @Test func balanceWithoutFocusFitsEveryStrip() {
        let workspace = workspace(columns: [1, 2], rows: [10, 11, 12, 13])
        #expect(workspace.perform(.balance, focused: nil, in: context))
        let frames = workspace.frames(in: context, focused: nil)
        #expect(frames[10]?.height == 200)
        #expect(frames[1]?.width == 375)
    }

    @Test func stackInTheVerticalStripJoinsTheRowAboveAndUnstackPullsItOutBelow() {
        let workspace = workspace(columns: [1], rows: [10, 11])
        #expect(workspace.perform(.stack(.left), focused: 11, in: context))
        #expect(workspace.frames(in: context, focused: 10) == [
            1: CGRect(x: 0, y: 0, width: 375, height: 800),
            10: CGRect(x: 750, y: 0, width: 125, height: 400),
            11: CGRect(x: 875, y: 0, width: 125, height: 400),
        ])
        #expect(!workspace.perform(.stack(.left), focused: 10, in: context))
        #expect(workspace.perform(.unstack(.right), focused: 11, in: context))
        #expect(workspace.frames(in: context, focused: 10)[11] == CGRect(x: 750, y: 400, width: 250, height: 400))
    }

    @Test func columnWidthOfARowSetsItsHeightFraction() {
        let workspace = workspace(columns: [1], rows: [10, 11])
        #expect(workspace.perform(.columnWidth(.fraction(0.25)), focused: 10, in: context))
        #expect(workspace.frames(in: context, focused: 10)[10] == CGRect(x: 750, y: 0, width: 250, height: 200))
    }

    @Test func centreOfARowCentresItInTheVerticalZone() {
        let workspace = workspace(columns: [1], rows: [10, 11, 12])
        #expect(workspace.perform(.center, focused: 11, in: context))
        #expect(workspace.verticalScrollOffset == 200)
        #expect(workspace.scrollOffset == 0)
    }

    // MARK: Rotate

    @Test func rotateMovesEveryWindowOneSlotAlongColumnsThenRows() {
        let workspace = workspace(columns: [1, 2], rows: [10, 11])
        #expect(workspace.perform(.rotate(clockwise: true), focused: 1, in: context))
        #expect(workspace.windows == [11, 1, 2, 10])
        #expect(workspace.strip(of: 11) == .horizontal)
        #expect(workspace.strip(of: 2) == .vertical)
    }

    @Test func rotateCounterclockwiseMovesTheOtherWay() {
        let workspace = workspace(columns: [1, 2], rows: [10, 11])
        #expect(workspace.perform(.rotate(clockwise: false), focused: 1, in: context))
        #expect(workspace.windows == [2, 10, 11, 1])
    }

    @Test func rotateClockwiseThenCounterclockwiseIsTheIdentity() {
        let workspace = workspace(columns: [1, 2, 3], rows: [10, 11])
        _ = workspace.perform(.stack(.left), focused: 3, in: context)
        let before = workspace.frames(in: context, focused: 1)
        #expect(workspace.perform(.rotate(clockwise: true), focused: 1, in: context))
        #expect(workspace.perform(.rotate(clockwise: false), focused: 1, in: context))
        #expect(workspace.windows == [1, 2, 3, 10, 11])
        #expect(workspace.frames(in: context, focused: 1) == before)
    }

    @Test func rotateKeepsEachStackShareWithItsSlot() {
        let workspace = workspace(columns: [1, 2, 3])
        _ = workspace.perform(.stack(.left), focused: 3, in: context)
        _ = workspace.perform(.resize(.height, 80), focused: 2, in: context)
        #expect(workspace.perform(.rotate(clockwise: true), focused: 1, in: context))
        #expect(workspace.windows == [3, 1, 2])
        #expect(workspace.frames(in: context, focused: 3) == [
            3: CGRect(x: 0, y: 0, width: 500, height: 800),
            1: CGRect(x: 500, y: 0, width: 500, height: 480),
            2: CGRect(x: 500, y: 480, width: 500, height: 320),
        ])
    }

    @Test func rotateNeedsTwoWindows() {
        let workspace = workspace(columns: [1])
        #expect(!workspace.perform(.rotate(clockwise: true), focused: 1, in: context))
        let none = self.workspace(columns: [])
        #expect(!none.perform(.rotate(clockwise: false), focused: nil, in: context))
    }

    // MARK: Overview

    @Test func overviewShowsALongStripUnparkedWithTheVerticalStripAfterItsEnd() {
        let workspace = workspace(columns: [1, 2, 3, 4, 5], rows: [10, 11])
        let overview = workspace.overview(in: context, focused: 5)
        #expect(overview.frames == [
            1: CGRect(x: 0, y: 0, width: 375, height: 800),
            2: CGRect(x: 375, y: 0, width: 375, height: 800),
            3: CGRect(x: 750, y: 0, width: 375, height: 800),
            4: CGRect(x: 1125, y: 0, width: 375, height: 800),
            5: CGRect(x: 1500, y: 0, width: 375, height: 800),
            10: CGRect(x: 1875, y: 0, width: 250, height: 400),
            11: CGRect(x: 1875, y: 400, width: 250, height: 400),
        ])
        #expect(overview.viewports == [
            CGRect(x: 1125, y: 0, width: 750, height: 800),
            CGRect(x: 1875, y: 0, width: 250, height: 800),
        ])
    }

    @Test func overviewPutsAShortHorizontalStripNextToItsZoneAndTheVerticalStripOnItsSide() {
        let workspace = workspace(columns: [1, 2], rows: [10, 11])
        let overview = workspace.overview(in: context, focused: 1)
        #expect(overview.frames[2] == CGRect(x: 375, y: 0, width: 375, height: 800))
        #expect(overview.frames[10] == CGRect(x: 750, y: 0, width: 250, height: 400))
        #expect(overview.viewports == [
            CGRect(x: 0, y: 0, width: 750, height: 800),
            CGRect(x: 750, y: 0, width: 250, height: 800),
        ])
    }

    @Test func overviewWithTheVerticalZoneOnTheLeftKeepsItThere() {
        let workspace = workspace(columns: [1, 2, 3, 4], rows: [10], side: .left)
        let overview = workspace.overview(in: context, focused: 4)
        #expect(overview.frames[10] == CGRect(x: 0, y: 0, width: 250, height: 400))
        #expect(overview.frames[1] == CGRect(x: 250, y: 0, width: 375, height: 800))
        #expect(overview.frames[4] == CGRect(x: 1375, y: 0, width: 375, height: 800))
        #expect(overview.viewports == [
            CGRect(x: 1000, y: 0, width: 750, height: 800),
            CGRect(x: 0, y: 0, width: 250, height: 800),
        ])
    }

    @Test func overviewOfOneStripIsThatStripAndItsViewport() {
        let workspace = workspace(columns: [1, 2, 3])
        let overview = workspace.overview(in: context, focused: 3)
        #expect(overview.frames == [
            1: CGRect(x: 0, y: 0, width: 500, height: 800),
            2: CGRect(x: 500, y: 0, width: 500, height: 800),
            3: CGRect(x: 1000, y: 0, width: 500, height: 800),
        ])
        #expect(overview.viewports == [CGRect(x: 500, y: 0, width: 1000, height: 800)])
    }

    @Test func overviewDoesNotMoveTheStrips() {
        let workspace = workspace(columns: [1, 2, 3, 4], rows: [10, 11, 12])
        _ = workspace.overview(in: context, focused: 4)
        #expect(workspace.scrollOffset == 0)
        #expect(workspace.verticalScrollOffset == 0)
    }

    // MARK: Reload

    @Test func keepingAPreviousEngineKeepsBothStripsAndTheZoneWidth() {
        let old = workspace(columns: [1, 2, 3], rows: [10, 11])
        _ = old.perform(.resize(.width, 250), focused: 10, in: context)
        var changed = settings()
        changed.scrolling.defaultWidth = 0.25
        changed.scrolling.vertical.rowHeight = 0.25
        let reloaded = Workspace(ScrollingEngine(settings: changed, keeping: old.engine))
        #expect(reloaded.windows == [1, 2, 3, 10, 11])
        #expect(reloaded.strip(of: 10) == .vertical)
        #expect(reloaded.verticalWidth == 0.5)
        #expect(reloaded.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 250, height: 800),
            2: CGRect(x: 250, y: 0, width: 250, height: 800),
            3: CGRect(x: 4000, y: 3000, width: 250, height: 800),
            10: CGRect(x: 500, y: 0, width: 500, height: 400),
            11: CGRect(x: 500, y: 400, width: 500, height: 400),
        ])
        // New lanes use the new settings.
        reloaded.insert(12, after: 10)
        #expect(reloaded.frames(in: context, focused: 1)[12] == CGRect(x: 500, y: 400, width: 500, height: 200))
    }
}
