import CoreGraphics
import Testing
@testable import Core

struct DwindleEngineTests {
    private let context = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1000, height: 600))

    // 1 | 2 over 3:
    //  1 | 2
    //    | 3
    private func threeWindows(_ settings: Settings = Settings()) -> DwindleEngine {
        var engine = DwindleEngine(settings: settings)
        engine.insert(1, after: nil)
        engine.insert(2, after: 1)
        engine.insert(3, after: 2)
        return engine
    }

    @Test func noWindowsNoFrames() {
        var engine = DwindleEngine(settings: Settings())
        #expect(engine.frames(in: context, focused: nil) == [:])
    }

    @Test func oneWindowFillsTheArea() {
        var engine = DwindleEngine(settings: Settings())
        engine.insert(1, after: nil)
        #expect(engine.frames(in: context, focused: 1) == [1: CGRect(x: 0, y: 0, width: 1000, height: 600)])
    }

    @Test func twoWindowsOnAWideScreenSitSideBySide() {
        var engine = DwindleEngine(settings: Settings())
        engine.insert(1, after: nil)
        engine.insert(2, after: 1)
        #expect(engine.frames(in: context, focused: 2) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 600),
            2: CGRect(x: 500, y: 0, width: 500, height: 600),
        ])
    }

    @Test func twoWindowsOnATallScreenAreStacked() {
        var engine = DwindleEngine(settings: Settings())
        engine.insert(1, after: nil)
        engine.insert(2, after: 1)
        let tall = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 600, height: 1000))
        #expect(engine.frames(in: tall, focused: 2) == [
            1: CGRect(x: 0, y: 0, width: 600, height: 500),
            2: CGRect(x: 0, y: 500, width: 600, height: 500),
        ])
    }

    @Test func threeWindowsSplitTheNewestCellAgain() {
        var engine = threeWindows()
        #expect(engine.windows == [1, 2, 3])
        #expect(engine.frames(in: context, focused: 3) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 600),
            2: CGRect(x: 500, y: 0, width: 500, height: 300),
            3: CGRect(x: 500, y: 300, width: 500, height: 300),
        ])
    }

    @Test func insertWithoutAnchorSplitsTheLastWindow() {
        var engine = threeWindows()
        engine.insert(4, after: nil)
        #expect(engine.windows == [1, 2, 3, 4])
        #expect(engine.frames(in: context, focused: 4) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 600),
            2: CGRect(x: 500, y: 0, width: 500, height: 300),
            3: CGRect(x: 500, y: 300, width: 250, height: 300),
            4: CGRect(x: 750, y: 300, width: 250, height: 300),
        ])
    }

    @Test func insertWithUnknownAnchorSplitsTheLastWindow() {
        var engine = threeWindows()
        engine.insert(4, after: 99)
        #expect(engine.windows == [1, 2, 3, 4])
    }

    @Test func insertAfterAnAnchorSplitsTheAnchorCell() {
        var engine = threeWindows()
        engine.insert(4, after: 1)
        #expect(engine.windows == [1, 4, 2, 3])
        #expect(engine.frames(in: context, focused: 4) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 300),
            4: CGRect(x: 0, y: 300, width: 500, height: 300),
            2: CGRect(x: 500, y: 0, width: 500, height: 300),
            3: CGRect(x: 500, y: 300, width: 500, height: 300),
        ])
    }

    @Test func removeGivesTheCellToTheSibling() {
        var engine = threeWindows()
        _ = engine.frames(in: context, focused: 3)
        engine.remove(2)
        #expect(engine.windows == [1, 3])
        #expect(engine.frames(in: context, focused: 3) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 600),
            3: CGRect(x: 500, y: 0, width: 500, height: 600),
        ])
    }

    @Test func removeKeepsTheOrientationOfTheRemainingSplit() {
        var engine = threeWindows()
        _ = engine.frames(in: context, focused: 3)
        engine.remove(1)
        #expect(engine.frames(in: context, focused: 3) == [
            2: CGRect(x: 0, y: 0, width: 1000, height: 300),
            3: CGRect(x: 0, y: 300, width: 1000, height: 300),
        ])
    }

    @Test func removeRecomputesTheOrientationWhenPreserveSplitIsOff() {
        var settings = Settings()
        settings.tiling.preserveSplit = false
        var engine = threeWindows(settings)
        _ = engine.frames(in: context, focused: 3)
        engine.remove(1)
        #expect(engine.frames(in: context, focused: 3) == [
            2: CGRect(x: 0, y: 0, width: 500, height: 600),
            3: CGRect(x: 500, y: 0, width: 500, height: 600),
        ])
    }

    @Test func removeTheLastWindowEmptiesTheEngine() {
        var engine = DwindleEngine(settings: Settings())
        engine.insert(1, after: nil)
        engine.remove(1)
        #expect(engine.windows == [])
        #expect(engine.frames(in: context, focused: nil) == [:])
    }

    @Test func splitRatioSettingSizesTheFirstWindow() {
        var settings = Settings()
        settings.tiling.splitRatio = 0.75
        var engine = DwindleEngine(settings: settings)
        engine.insert(1, after: nil)
        engine.insert(2, after: 1)
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 750, height: 600),
            2: CGRect(x: 750, y: 0, width: 250, height: 600),
        ])
    }

    @Test func splitRatioSettingIsClamped() {
        var settings = Settings()
        settings.tiling.splitRatio = 5
        var engine = DwindleEngine(settings: settings)
        engine.insert(1, after: nil)
        engine.insert(2, after: 1)
        #expect(engine.frames(in: context, focused: 1)[1] == CGRect(x: 0, y: 0, width: 900, height: 600))
    }

    @Test func gapsAreAppliedToEveryCell() {
        var engine = DwindleEngine(settings: Settings())
        engine.insert(1, after: nil)
        engine.insert(2, after: 1)
        let gapped = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1000, height: 600), gaps: Gaps(inner: 10, outer: 20))
        #expect(engine.frames(in: gapped, focused: 1) == [
            1: CGRect(x: 20, y: 20, width: 475, height: 560),
            2: CGRect(x: 505, y: 20, width: 475, height: 560),
        ])
    }

    @Test func moveSwapsWithTheNeighbour() {
        var engine = threeWindows()
        #expect(engine.perform(.move(.right), focused: 1, in: context) == true)
        #expect(engine.windows == [2, 1, 3])
        #expect(engine.frames(in: context, focused: 1) == [
            2: CGRect(x: 0, y: 0, width: 500, height: 600),
            1: CGRect(x: 500, y: 0, width: 500, height: 300),
            3: CGRect(x: 500, y: 300, width: 500, height: 300),
        ])
    }

    @Test func moveAtTheEdgeChangesNothing() {
        var engine = threeWindows()
        #expect(engine.perform(.move(.left), focused: 1, in: context) == false)
        #expect(engine.windows == [1, 2, 3])
    }

    @Test func resizeWidthGrowsTheFirstWindow() {
        var engine = threeWindows()
        #expect(engine.perform(.resize(.width, 125), focused: 1, in: context) == true)
        #expect(engine.frames(in: context, focused: 1)[1] == CGRect(x: 0, y: 0, width: 625, height: 600))
    }

    @Test func resizeWidthOfTheSecondChildShrinksTheFirst() {
        var engine = threeWindows()
        #expect(engine.perform(.resize(.width, 125), focused: 3, in: context) == true)
        #expect(engine.frames(in: context, focused: 3) == [
            1: CGRect(x: 0, y: 0, width: 375, height: 600),
            2: CGRect(x: 375, y: 0, width: 625, height: 300),
            3: CGRect(x: 375, y: 300, width: 625, height: 300),
        ])
    }

    @Test func resizeHeightUsesTheNearestStackedAncestor() {
        var engine = threeWindows()
        #expect(engine.perform(.resize(.height, 75), focused: 3, in: context) == true)
        #expect(engine.frames(in: context, focused: 3) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 600),
            2: CGRect(x: 500, y: 0, width: 500, height: 225),
            3: CGRect(x: 500, y: 225, width: 500, height: 375),
        ])
    }

    @Test func resizeHeightWithoutStackedAncestorChangesNothing() {
        var engine = threeWindows()
        #expect(engine.perform(.resize(.height, 75), focused: 1, in: context) == false)
    }

    @Test func resizeSmartUsesTheNearestAncestorOfAnyKind() {
        var engine = threeWindows()
        #expect(engine.perform(.resize(.smart, 75), focused: 3, in: context) == true)
        #expect(engine.frames(in: context, focused: 3)[2] == CGRect(x: 500, y: 0, width: 500, height: 225))
    }

    @Test func resizeIsLimitedToNinetyPercent() {
        var engine = threeWindows()
        #expect(engine.perform(.resize(.width, 5000), focused: 1, in: context) == true)
        #expect(engine.frames(in: context, focused: 1)[1] == CGRect(x: 0, y: 0, width: 900, height: 600))
        #expect(engine.perform(.resize(.width, 5000), focused: 1, in: context) == false)
    }

    @Test func balanceGivesEveryWindowTheSameSize() {
        let wide = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1200, height: 600))
        var engine = threeWindows()
        #expect(engine.perform(.balance, focused: 1, in: wide) == true)
        #expect(engine.frames(in: wide, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 400, height: 600),
            2: CGRect(x: 400, y: 0, width: 400, height: 600),
            3: CGRect(x: 800, y: 0, width: 400, height: 600),
        ])
    }

    @Test func balanceUndoesAResize() {
        var engine = DwindleEngine(settings: Settings())
        engine.insert(1, after: nil)
        engine.insert(2, after: 1)
        _ = engine.perform(.resize(.width, 125), focused: 1, in: context)
        #expect(engine.perform(.balance, focused: 1, in: context) == true)
        #expect(engine.frames(in: context, focused: 1)[1] == CGRect(x: 0, y: 0, width: 500, height: 600))
    }

    @Test func balanceOnABalancedLayoutChangesNothing() {
        var engine = DwindleEngine(settings: Settings())
        engine.insert(1, after: nil)
        engine.insert(2, after: 1)
        #expect(engine.perform(.balance, focused: 1, in: context) == false)
    }

    @Test func toggleSplitFlipsTheParentOrientation() {
        var engine = DwindleEngine(settings: Settings())
        engine.insert(1, after: nil)
        engine.insert(2, after: 1)
        #expect(engine.perform(.toggleSplit, focused: 1, in: context) == true)
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 1000, height: 300),
            2: CGRect(x: 0, y: 300, width: 1000, height: 300),
        ])
    }

    @Test func toggledSplitStaysPinnedWhenPreserveSplitIsOff() {
        var settings = Settings()
        settings.tiling.preserveSplit = false
        var engine = DwindleEngine(settings: settings)
        engine.insert(1, after: nil)
        engine.insert(2, after: 1)
        _ = engine.perform(.toggleSplit, focused: 1, in: context)
        _ = engine.frames(in: context, focused: 1)
        #expect(engine.frames(in: context, focused: 1)[2] == CGRect(x: 0, y: 300, width: 1000, height: 300))
    }

    @Test func toggleSplitNeedsAParent() {
        var engine = DwindleEngine(settings: Settings())
        engine.insert(1, after: nil)
        #expect(engine.perform(.toggleSplit, focused: 1, in: context) == false)
    }

    @Test func swapSplitSwapsTheChildrenOfTheParent() {
        var engine = DwindleEngine(settings: Settings())
        engine.insert(1, after: nil)
        engine.insert(2, after: 1)
        #expect(engine.perform(.swapSplit, focused: 1, in: context) == true)
        #expect(engine.windows == [2, 1])
        #expect(engine.frames(in: context, focused: 1) == [
            2: CGRect(x: 0, y: 0, width: 500, height: 600),
            1: CGRect(x: 500, y: 0, width: 500, height: 600),
        ])
    }

    @Test func swapSplitNeedsAParent() {
        var engine = DwindleEngine(settings: Settings())
        engine.insert(1, after: nil)
        #expect(engine.perform(.swapSplit, focused: 1, in: context) == false)
    }

    @Test func commandsForOtherLayoutsAreIgnored() {
        var engine = threeWindows()
        #expect(engine.perform(.columnWidth(.cycle), focused: 1, in: context) == false)
        #expect(engine.perform(.stack(.left), focused: 1, in: context) == false)
    }

    @Test func commandsNeedAFocusedWindowOfTheLayout() {
        var engine = threeWindows()
        #expect(engine.perform(.toggleSplit, focused: nil, in: context) == false)
        #expect(engine.perform(.toggleSplit, focused: 99, in: context) == false)
    }

    @Test func neighborFollowsTheGeometry() {
        var engine = threeWindows()
        #expect(engine.neighbor(of: 1, .right, wrap: false, in: context) == 2)
        #expect(engine.neighbor(of: 2, .down, wrap: false, in: context) == 3)
        #expect(engine.neighbor(of: 3, .left, wrap: false, in: context) == 1)
        #expect(engine.neighbor(of: 1, .left, wrap: false, in: context) == nil)
        #expect(engine.neighbor(of: 1, .left, wrap: true, in: context) == 2)
    }

    // MARK: resizeEdge

    private func twoWindows() -> DwindleEngine {
        var engine = DwindleEngine(settings: Settings())
        engine.insert(1, after: nil)
        engine.insert(2, after: 1)
        return engine
    }

    @Test func draggingTheRightEdgeOfTheLeftWindowWidensIt() {
        var engine = twoWindows()
        #expect(engine.perform(.resizeEdge(.right, 100), focused: 1, in: context) == true)
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 600, height: 600),
            2: CGRect(x: 600, y: 0, width: 400, height: 600),
        ])
    }

    @Test func draggingTheLeftEdgeOfTheRightWindowLeftWidensIt() {
        var engine = twoWindows()
        #expect(engine.perform(.resizeEdge(.left, 100), focused: 2, in: context) == true)
        #expect(engine.frames(in: context, focused: 2) == [
            1: CGRect(x: 0, y: 0, width: 400, height: 600),
            2: CGRect(x: 400, y: 0, width: 600, height: 600),
        ])
    }

    @Test func aNegativeEdgeDeltaNarrowsTheWindow() {
        var engine = twoWindows()
        #expect(engine.perform(.resizeEdge(.right, -100), focused: 1, in: context) == true)
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 400, height: 600),
            2: CGRect(x: 400, y: 0, width: 600, height: 600),
        ])
    }

    @Test func screenEdgesHaveNoDividerToDrag() {
        var engine = twoWindows()
        #expect(engine.perform(.resizeEdge(.left, 100), focused: 1, in: context) == false)
        #expect(engine.perform(.resizeEdge(.right, 100), focused: 2, in: context) == false)
        #expect(engine.perform(.resizeEdge(.up, 100), focused: 1, in: context) == false)
        #expect(engine.perform(.resizeEdge(.down, 100), focused: 2, in: context) == false)
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 600),
            2: CGRect(x: 500, y: 0, width: 500, height: 600),
        ])
    }

    @Test func theTopEdgeOfTheLowerWindowMovesTheInnerDivider() {
        var engine = threeWindows()
        #expect(engine.perform(.resizeEdge(.up, 60), focused: 3, in: context) == true)
        #expect(engine.frames(in: context, focused: 3) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 600),
            2: CGRect(x: 500, y: 0, width: 500, height: 240),
            3: CGRect(x: 500, y: 240, width: 500, height: 360),
        ])
    }

    @Test func theBottomEdgeOfTheUpperWindowMovesTheInnerDivider() {
        var engine = threeWindows()
        #expect(engine.perform(.resizeEdge(.down, 60), focused: 2, in: context) == true)
        #expect(engine.frames(in: context, focused: 2) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 600),
            2: CGRect(x: 500, y: 0, width: 500, height: 360),
            3: CGRect(x: 500, y: 360, width: 500, height: 240),
        ])
    }

    @Test func theLeftEdgeOfAnInnerWindowMovesTheOuterDivider() {
        var engine = threeWindows()
        #expect(engine.perform(.resizeEdge(.left, 100), focused: 3, in: context) == true)
        #expect(engine.frames(in: context, focused: 3) == [
            1: CGRect(x: 0, y: 0, width: 400, height: 600),
            2: CGRect(x: 400, y: 0, width: 600, height: 300),
            3: CGRect(x: 400, y: 300, width: 600, height: 300),
        ])
    }

    @Test func theRightEdgeOfTheLeftWindowMovesTheOuterDivider() {
        var engine = threeWindows()
        #expect(engine.perform(.resizeEdge(.right, 100), focused: 1, in: context) == true)
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 600, height: 600),
            2: CGRect(x: 600, y: 0, width: 400, height: 300),
            3: CGRect(x: 600, y: 300, width: 400, height: 300),
        ])
    }

    @Test func edgesOnTheScreenBorderOfANestedTreeReturnFalse() {
        var engine = threeWindows()
        #expect(engine.perform(.resizeEdge(.right, 100), focused: 3, in: context) == false)
        #expect(engine.perform(.resizeEdge(.right, 100), focused: 2, in: context) == false)
        #expect(engine.perform(.resizeEdge(.down, 100), focused: 3, in: context) == false)
        #expect(engine.perform(.resizeEdge(.up, 100), focused: 2, in: context) == false)
        #expect(engine.perform(.resizeEdge(.left, 100), focused: 1, in: context) == false)
        #expect(engine.perform(.resizeEdge(.up, 100), focused: 1, in: context) == false)
        #expect(engine.perform(.resizeEdge(.down, 100), focused: 1, in: context) == false)
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 600),
            2: CGRect(x: 500, y: 0, width: 500, height: 300),
            3: CGRect(x: 500, y: 300, width: 500, height: 300),
        ])
    }

    @Test func edgeDragsClampTheRatio() {
        var engine = twoWindows()
        #expect(engine.perform(.resizeEdge(.right, 5000), focused: 1, in: context) == true)
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 900, height: 600),
            2: CGRect(x: 900, y: 0, width: 100, height: 600),
        ])
        #expect(engine.perform(.resizeEdge(.right, 100), focused: 1, in: context) == false)
        #expect(engine.perform(.resizeEdge(.right, -5000), focused: 1, in: context) == true)
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 100, height: 600),
            2: CGRect(x: 100, y: 0, width: 900, height: 600),
        ])
    }

    @Test func aZeroEdgeDeltaChangesNothing() {
        var engine = twoWindows()
        #expect(engine.perform(.resizeEdge(.right, 0), focused: 1, in: context) == false)
    }

    @Test func edgeDragsNeedAManagedFocusedWindow() {
        var engine = twoWindows()
        #expect(engine.perform(.resizeEdge(.right, 100), focused: nil, in: context) == false)
        #expect(engine.perform(.resizeEdge(.right, 100), focused: 9, in: context) == false)
    }
}
