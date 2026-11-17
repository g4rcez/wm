import CoreGraphics
import Testing
@testable import Core

// Viewport 1000x800, no gaps.
struct ScrollingFillTests {
    private let context = LayoutContext(
        viewport: CGRect(x: 0, y: 0, width: 1000, height: 800), gaps: Gaps(), hiddenCorner: CGPoint(x: 4000, y: 3000))

    private func engine(_ count: WindowID, _ configure: (inout Settings) -> Void = { _ in }) -> ScrollingEngine {
        var settings = Settings()
        settings.scrolling.singleWindowFit = .keep  // these tests are about widths; a lone column fills by default
        configure(&settings)
        var engine = ScrollingEngine(settings: settings)
        for id in 1...count { engine.insert(id, after: id == 1 ? nil : id - 1) }
        return engine
    }

    // MARK: single_window_fit

    @Test func aLoneColumnFillsTheScreenWithFit() {
        var engine = engine(1) { $0.scrolling.singleWindowFit = .fill }
        #expect(engine.frames(in: context, focused: 1) == [1: CGRect(x: 0, y: 0, width: 1000, height: 800)])
    }

    @Test func fitDoesNotChangeTwoColumns() {
        var engine = engine(2) { $0.scrolling.singleWindowFit = .fill }
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 800),
            2: CGRect(x: 500, y: 0, width: 500, height: 800),
        ])
    }

    @Test func aLoneColumnKeepsItsWidthWithKeep() {
        var engine = engine(1) { $0.scrolling.singleWindowFit = .keep }
        #expect(engine.frames(in: context, focused: 1) == [1: CGRect(x: 0, y: 0, width: 500, height: 800)])
    }

    @Test func aLoneColumnFillsTheScreenByDefault() {
        var engine = ScrollingEngine(settings: Settings())
        engine.insert(1, after: nil)
        #expect(engine.frames(in: context, focused: 1) == [1: CGRect(x: 0, y: 0, width: 1000, height: 800)])
    }

    @Test func aWidthThatYouSetIsKeptWhileTheColumnIsAlone() {
        var engine = engine(1) { $0.scrolling.singleWindowFit = .fill }
        let result1 = engine.perform(.columnWidth(.fraction(0.5)), focused: 1, in: context)
        #expect(result1)
        #expect(engine.frames(in: context, focused: 1) == [1: CGRect(x: 0, y: 0, width: 500, height: 800)])
    }

    @Test func matchingTheWidthAlsoMarksALoneColumn() {
        var engine = engine(1) { $0.scrolling.singleWindowFit = .fill }
        let result2 = engine.perform(.matchWidth, focused: 1, in: context)
        #expect(result2)
        #expect(engine.frames(in: context, focused: 1) == [1: CGRect(x: 0, y: 0, width: 500, height: 800)])
    }

    @Test func theChosenWidthSurvivesASecondColumnComingAndGoing() {
        var engine = engine(1) { $0.scrolling.singleWindowFit = .fill }
        _ = engine.perform(.columnWidth(.fraction(0.5)), focused: 1, in: context)
        engine.insert(2, after: 1)
        engine.remove(2)
        #expect(engine.frames(in: context, focused: 1) == [1: CGRect(x: 0, y: 0, width: 500, height: 800)])
    }

    @Test func aLoneColumnThatWasNeverSizedStillFills() {
        var engine = engine(2) { $0.scrolling.singleWindowFit = .fill }
        engine.remove(2)
        #expect(engine.frames(in: context, focused: 1) == [1: CGRect(x: 0, y: 0, width: 1000, height: 800)])
    }

    @Test func aResizeOfAFilledLoneColumnStartsFromItsShownWidth() {
        var engine = engine(1) { $0.scrolling.singleWindowFit = .fill }
        let result3 = engine.perform(.resize(.width, -100), focused: 1, in: context)
        #expect(result3)
        #expect(engine.frames(in: context, focused: 1) == [1: CGRect(x: 0, y: 0, width: 900, height: 800)])
    }

    // MARK: visible_columns

    @Test func twoColumnsGrowToFillTheScreenWhenThreeAreVisible() {
        var engine = engine(2) { $0.scrolling.visibleColumns = 3; $0.scrolling.defaultWidth = 0.3 }
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 800),
            2: CGRect(x: 500, y: 0, width: 500, height: 800),
        ])
    }

    @Test func columnsKeepTheirOwnWidthWhenTheCountIsReached() {
        var engine = engine(3) { $0.scrolling.visibleColumns = 3; $0.scrolling.defaultWidth = 0.3 }
        let frames = engine.frames(in: context, focused: 1)
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 300, height: 800))
        #expect(frames[3] == CGRect(x: 600, y: 0, width: 300, height: 800))
    }

    @Test func aLoneColumnIgnoresVisibleColumns() {
        var engine = engine(1) { $0.scrolling.visibleColumns = 3; $0.scrolling.defaultWidth = 0.3 }
        #expect(engine.frames(in: context, focused: 1) == [1: CGRect(x: 0, y: 0, width: 300, height: 800)])
    }

    @Test func resizingAGrownColumnMovesItsEdgeByTheAmountAsked() {
        var engine = engine(2) { $0.scrolling.visibleColumns = 3; $0.scrolling.defaultWidth = 0.3 }
        let resized = engine.perform(.resize(.width, 100), focused: 1, in: context)
        #expect(resized)
        let frames = engine.frames(in: context, focused: 1)
        let first = frames[1]!
        let second = frames[2]!
        #expect(abs(first.width - 600) < 0.01)
        #expect(abs(second.minX - 600) < 0.01)
        #expect(abs(second.width - 400) < 0.01)
    }

    // MARK: layout column expand

    @Test func aColumnGrowsIntoTheFreeRoomOnScreen() {
        var engine = engine(3) { $0.scrolling.defaultWidth = 0.3 }
        let expanded = engine.perform(.expandColumn, focused: 3, in: context)
        #expect(expanded)
        let frames = engine.frames(in: context, focused: 3)
        #expect(abs(frames[3]!.width - 400) < 0.01)
        #expect(frames[1]!.width == 300)
    }

    @Test func expandingAColumnThatAlreadyFillsTheRoomChangesNothing() {
        var engine = engine(2)
        let expanded = engine.perform(.expandColumn, focused: 2, in: context)
        #expect(!expanded)
    }
}
