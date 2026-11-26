import CoreGraphics
import Testing
@testable import Core

// Viewport 1000x800, no gaps, default column width 0.5.
struct ScrollingTemplateTests {
    private let context = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1000, height: 800), gaps: Gaps())

    // A reference type, because #expect cannot call mutating methods on a value.
    private final class Box {
        // These tests are about widths; a lone column fills by default.
        var engine = ScrollingEngine(settings: {
            var settings = Settings()
            settings.scrolling.singleWindowFit = .keep
            return settings
        }())
        var windows: [WindowID] { engine.windows }
        func remove(_ window: WindowID) { engine.remove(window) }
        func templateError(_ template: SplitTemplate, focused: WindowID?) -> String? {
            engine.templateError(template, focused: focused)
        }
        func perform(_ command: LayoutCommand, focused: WindowID?, in context: LayoutContext) -> Bool {
            engine.perform(command, focused: focused, in: context)
        }
        func frames(in context: LayoutContext, focused: WindowID?) -> [WindowID: CGRect] {
            engine.frames(in: context, focused: focused)
        }
        func neighbor(of window: WindowID, _ direction: Direction, wrap: Bool, in context: LayoutContext) -> WindowID? {
            engine.neighbor(of: window, direction, wrap: wrap, in: context)
        }
    }

    private func engine(_ ids: [WindowID]) -> Box {
        let box = Box()
        var previous: WindowID?
        for id in ids {
            box.engine.insert(id, after: previous)
            previous = id
        }
        return box
    }

    @Test func twoPutsTheFocusedWindowAndTheNextOneSideBySide() {
        let engine = engine([1, 2, 3, 4])
        #expect(engine.perform(.applyTemplate(.two), focused: 2, in: context))
        let frames = engine.frames(in: context, focused: 2)
        #expect(frames[2] == CGRect(x: 0, y: 0, width: 500, height: 800))
        #expect(frames[3] == CGRect(x: 500, y: 0, width: 500, height: 800))
    }

    @Test func theGroupStartsEarlierWhenTooFewWindowsComeAfter() {
        let engine = engine([1, 2, 3, 4])
        #expect(engine.perform(.applyTemplate(.three), focused: 4, in: context))
        let frames = engine.frames(in: context, focused: 4)
        #expect(frames[2]?.minX == 0)
        #expect(frames[3]?.minX ?? 0 > 333 && frames[3]?.minX ?? 0 < 334)
        #expect(frames[4]?.maxX == 1000)
        #expect(engine.windows == [1, 2, 3, 4])
    }

    @Test func stackLeftFillsTheScreenWithTwoStackedAndOneTall() {
        let engine = engine([1, 2, 3])
        #expect(engine.perform(.applyTemplate(.stackLeft), focused: 1, in: context))
        let frames = engine.frames(in: context, focused: 1)
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 500, height: 400))
        #expect(frames[2] == CGRect(x: 0, y: 400, width: 500, height: 400))
        #expect(frames[3] == CGRect(x: 500, y: 0, width: 500, height: 800))
    }

    @Test func stackRightFillsTheScreenWithOneTallAndTwoStacked() {
        let engine = engine([1, 2, 3])
        #expect(engine.perform(.applyTemplate(.stackRight), focused: 1, in: context))
        let frames = engine.frames(in: context, focused: 1)
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 500, height: 800))
        #expect(frames[2] == CGRect(x: 500, y: 0, width: 500, height: 400))
        #expect(frames[3] == CGRect(x: 500, y: 400, width: 500, height: 400))
    }

    @Test func sixIsTwoRowsOfThree() {
        let engine = engine([1, 2, 3, 4, 5, 6])
        #expect(engine.perform(.applyTemplate(.six), focused: 1, in: context))
        let frames = engine.frames(in: context, focused: 1)
        #expect(frames[1]?.height == 400)
        #expect(frames[4]?.minY == 400)
        #expect(frames[6]?.maxX == 1000)
        #expect(frames[6]?.maxY == 800)
    }

    @Test func fiveStretchesTheLastRowToTheFullWidth() {
        let engine = engine([1, 2, 3, 4, 5])
        #expect(engine.perform(.applyTemplate(.five), focused: 1, in: context))
        let frames = engine.frames(in: context, focused: 1)
        #expect(frames[4] == CGRect(x: 0, y: 400, width: 500, height: 400))
        #expect(frames[5] == CGRect(x: 500, y: 400, width: 500, height: 400))
    }

    @Test func tooFewWindowsGiveAnErrorAndChangeNothing() {
        let engine = engine([1, 2])
        #expect(engine.templateError(.three, focused: 1) == "need at least 3 windows in the strip (it has 2)")
        #expect(!engine.perform(.applyTemplate(.three), focused: 1, in: context))
        #expect(engine.templateError(.two, focused: 1) == nil)
    }

    @Test func theSameTemplateAgainGoesBackToTheChain() {
        let engine = engine([1, 2, 3])
        _ = engine.perform(.applyTemplate(.stackLeft), focused: 1, in: context)
        #expect(engine.perform(.applyTemplate(.stackLeft), focused: 1, in: context))
        let frames = engine.frames(in: context, focused: 1)
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 500, height: 800))
        #expect(frames[2] == CGRect(x: 500, y: 0, width: 500, height: 800))
    }

    @Test func releaseTemplateGoesBackToTheChainAndFailsOutsideATemplate() {
        let engine = engine([1, 2, 3])
        #expect(!engine.perform(.releaseTemplate, focused: 1, in: context))
        _ = engine.perform(.applyTemplate(.three), focused: 1, in: context)
        #expect(engine.perform(.releaseTemplate, focused: 1, in: context))
        #expect(engine.frames(in: context, focused: 1)[2] == CGRect(x: 500, y: 0, width: 500, height: 800))
    }

    @Test func aDifferentTemplateReplacesTheFirstOne() {
        let engine = engine([1, 2, 3, 4])
        _ = engine.perform(.applyTemplate(.four), focused: 1, in: context)
        #expect(engine.perform(.applyTemplate(.two), focused: 1, in: context))
        let frames = engine.frames(in: context, focused: 1)
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 500, height: 800))
        #expect(frames[2] == CGRect(x: 500, y: 0, width: 500, height: 800))
    }

    @Test func focusMovesToTheAdjacentCellAndThenLeavesTheBlock() {
        let engine = engine([1, 2, 3, 4])
        _ = engine.perform(.applyTemplate(.stackLeft), focused: 1, in: context)
        #expect(engine.neighbor(of: 1, .down, wrap: false, in: context) == 2)
        #expect(engine.neighbor(of: 1, .right, wrap: false, in: context) == 3)
        #expect(engine.neighbor(of: 2, .right, wrap: false, in: context) == 3)
        #expect(engine.neighbor(of: 3, .left, wrap: false, in: context) == 1)
        #expect(engine.neighbor(of: 3, .right, wrap: false, in: context) == 4)
        #expect(engine.neighbor(of: 4, .left, wrap: false, in: context) == 3)
    }

    @Test func movingASwapsItWithTheAdjacentCell() {
        let engine = engine([1, 2, 3])
        _ = engine.perform(.applyTemplate(.stackLeft), focused: 1, in: context)
        #expect(engine.perform(.move(.down), focused: 1, in: context))
        let frames = engine.frames(in: context, focused: 1)
        #expect(frames[2] == CGRect(x: 0, y: 0, width: 500, height: 400))
        #expect(frames[1] == CGRect(x: 0, y: 400, width: 500, height: 400))
    }

    @Test func closingAWindowOfTheBlockBringsTheOthersBackToTheChain() {
        let engine = engine([1, 2, 3])
        _ = engine.perform(.applyTemplate(.three), focused: 1, in: context)
        engine.remove(2)
        let frames = engine.frames(in: context, focused: 1)
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 500, height: 800))
        #expect(frames[3]?.height == 800)
    }

    @Test func sendingAWindowOfTheBlockToTheOtherStripBreaksTheBlock() {
        let engine = engine([1, 2, 3])
        _ = engine.perform(.applyTemplate(.three), focused: 1, in: context)
        #expect(engine.perform(.sendToStrip(.vertical), focused: 2, in: context))
        #expect(engine.engine.strip(of: 2) == .vertical)
        // Every way out of the windows that stay works: the block no longer counts cells that it lost.
        for window: WindowID in [1, 3] {
            for direction in Direction.allCases {
                _ = engine.neighbor(of: window, direction, wrap: true, in: context)
                _ = engine.perform(.move(direction), focused: window, in: context)
            }
        }
        #expect(Set(engine.windows) == [1, 2, 3])
        #expect(engine.frames(in: context, focused: 1).count == 3)
    }

    @Test func stackingAndTabsDoNotApplyInsideATemplate() {
        let engine = engine([1, 2, 3])
        _ = engine.perform(.applyTemplate(.three), focused: 1, in: context)
        #expect(!engine.perform(.unstack(.right), focused: 1, in: context))
        #expect(!engine.perform(.toggleTabs, focused: 1, in: context))
        #expect(!engine.perform(.equalizeStack, focused: 1, in: context))
    }

    @Test func oneQuarterFillsAScreenWithTheBigWindowOnTheRight() {
        let box = engine([1, 2, 3])
        let applied = box.perform(.applyTemplate(.oneQuarter), focused: 1, in: context)
        #expect(applied)
        let frames = box.frames(in: context, focused: 1)
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 250, height: 800))
        #expect(frames[2] == CGRect(x: 250, y: 0, width: 750, height: 800))
    }

    @Test func aStackOutsideTheGroupStaysStacked() {
        let engine = engine([1, 2, 3, 4])
        #expect(engine.perform(.stack(.left), focused: 4, in: context))
        let before = engine.frames(in: context, focused: 1)
        #expect(engine.perform(.applyTemplate(.two), focused: 1, in: context))
        let frames = engine.frames(in: context, focused: 1)
        #expect(frames[3]?.minX == frames[4]?.minX)
        #expect(frames[3]?.height == before[3]?.height)
        #expect(frames[4]?.height == before[4]?.height)
    }

    @Test func aPatternNeverSplitsAStack() {
        let engine = engine([1, 2, 3, 4])
        #expect(engine.perform(.stack(.left), focused: 3, in: context))
        // Columns: [1] [2, 3] [4]. Two windows cannot be made from whole columns around window 4 or 1.
        #expect(engine.templateError(.two, focused: 4) != nil)
        #expect(!engine.perform(.applyTemplate(.two), focused: 4, in: context))
        #expect(engine.perform(.applyTemplate(.three), focused: 1, in: context))
    }

    @Test func theChainGivesBackTheColumnsThatThePatternTook() {
        let engine = engine([1, 2, 3, 4])
        #expect(engine.perform(.stack(.left), focused: 3, in: context))
        #expect(engine.perform(.columnWidth(.fraction(0.3)), focused: 4, in: context))
        let before = engine.frames(in: context, focused: 1)
        #expect(engine.perform(.applyTemplate(.three), focused: 1, in: context))
        #expect(engine.perform(.releaseTemplate, focused: 1, in: context))
        #expect(engine.frames(in: context, focused: 1) == before)
    }
}
