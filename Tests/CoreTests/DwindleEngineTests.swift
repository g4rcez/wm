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

    @Test func aPatternPlacesALoneWindowInItsFirstCell() {
        var engine = DwindleEngine(settings: Settings())
        engine.insert(1, after: nil)
        #expect(engine.templateError(.two, focused: 1) == nil)
        let applied = engine.perform(.applyTemplate(.two), focused: 1, in: context)
        #expect(applied)
        #expect(engine.frames(in: context, focused: 1) == [1: CGRect(x: 0, y: 0, width: 500, height: 600)])
        let released = engine.perform(.releaseTemplate, focused: 1, in: context)
        #expect(released)
        #expect(engine.frames(in: context, focused: 1) == [1: CGRect(x: 0, y: 0, width: 1000, height: 600)])
    }

    @Test func aWindowThatOpensInAColumnOfAPatternKeepsStacking() {
        var engine = DwindleEngine(settings: Settings())
        for id in 1...3 { engine.insert(WindowID(id), after: id == 1 ? nil : WindowID(id - 1)) }
        let columns = SplitTemplate(name: "30/40/30", cells: [
            CGRect(x: 0, y: 0, width: 0.3, height: 1), CGRect(x: 0.3, y: 0, width: 0.4, height: 1), CGRect(x: 0.7, y: 0, width: 0.3, height: 1),
        ])
        let applied = engine.perform(.applyTemplate(columns), focused: 1, in: context)
        #expect(applied)
        engine.insert(4, after: 3)
        engine.insert(5, after: 3)
        let frames = engine.frames(in: context, focused: 5)
        // Windows 3, 5 and 4 are three rows of the same column; nothing sits beside another one in it.
        #expect(Set([frames[3]!.minX, frames[4]!.minX, frames[5]!.minX]) == [700])
        #expect(Set([frames[3]!.width, frames[4]!.width, frames[5]!.width]) == [300])
    }

    @Test func theTilingFrameOfAnOpeningWindow() {
        let settings = Settings()
        #expect(tilingFrame(for: 1, among: [], after: nil, settings: settings, context: context) == CGRect(x: 0, y: 0, width: 1000, height: 600))
        #expect(tilingFrame(for: 2, among: [1], after: 1, settings: settings, context: context) == CGRect(x: 500, y: 0, width: 500, height: 600))
        // An anchor that is not there falls back to the last window.
        #expect(tilingFrame(for: 3, among: [1, 2], after: 9, settings: settings, context: context) != nil)
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

    @Test func balanceUndoesResizesOfEveryKindOnManyWindows() {
        var fresh = DwindleEngine(settings: Settings())
        for id in 1...4 { fresh.insert(WindowID(id), after: id == 1 ? nil : WindowID(id - 1)) }
        // The first layout decides which way each split goes, and a resize or balance keeps it.
        _ = fresh.frames(in: context, focused: nil)
        var engine = fresh
        _ = fresh.perform(.balance, focused: nil, in: context)
        var changes = 0
        for window in 1...4 as ClosedRange<WindowID> {
            for direction in [Direction.left, .right, .up, .down] {
                if engine.perform(.resizeEdge(direction, 40), focused: window, in: context) { changes += 1 }
            }
            if engine.perform(.resizeDirection(.right, 30), focused: window, in: context) { changes += 1 }
            if engine.perform(.resize(.height, 25), focused: window, in: context) { changes += 1 }
        }
        #expect(changes > 0)
        _ = engine.perform(.balance, focused: 2, in: context)
        let frames = engine.frames(in: context, focused: 2)
        #expect(frames == fresh.frames(in: context, focused: 2))
        #expect(frames.values.map { $0.width * $0.height } == [150_000, 150_000, 150_000, 150_000])
    }

    @Test func balanceNeedsNoWindowInFocus() {
        var engine = DwindleEngine(settings: Settings())
        engine.insert(1, after: nil)
        engine.insert(2, after: 1)
        _ = engine.perform(.resize(.width, 125), focused: 1, in: context)
        #expect(engine.perform(.balance, focused: nil, in: context) == true)
        #expect(engine.frames(in: context, focused: nil)[1] == CGRect(x: 0, y: 0, width: 500, height: 600))
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

    // MARK: resizeDirection

    @Test func directionMovesTheDividerSoTheLeftWindowGrowsAndTheRightOneShrinks() {
        var left = twoWindows()
        let ok51818 = left.perform(.resizeDirection(.right, 50), focused: 1, in: context)
        #expect(ok51818 == true)
        #expect(left.frames(in: context, focused: 1)[1] == CGRect(x: 0, y: 0, width: 550, height: 600))
        var right = twoWindows()
        let ok78036 = right.perform(.resizeDirection(.right, 50), focused: 2, in: context)
        #expect(ok78036 == true)
        #expect(right.frames(in: context, focused: 2)[2] == CGRect(x: 550, y: 0, width: 450, height: 600))
    }

    @Test func directionWorksOnTheOtherSideOfAScreenEdge() {
        var engine = twoWindows()
        let ok24192 = engine.perform(.resizeDirection(.left, 50), focused: 1, in: context)
        #expect(ok24192 == true)
        #expect(engine.frames(in: context, focused: 1)[1]?.width == 450)
    }

    @Test func directionOnTheInnerSplitMovesTheHorizontalDivider() {
        var engine = threeWindows()
        let ok76564 = engine.perform(.resizeDirection(.down, 60), focused: 3, in: context)
        #expect(ok76564 == true)
        #expect(engine.frames(in: context, focused: 3) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 600),
            2: CGRect(x: 500, y: 0, width: 500, height: 360),
            3: CGRect(x: 500, y: 360, width: 500, height: 240),
        ])
        var grow = threeWindows()
        let ok94560 = grow.perform(.resizeDirection(.left, 50), focused: 3, in: context)
        #expect(ok94560 == true)
        #expect(grow.frames(in: context, focused: 3)[3] == CGRect(x: 450, y: 300, width: 550, height: 300))
    }

    @Test func directionWithoutADividerOnThatAxisFails() {
        var single = DwindleEngine(settings: Settings())
        single.insert(1, after: nil)
        let ok45601 = single.perform(.resizeDirection(.right, 50), focused: 1, in: context)
        #expect(ok45601 == false)
        var engine = twoWindows()
        let ok72384 = engine.perform(.resizeDirection(.down, 50), focused: 1, in: context)
        #expect(ok72384 == false)
        let ok57515 = engine.perform(.resizeDirection(.right, 0), focused: 1, in: context)
        #expect(ok57515 == false)
    }

    @Test func aClampedRatioPassesToTheNextAncestor() {
        var engine = threeWindows()
        // Window 3: its horizontal ancestor is only the root. Push it to the limit, then the call is a no-op.
        let ok27789 = engine.perform(.resizeDirection(.right, 5000), focused: 1, in: context)
        #expect(ok27789 == true)
        let ok39421 = engine.perform(.resizeDirection(.right, 50), focused: 1, in: context)
        #expect(ok39421 == false)
        // Left of the root is clamped for window 1, and window 3 has no other horizontal ancestor.
        let ok86981 = engine.perform(.resizeDirection(.left, 50), focused: 3, in: context)
        #expect(ok86981 == true)
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
