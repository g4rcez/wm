import CoreGraphics
import Testing
@testable import Core

// Viewport 1000x800, no gaps.
struct ScrollingOptionsTests {
    private let context = LayoutContext(
        viewport: CGRect(x: 0, y: 0, width: 1000, height: 800), gaps: Gaps(), hiddenCorner: CGPoint(x: 4000, y: 3000))

    private func engine(_ count: WindowID, _ configure: (inout Settings) -> Void = { _ in }) -> ScrollingEngine {
        var settings = Settings()
        configure(&settings)
        var engine = ScrollingEngine(settings: settings)
        for id in 1...count { engine.insert(id, after: id == 1 ? nil : id - 1) }
        return engine
    }

    @Test func aLoneColumnSitsAtTheStartByDefault() {
        var engine = engine(1) { $0.scrolling.center = .never }
        #expect(engine.frames(in: context, focused: 1) == [1: CGRect(x: 0, y: 0, width: 500, height: 800)])
    }

    @Test func alwaysCenterSingleColumnCentersALoneColumn() {
        var engine = engine(1) { $0.scrolling.center = .never; $0.scrolling.alwaysCenterSingleColumn = true }
        #expect(engine.frames(in: context, focused: 1) == [1: CGRect(x: 250, y: 0, width: 500, height: 800)])
    }

    @Test func alwaysCenterSingleColumnLeavesTwoColumnsAlone() {
        var engine = engine(2) { $0.scrolling.center = .never; $0.scrolling.alwaysCenterSingleColumn = true }
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 800),
            2: CGRect(x: 500, y: 0, width: 500, height: 800),
        ])
    }

    @Test func aNewColumnIsNormalByDefault() {
        var engine = engine(2)
        let joined = engine.perform(.stack, focused: 2, in: context)
        #expect(joined)
        #expect(engine.tabs(of: 1) == nil)
    }

    @Test func aNewColumnCanBeTabbedByDefault() {
        var engine = engine(2) { $0.scrolling.defaultColumnDisplay = .tabbed }
        let joined = engine.perform(.stack, focused: 2, in: context)
        #expect(joined)
        #expect(engine.tabs(of: 1) == [1, 2])
        #expect(engine.tabs(of: 2) == [1, 2])
    }

    @Test func centerVisibleCentersTheColumnsThatAreFullyOnScreen() {
        // Five columns of 300: columns 1, 2, 3 are fully on screen (0...900). The block is moved 50 to the right.
        var engine = engine(5) { $0.scrolling.defaultWidth = 0.3 }
        _ = engine.frames(in: context, focused: 1)
        let moved = engine.perform(.centerVisible, focused: 1, in: context)
        #expect(moved)
        #expect(engine.scrollOffset == -50)
        #expect(engine.frames(in: context, focused: 1)[1] == CGRect(x: 50, y: 0, width: 300, height: 800))
    }

    // Three windows in one column of height 800.
    private func stack(_ configure: (inout Settings) -> Void = { _ in }) -> ScrollingEngine {
        var engine = engine(3, configure)
        _ = engine.perform(.stack, focused: 2, in: context)
        _ = engine.perform(.stack, focused: 3, in: context)
        return engine
    }

    @Test func windowHeightGivesTheWindowItsShareAndTheOthersTheRest() {
        var engine = stack()
        let changed = engine.perform(.windowHeight(.fraction(0.5)), focused: 1, in: context)
        #expect(changed)
        let frames = engine.frames(in: context, focused: 1)
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 500, height: 400))
        #expect(frames[2] == CGRect(x: 0, y: 400, width: 500, height: 200))
        #expect(frames[3] == CGRect(x: 0, y: 600, width: 500, height: 200))
    }

    @Test func windowHeightCyclesThroughThePresetsAndWraps() {
        var engine = stack { $0.scrolling.presetHeights = [0.5, 0.75] }
        let first = engine.perform(.windowHeight(.cycle), focused: 1, in: context)
        #expect(first)
        #expect(engine.frames(in: context, focused: 1)[1]?.height == 400)
        let second = engine.perform(.windowHeight(.cycle), focused: 1, in: context)
        #expect(second)
        let frames = engine.frames(in: context, focused: 1)
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 500, height: 600))
        #expect(frames[2] == CGRect(x: 0, y: 600, width: 500, height: 100))
        let third = engine.perform(.windowHeight(.cycle), focused: 1, in: context)
        #expect(third)
        #expect(engine.frames(in: context, focused: 1)[1]?.height == 400)
    }

    @Test func windowHeightRefusesASizeThatSqueezesTheOthersTooMuch() {
        var engine = stack()
        let changed = engine.perform(.windowHeight(.fraction(0.95)), focused: 1, in: context)
        #expect(!changed)
    }

    @Test func windowHeightNeedsAStack() {
        var engine = engine(2)
        let changed = engine.perform(.windowHeight(.fraction(0.5)), focused: 1, in: context)
        #expect(!changed)
    }
}
