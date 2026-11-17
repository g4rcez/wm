import CoreGraphics
import Testing
@testable import Core

// Viewport 1000x800, no gaps, default column width 0.5, sliver 8 points, parked height 0.9.
struct ScrollingEngineTests {
    private let context = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1000, height: 800), gaps: Gaps())

    // A reference type, because #expect cannot call mutating methods on a value.
    private final class Strip {
        var engine: ScrollingEngine
        init(_ engine: ScrollingEngine) { self.engine = engine }
        var windows: [WindowID] { engine.windows }
        var scrollOffset: CGFloat { engine.scrollOffset }
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
        func settle(in context: LayoutContext) -> WindowID? { engine.settle(in: context) }
    }

    private func engine(_ ids: [WindowID], center: CenterMode = .onOverflow, presets: [Double]? = nil) -> Strip {
        var settings = Settings()
        settings.scrolling.singleWindowFit = .keep  // these tests are about widths; a lone column fills by default
        settings.scrolling.center = center
        if let presets { settings.scrolling.presets = presets }
        var engine = ScrollingEngine(settings: settings)
        var previous: WindowID?
        for id in ids {
            engine.insert(id, after: previous)
            previous = id
        }
        return Strip(engine)
    }

    // MARK: Frames and scroll offset

    @Test func oneColumnFillsItsWidthAndTheFullHeight() {
        let engine = engine([1])
        #expect(engine.frames(in: context, focused: 1) == [1: CGRect(x: 0, y: 0, width: 500, height: 800)])
        #expect(engine.scrollOffset == 0)
    }

    @Test func twoColumnsFillTheViewportAndDoNotScroll() {
        let engine = engine([1, 2])
        #expect(engine.frames(in: context, focused: 2) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 800),
            2: CGRect(x: 500, y: 0, width: 500, height: 800),
        ])
        #expect(engine.scrollOffset == 0)
    }

    @Test func threeColumnsScrollToTheRightEdgeAndParkTheFirstOne() {
        let engine = engine([1, 2, 3])
        #expect(engine.frames(in: context, focused: 3) == [
            1: CGRect(x: -492, y: 40, width: 500, height: 720),
            2: CGRect(x: 0, y: 0, width: 500, height: 800),
            3: CGRect(x: 500, y: 0, width: 500, height: 800),
        ])
        #expect(engine.scrollOffset == 500)
    }

    @Test func focusingBackScrollsToTheLeftEdgeAndParksTheLastColumnOnTheRight() {
        let engine = engine([1, 2, 3])
        _ = engine.frames(in: context, focused: 3)
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 800),
            2: CGRect(x: 500, y: 0, width: 500, height: 800),
            3: CGRect(x: 992, y: 40, width: 500, height: 720),
        ])
        #expect(engine.scrollOffset == 0)
    }

    @Test func fourColumnsOffsetAfterFocusingEachOne() {
        let engine = engine([1, 2, 3, 4])
        _ = engine.frames(in: context, focused: 1)
        #expect(engine.scrollOffset == 0)
        _ = engine.frames(in: context, focused: 2)
        #expect(engine.scrollOffset == 0)
        _ = engine.frames(in: context, focused: 3)
        #expect(engine.scrollOffset == 750)
        _ = engine.frames(in: context, focused: 4)
        #expect(engine.scrollOffset == 1000)
    }

    @Test func fourColumnsFramesWhenTheThirdIsFocused() {
        let engine = engine([1, 2, 3, 4])
        #expect(engine.frames(in: context, focused: 3) == [
            1: CGRect(x: -492, y: 40, width: 500, height: 720),
            2: CGRect(x: -250, y: 0, width: 500, height: 800),
            3: CGRect(x: 250, y: 0, width: 500, height: 800),
            4: CGRect(x: 750, y: 0, width: 500, height: 800),
        ])
    }

    @Test func rightEdgeColumnsAreParkedWithOnlyASliverVisible() {
        let engine = engine([1, 2, 3, 4])
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 800),
            2: CGRect(x: 500, y: 0, width: 500, height: 800),
            3: CGRect(x: 992, y: 40, width: 500, height: 720),
            4: CGRect(x: 992, y: 40, width: 500, height: 720),
        ])
    }

    @Test func minimalShiftMovesOnlyByTheShortfall() {
        let engine = engine([1, 2, 3, 4], center: .never)
        _ = engine.frames(in: context, focused: 3)
        #expect(engine.scrollOffset == 500)
        _ = engine.frames(in: context, focused: 4)
        #expect(engine.scrollOffset == 1000)
    }

    @Test func minimalShiftKeepsTheOffsetWhenTheColumnIsAlreadyVisible() {
        let engine = engine([1, 2, 3, 4], center: .never)
        _ = engine.frames(in: context, focused: 4)
        _ = engine.frames(in: context, focused: 3)
        #expect(engine.scrollOffset == 1000)
    }

    @Test func onOverflowCentresOnlyWhenTheColumnIsNotFullyVisible() {
        let engine = engine([1, 2, 3, 4], center: .onOverflow)
        _ = engine.frames(in: context, focused: 2)
        #expect(engine.scrollOffset == 0)
        _ = engine.frames(in: context, focused: 3)
        #expect(engine.scrollOffset == 750)
    }

    @Test func alwaysCentresEvenBeyondTheStripEdge() {
        let engine = engine([1, 2, 3, 4], center: .always)
        #expect(engine.frames(in: context, focused: 1)[1] == CGRect(x: 250, y: 0, width: 500, height: 800))
        #expect(engine.scrollOffset == -250)
        _ = engine.frames(in: context, focused: 2)
        #expect(engine.scrollOffset == 250)
    }

    @Test func offsetIsClampedWhenTheStripShrinks() {
        let engine = engine([1, 2, 3, 4], center: .never)
        _ = engine.frames(in: context, focused: 4)
        engine.remove(3)
        engine.remove(4)
        #expect(engine.frames(in: context, focused: 2) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 800),
            2: CGRect(x: 500, y: 0, width: 500, height: 800),
        ])
        #expect(engine.scrollOffset == 0)
    }

    @Test func unknownFocusDoesNotMoveTheStrip() {
        let engine = engine([1, 2, 3, 4], center: .never)
        _ = engine.frames(in: context, focused: 3)
        _ = engine.frames(in: context, focused: nil)
        #expect(engine.scrollOffset == 500)
    }

    // MARK: Stacks and tabs

    @Test func stackedWindowsShareTheColumnHeight() {
        let engine = engine([1, 2])
        #expect(engine.perform(.stack(.left), focused: 2, in: context))
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 400),
            2: CGRect(x: 0, y: 400, width: 500, height: 400),
        ])
    }

    @Test func parkedStackKeepsItsStackHeights() {
        let engine = engine([1, 2, 3, 4])
        _ = engine.perform(.stack(.left), focused: 2, in: context)
        #expect(engine.frames(in: context, focused: 4) == [
            1: CGRect(x: -492, y: 0, width: 500, height: 400),
            2: CGRect(x: -492, y: 400, width: 500, height: 400),
            3: CGRect(x: 0, y: 0, width: 500, height: 800),
            4: CGRect(x: 500, y: 0, width: 500, height: 800),
        ])
    }

    @Test func tabbedColumnGivesEveryWindowTheFullFrame() {
        let engine = engine([1, 2, 3])
        _ = engine.perform(.stack(.left), focused: 2, in: context)
        #expect(engine.perform(.toggleTabs, focused: 1, in: context))
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 800),
            2: CGRect(x: 0, y: 0, width: 500, height: 800),
            3: CGRect(x: 500, y: 0, width: 500, height: 800),
        ])
    }

    @Test func togglingTabsTwiceRestoresTheStack() {
        let engine = engine([1, 2])
        _ = engine.perform(.stack(.left), focused: 2, in: context)
        _ = engine.perform(.toggleTabs, focused: 1, in: context)
        _ = engine.perform(.toggleTabs, focused: 1, in: context)
        #expect(engine.frames(in: context, focused: 1)[2] == CGRect(x: 0, y: 400, width: 500, height: 400))
    }

    // MARK: Maximize

    @Test func maximizeKeepsTheColumnInTheStripAndGivesItTheFullZone() {
        let engine = engine([1, 2, 3])
        #expect(engine.perform(.maximize, focused: 2, in: context))
        #expect(engine.windows == [1, 2, 3])
        #expect(engine.frames(in: context, focused: 2)[2] == CGRect(x: 0, y: 0, width: 1000, height: 800))
    }

    @Test func maximizeShowsAStackedWindowAtTheFullHeight() {
        let engine = engine([1, 2])
        _ = engine.perform(.stack(.left), focused: 2, in: context)
        #expect(engine.perform(.maximize, focused: 2, in: context))
        #expect(engine.frames(in: context, focused: 2)[2] == CGRect(x: 0, y: 0, width: 1000, height: 800))
    }

    @Test func maximizeTwiceRestoresSizeAndStack() {
        let engine = engine([1, 2])
        _ = engine.perform(.stack(.left), focused: 2, in: context)
        let before = engine.frames(in: context, focused: 2)
        _ = engine.perform(.maximize, focused: 2, in: context)
        _ = engine.perform(.maximize, focused: 2, in: context)
        #expect(engine.frames(in: context, focused: 2) == before)
    }

    @Test func movingFocusAfterMaximizeScrollsTheMaximizedColumnLikeAnyColumn() {
        let engine = engine([1, 2, 3])
        _ = engine.perform(.maximize, focused: 1, in: context)
        let frames = engine.frames(in: context, focused: 2)
        #expect(frames[1] == CGRect(x: -750, y: 0, width: 1000, height: 800))
        #expect(frames[2] == CGRect(x: 250, y: 0, width: 500, height: 800))
    }

    @Test func maximizeRefusesATemplateBlock() {
        let engine = engine([1, 2, 3])
        _ = engine.perform(.applyTemplate(.two), focused: 1, in: context)
        #expect(!engine.perform(.maximize, focused: 1, in: context))
    }

    // MARK: Insert and remove

    @Test func insertOpensARightHandColumnAfterTheAnchor() {
        let engine = engine([1, 2])
        engine.insert(3, after: 1)
        #expect(engine.windows == [1, 3, 2])
    }

    @Test func insertWithoutAnchorOrWithUnknownAnchorAppends() {
        let engine = engine([1, 2])
        engine.insert(3, after: nil)
        engine.insert(4, after: 99)
        #expect(engine.windows == [1, 2, 3, 4])
    }

    @Test func insertingAKnownWindowAgainChangesNothing() {
        let engine = engine([1, 2])
        engine.insert(1, after: 2)
        #expect(engine.windows == [1, 2])
    }

    @Test func removeDeletesTheWindowAndItsEmptyColumn() {
        let engine = engine([1, 2, 3])
        engine.remove(2)
        #expect(engine.windows == [1, 3])
        #expect(engine.frames(in: context, focused: 3) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 800),
            3: CGRect(x: 500, y: 0, width: 500, height: 800),
        ])
    }

    @Test func removeFromAStackKeepsTheColumnAndGivesTheHeightToTheRest() {
        let engine = engine([1, 2, 3])
        _ = engine.perform(.stack(.left), focused: 2, in: context)
        engine.remove(2)
        #expect(engine.frames(in: context, focused: 1)[1] == CGRect(x: 0, y: 0, width: 500, height: 800))
        #expect(engine.windows == [1, 3])
    }

    @Test func removeIgnoresUnknownWindows() {
        let engine = engine([1, 2])
        engine.remove(9)
        #expect(engine.windows == [1, 2])
    }

    // MARK: Commands

    @Test func moveHorizontallySwapsColumns() {
        let engine = engine([1, 2, 3])
        #expect(engine.perform(.move(.right), focused: 2, in: context))
        #expect(engine.windows == [1, 3, 2])
        #expect(engine.perform(.move(.left), focused: 2, in: context))
        #expect(engine.windows == [1, 2, 3])
    }

    @Test func moveAtTheEdgeDoesNothing() {
        let engine = engine([1, 2])
        #expect(!engine.perform(.move(.left), focused: 1, in: context))
        #expect(!engine.perform(.move(.right), focused: 2, in: context))
        #expect(engine.windows == [1, 2])
    }

    @Test func moveVerticallyReordersTheStack() {
        let engine = engine([1, 2])
        _ = engine.perform(.stack(.left), focused: 2, in: context)
        #expect(engine.perform(.move(.up), focused: 2, in: context))
        #expect(engine.windows == [2, 1])
        #expect(!engine.perform(.move(.up), focused: 2, in: context))
        #expect(engine.frames(in: context, focused: 2)[2] == CGRect(x: 0, y: 0, width: 500, height: 400))
    }

    @Test func resizeWidthChangesTheFocusedColumnByDeltaOverViewportWidth() {
        let engine = engine([1, 2])
        #expect(engine.perform(.resize(.width, 100), focused: 1, in: context))
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 600, height: 800),
            2: CGRect(x: 600, y: 0, width: 500, height: 800),
        ])
    }

    @Test func resizeSmartActsOnWidth() {
        let engine = engine([1, 2])
        #expect(engine.perform(.resize(.smart, -250), focused: 1, in: context))
        #expect(engine.frames(in: context, focused: 1)[1] == CGRect(x: 0, y: 0, width: 250, height: 800))
    }

    @Test func resizeWidthIsClamped() {
        let engine = engine([1])
        #expect(engine.perform(.resize(.width, 5000), focused: 1, in: context))
        #expect(engine.frames(in: context, focused: 1)[1] == CGRect(x: 0, y: 0, width: 1000, height: 800))
        #expect(!engine.perform(.resize(.width, 5000), focused: 1, in: context))
        #expect(engine.perform(.resize(.width, -5000), focused: 1, in: context))
        #expect(engine.frames(in: context, focused: 1)[1] == CGRect(x: 0, y: 0, width: 100, height: 800))
    }

    @Test func resizeHeightShiftsHeightToTheNeighbour() {
        let engine = engine([1, 2])
        _ = engine.perform(.stack(.left), focused: 2, in: context)
        #expect(engine.perform(.resize(.height, 80), focused: 1, in: context))
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 480),
            2: CGRect(x: 0, y: 480, width: 500, height: 320),
        ])
    }

    @Test func resizeHeightOfTheLastWindowTakesFromTheOneAbove() {
        let engine = engine([1, 2])
        _ = engine.perform(.stack(.left), focused: 2, in: context)
        #expect(engine.perform(.resize(.height, 80), focused: 2, in: context))
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 320),
            2: CGRect(x: 0, y: 320, width: 500, height: 480),
        ])
    }

    @Test func resizeHeightKeepsTenPercentForTheNeighbour() {
        let engine = engine([1, 2])
        _ = engine.perform(.stack(.left), focused: 2, in: context)
        #expect(engine.perform(.resize(.height, 10000), focused: 1, in: context))
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 720),
            2: CGRect(x: 0, y: 720, width: 500, height: 80),
        ])
    }

    @Test func resizeHeightNeedsAStack() {
        let engine = engine([1, 2])
        #expect(!engine.perform(.resize(.height, 50), focused: 1, in: context))
    }

    @Test func balanceFitsEveryColumnOnScreenAndKeepsStackHeights() {
        let engine = engine([1, 2, 3, 4])
        _ = engine.perform(.stack(.left), focused: 3, in: context)
        _ = engine.perform(.resize(.height, 80), focused: 2, in: context)
        _ = engine.perform(.columnWidth(.fraction(0.9)), focused: 1, in: context)
        #expect(engine.perform(.balance, focused: 1, in: context))
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 333.3333333333333, height: 800),
            2: CGRect(x: 333.3333333333333, y: 0, width: 333.3333333333333, height: 480),
            3: CGRect(x: 333.3333333333333, y: 480, width: 333.3333333333333, height: 320),
            4: CGRect(x: 666.6666666666666, y: 0, width: 333.3333333333333, height: 800),
        ])
        #expect(!engine.perform(.balance, focused: 1, in: context))
    }

    @Test func balanceOfFourColumnsGivesEachAQuarterOfTheScreen() {
        let engine = engine([1, 2, 3, 4])
        #expect(engine.perform(.balance, focused: 2, in: context))
        #expect(engine.frames(in: context, focused: 2) == [
            1: CGRect(x: 0, y: 0, width: 250, height: 800),
            2: CGRect(x: 250, y: 0, width: 250, height: 800),
            3: CGRect(x: 500, y: 0, width: 250, height: 800),
            4: CGRect(x: 750, y: 0, width: 250, height: 800),
        ])
    }

    @Test func balanceStopsAtTheMinimumWidthWhenThereAreTooManyColumns() {
        let engine = engine(Array(1...12))
        #expect(engine.perform(.balance, focused: 1, in: context))
        #expect(engine.frames(in: context, focused: 1)[1] == CGRect(x: 0, y: 0, width: 100, height: 800))
        #expect(engine.frames(in: context, focused: 1)[10] == CGRect(x: 900, y: 0, width: 100, height: 800))
    }

    @Test func balanceOfOneColumnFillsTheScreen() {
        let engine = engine([1])
        #expect(engine.perform(.balance, focused: 1, in: context))
        #expect(engine.frames(in: context, focused: 1)[1] == CGRect(x: 0, y: 0, width: 1000, height: 800))
    }

    @Test func matchWidthCopiesTheFocusedWidthToEveryColumn() {
        let engine = engine([1, 2, 3])
        _ = engine.perform(.columnWidth(.fraction(0.25)), focused: 3, in: context)
        #expect(engine.perform(.matchWidth, focused: 3, in: context))
        let frames = engine.frames(in: context, focused: 3)
        #expect(frames[1]?.width == 250)
        #expect(frames[2]?.width == 250)
        #expect(!engine.perform(.matchWidth, focused: 3, in: context))
    }

    @Test func equalizeStackEvensOnlyTheFocusedStack() {
        let engine = engine([1, 2, 3])
        _ = engine.perform(.stack(.left), focused: 2, in: context)
        _ = engine.perform(.resize(.height, 80), focused: 1, in: context)
        #expect(engine.perform(.equalizeStack, focused: 1, in: context))
        let frames = engine.frames(in: context, focused: 1)
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 500, height: 400))
        #expect(frames[2] == CGRect(x: 0, y: 400, width: 500, height: 400))
        #expect(!engine.perform(.equalizeStack, focused: 1, in: context))
    }

    // MARK: Mouse resize

    @Test func draggingEitherSideOfAColumnOutwardWidensIt() {
        let right = engine([1, 2])
        #expect(right.perform(.resizeEdge(.right, 100), focused: 1, in: context))
        #expect(right.frames(in: context, focused: 1)[1] == CGRect(x: 0, y: 0, width: 600, height: 800))
        let left = engine([1, 2])
        #expect(left.perform(.resizeEdge(.left, 100), focused: 2, in: context))
        #expect(left.frames(in: context, focused: 2)[2]?.width == 600)
    }

    @Test func draggingASideInwardNarrowsTheColumn() {
        let engine = engine([1, 2])
        #expect(engine.perform(.resizeEdge(.right, -200), focused: 1, in: context))
        #expect(engine.frames(in: context, focused: 1)[1] == CGRect(x: 0, y: 0, width: 300, height: 800))
    }

    @Test func draggingTheDividerInsideAStackMovesHeightBetweenTheTwoWindows() {
        let engine = engine([1, 2])
        _ = engine.perform(.stack(.left), focused: 2, in: context)
        #expect(engine.perform(.resizeEdge(.down, 80), focused: 1, in: context))
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 480),
            2: CGRect(x: 0, y: 480, width: 500, height: 320),
        ])
        #expect(engine.perform(.resizeEdge(.up, 80), focused: 2, in: context))
        #expect(engine.frames(in: context, focused: 2)[1]?.height == 400)
    }

    @Test func topOfTheFirstWindowAndBottomOfTheLastHaveNoDivider() {
        let engine = engine([1, 2])
        _ = engine.perform(.stack(.left), focused: 2, in: context)
        #expect(!engine.perform(.resizeEdge(.up, 50), focused: 1, in: context))
        #expect(!engine.perform(.resizeEdge(.down, 50), focused: 2, in: context))
        #expect(!engine.perform(.resizeEdge(.right, 0), focused: 1, in: context))
    }

    @Test func columnWidthFractionSetsTheWidth() {
        let engine = engine([1, 2])
        #expect(engine.perform(.columnWidth(.fraction(0.25)), focused: 2, in: context))
        #expect(engine.frames(in: context, focused: 1)[2] == CGRect(x: 500, y: 0, width: 250, height: 800))
        #expect(engine.perform(.columnWidth(.fraction(7)), focused: 2, in: context))
        #expect(engine.frames(in: context, focused: 2)[2]?.width == 1000)
    }

    @Test func columnWidthCycleWalksThePresetsAndWraps() {
        let engine = engine([1], presets: [0.25, 0.5, 1.0])
        #expect(engine.perform(.columnWidth(.cycle), focused: 1, in: context))
        #expect(engine.frames(in: context, focused: 1)[1]?.width == 1000)
        #expect(engine.perform(.columnWidth(.cycle), focused: 1, in: context))
        #expect(engine.frames(in: context, focused: 1)[1]?.width == 250)
        #expect(engine.perform(.columnWidth(.cycle), focused: 1, in: context))
        #expect(engine.frames(in: context, focused: 1)[1]?.width == 500)
    }

    @Test func stackMovesTheWindowToTheBottomOfTheLeftColumn() {
        let engine = engine([1, 2, 3])
        #expect(engine.perform(.stack(.left), focused: 3, in: context))
        #expect(engine.windows == [1, 2, 3])
        #expect(engine.frames(in: context, focused: 3) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 800),
            2: CGRect(x: 500, y: 0, width: 500, height: 400),
            3: CGRect(x: 500, y: 400, width: 500, height: 400),
        ])
    }

    @Test func stackInTheFirstColumnDoesNothing() {
        let engine = engine([1, 2])
        #expect(!engine.perform(.stack(.left), focused: 1, in: context))
    }

    @Test func unstackPutsTheWindowInItsOwnColumnOnTheRight() {
        let engine = engine([1, 2, 3])
        _ = engine.perform(.stack(.left), focused: 2, in: context)
        #expect(engine.perform(.unstack(.right), focused: 1, in: context))
        #expect(engine.windows == [2, 1, 3])
        #expect(engine.frames(in: context, focused: 2) == [
            2: CGRect(x: 0, y: 0, width: 500, height: 800),
            1: CGRect(x: 500, y: 0, width: 500, height: 800),
            3: CGRect(x: 992, y: 40, width: 500, height: 720),
        ])
    }

    @Test func unstackOfASingleWindowColumnDoesNothing() {
        let engine = engine([1, 2])
        #expect(!engine.perform(.unstack(.right), focused: 1, in: context))
    }

    @Test func centreIsOneShot() {
        let engine = engine([1, 2, 3, 4, 5], center: .never)
        #expect(engine.perform(.center, focused: 2, in: context))
        #expect(engine.frames(in: context, focused: 2)[2] == CGRect(x: 250, y: 0, width: 500, height: 800))
        #expect(engine.scrollOffset == 250)
        _ = engine.frames(in: context, focused: 3)
        #expect(engine.scrollOffset == 500)
    }

    @Test func scrollMovesTheViewAndHoldsUntilFocusChanges() {
        let engine = engine([1, 2, 3, 4], center: .never)
        _ = engine.frames(in: context, focused: 1)
        #expect(engine.perform(.scroll(600), focused: 1, in: context))
        #expect(engine.frames(in: context, focused: 1)[2] == CGRect(x: -100, y: 0, width: 500, height: 800))
        #expect(engine.scrollOffset == 600)
        _ = engine.frames(in: context, focused: 2)
        #expect(engine.scrollOffset == 500)
    }

    @Test func scrollIsClampedToTheStrip() {
        let engine = engine([1, 2, 3, 4])
        _ = engine.perform(.scroll(10000), focused: 1, in: context)
        #expect(engine.scrollOffset == 1000)
        _ = engine.perform(.scroll(-10000), focused: 1, in: context)
        #expect(engine.scrollOffset == 0)
    }

    @Test func anyOtherCommandEndsTheManualScroll() {
        let engine = engine([1, 2, 3, 4], center: .never)
        _ = engine.perform(.scroll(600), focused: 1, in: context)
        _ = engine.perform(.balance, focused: 1, in: context)
        _ = engine.frames(in: context, focused: 1)
        #expect(engine.scrollOffset == 0)
    }

    @Test func commandsOfOtherLayoutsAreIgnored() {
        let engine = engine([1, 2])
        #expect(!engine.perform(.toggleSplit, focused: 1, in: context))
        #expect(!engine.perform(.swapSplit, focused: 1, in: context))
        #expect(!engine.perform(.balance, focused: nil, in: context))
    }

    // MARK: Neighbours

    // Columns: [1, 2] [3] [4, 5]
    private func neighborEngine() -> Strip {
        let engine = engine([1, 2, 3, 4, 5])
        _ = engine.perform(.stack(.left), focused: 2, in: context)
        _ = engine.perform(.stack(.left), focused: 5, in: context)
        return engine
    }

    @Test func horizontalNeighborKeepsTheStackIndexOrTakesTheLastWindow() {
        let engine = neighborEngine()
        #expect(engine.neighbor(of: 2, .right, wrap: false, in: context) == 3)
        #expect(engine.neighbor(of: 3, .left, wrap: false, in: context) == 1)
        #expect(engine.neighbor(of: 3, .right, wrap: false, in: context) == 4)
        #expect(engine.neighbor(of: 5, .left, wrap: false, in: context) == 3)
        #expect(engine.neighbor(of: 2, .left, wrap: false, in: context) == nil)
    }

    @Test func verticalNeighborMovesInsideTheStack() {
        let engine = neighborEngine()
        #expect(engine.neighbor(of: 1, .down, wrap: false, in: context) == 2)
        #expect(engine.neighbor(of: 2, .up, wrap: false, in: context) == 1)
        #expect(engine.neighbor(of: 1, .up, wrap: false, in: context) == nil)
        #expect(engine.neighbor(of: 2, .down, wrap: false, in: context) == nil)
        #expect(engine.neighbor(of: 3, .down, wrap: false, in: context) == nil)
    }

    @Test func neighborWrapsToTheOtherEnd() {
        let engine = neighborEngine()
        #expect(engine.neighbor(of: 5, .right, wrap: true, in: context) == 2)
        #expect(engine.neighbor(of: 1, .left, wrap: true, in: context) == 4)
        #expect(engine.neighbor(of: 1, .up, wrap: true, in: context) == 2)
        #expect(engine.neighbor(of: 2, .down, wrap: true, in: context) == 1)
    }

    @Test func neighborOfAnUnknownWindowIsNil() {
        let engine = neighborEngine()
        #expect(engine.neighbor(of: 99, .right, wrap: true, in: context) == nil)
    }

    @Test func neighborDoesNotMoveTheStrip() {
        let engine = engine([1, 2, 3, 4], center: .never)
        _ = engine.frames(in: context, focused: 1)
        _ = engine.neighbor(of: 1, .right, wrap: false, in: context)
        #expect(engine.scrollOffset == 0)
    }

    // MARK: Settle

    @Test func settleReturnsTheColumnNearestTheCentreAndEndsTheScroll() {
        let engine = engine([1, 2, 3, 4], center: .never)
        _ = engine.frames(in: context, focused: 1)
        _ = engine.perform(.scroll(600), focused: 1, in: context)
        #expect(engine.settle(in: context) == 3)
        #expect(engine.settle(in: context) == nil)
        // The caller focuses window 3, and the strip shows it.
        #expect(engine.frames(in: context, focused: 3)[3] == CGRect(x: 400, y: 0, width: 500, height: 800))
    }

    @Test func settleReturnsTheFirstWindowOfAStackedColumn() {
        let engine = engine([1, 2, 3, 4], center: .never)
        _ = engine.perform(.stack(.left), focused: 3, in: context)
        _ = engine.frames(in: context, focused: 1)
        _ = engine.perform(.scroll(300), focused: 1, in: context)
        #expect(engine.settle(in: context) == 2)
    }

    @Test func settleWithoutAManualScrollDoesNothing() {
        let engine = engine([1, 2, 3])
        _ = engine.frames(in: context, focused: 1)
        #expect(engine.settle(in: context) == nil)
    }

    // MARK: Gaps

    @Test func gapsLeaveOuterAtTheEdgesAndInnerBetweenWindows() {
        let gapped = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1000, height: 800), gaps: Gaps(inner: 10, outer: 20))
        let engine = engine([1, 2])
        #expect(engine.frames(in: gapped, focused: 1) == [
            1: CGRect(x: 20, y: 20, width: 475, height: 760),
            2: CGRect(x: 505, y: 20, width: 475, height: 760),
        ])
    }

    @Test func gapsApplyBetweenStackedWindows() {
        let gapped = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1000, height: 800), gaps: Gaps(inner: 10, outer: 20))
        let engine = engine([1, 2])
        _ = engine.perform(.stack(.left), focused: 2, in: gapped)
        #expect(engine.frames(in: gapped, focused: 1) == [
            1: CGRect(x: 20, y: 20, width: 475, height: 375),
            2: CGRect(x: 20, y: 405, width: 475, height: 375),
        ])
    }

    @Test func gapsKeepScrollingAndParkingInsideTheTilingArea() {
        let gapped = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1000, height: 800), gaps: Gaps(inner: 10, outer: 20))
        let engine = engine([1, 2, 3])
        #expect(engine.frames(in: gapped, focused: 3) == [
            1: CGRect(x: -467, y: 40, width: 475, height: 720),
            2: CGRect(x: 20, y: 20, width: 475, height: 760),
            3: CGRect(x: 505, y: 20, width: 475, height: 760),
        ])
        #expect(engine.scrollOffset == 485)
    }
}
