import CoreGraphics
import Testing
@testable import Core

// Viewport 1000x600, no gaps, default settings.
struct TilingTemplateTests {
    private let context = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1000, height: 600))

    private func engine(_ count: WindowID) -> DwindleEngine {
        var engine = DwindleEngine(settings: Settings())
        for id in 1...count { engine.insert(id, after: id == 1 ? nil : id - 1) }
        return engine
    }

    @Test func twoStackedOneBesideFillsTheScreen() {
        var engine = engine(3)
        let applied = engine.perform(.applyTemplate(.stackLeft), focused: 1, in: context)
        #expect(applied)
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 300),
            2: CGRect(x: 0, y: 300, width: 500, height: 300),
            3: CGRect(x: 500, y: 0, width: 500, height: 600),
        ])
    }

    @Test func fourInAGridTakeTheCellsInReadingOrder() {
        var engine = engine(4)
        let applied = engine.perform(.applyTemplate(.four), focused: 1, in: context)
        #expect(applied)
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 300),
            2: CGRect(x: 500, y: 0, width: 500, height: 300),
            3: CGRect(x: 0, y: 300, width: 500, height: 300),
            4: CGRect(x: 500, y: 300, width: 500, height: 300),
        ])
    }

    @Test func threeQuartersGivesTheFirstWindowTheBigCell() {
        var engine = engine(2)
        let applied = engine.perform(.applyTemplate(.threeQuarters), focused: 2, in: context)
        #expect(applied)
        #expect(engine.frames(in: context, focused: 2) == [
            1: CGRect(x: 0, y: 0, width: 750, height: 600),
            2: CGRect(x: 750, y: 0, width: 250, height: 600),
        ])
    }

    @Test func oneQuarterGivesTheBigCellToTheRightWindow() {
        var engine = engine(2)
        let applied = engine.perform(.applyTemplate(.oneQuarter), focused: 1, in: context)
        #expect(applied)
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 250, height: 600),
            2: CGRect(x: 250, y: 0, width: 750, height: 600),
        ])
    }

    @Test func aPatternKeepsItsShapeOnAWideScreenAndATallOne() {
        var engine = engine(2)
        _ = engine.perform(.applyTemplate(.threeQuarters), focused: 1, in: context)
        let tall = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 400, height: 800))
        #expect(engine.frames(in: tall, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 300, height: 800),
            2: CGRect(x: 300, y: 0, width: 100, height: 800),
        ])
    }

    @Test func aWrongNumberOfWindowsChangesNothing() {
        var engine = engine(4)
        let before = engine.frames(in: context, focused: 1)
        let applied = engine.perform(.applyTemplate(.stackLeft), focused: 1, in: context)
        #expect(!applied)
        #expect(engine.frames(in: context, focused: 1) == before)
        #expect(engine.templateError(.stackLeft, focused: 1) == "tile needs exactly 3 windows in this layout (the workspace has 4)")
        #expect(engine.templateError(.four, focused: 1) == nil)
    }

    @Test(arguments: SplitTemplate.allCases)
    func everyPatternFitsItsOwnNumberOfWindows(template: SplitTemplate) {
        var engine = engine(WindowID(template.count))
        let applied = engine.perform(.applyTemplate(template), focused: 1, in: context)
        #expect(applied)
        #expect(engine.frames(in: context, focused: 1).count == template.count)
    }

    @Test func chainGoesBackToTheAutomaticLayout() {
        var engine = engine(4)
        _ = engine.perform(.applyTemplate(.four), focused: 1, in: context)
        let released = engine.perform(.releaseTemplate, focused: 1, in: context)
        #expect(released)
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 600),
            2: CGRect(x: 500, y: 0, width: 500, height: 300),
            3: CGRect(x: 500, y: 300, width: 250, height: 300),
            4: CGRect(x: 750, y: 300, width: 250, height: 300),
        ])
    }

    @Test func rotateLayoutFlipsEverySplitAndFlipsBack() {
        // 1 | (2 over 3)  becomes  1 over (2 | 3), then goes back.
        var engine = engine(3)
        let flipped = engine.perform(.rotateLayout, focused: 3, in: context)
        #expect(flipped)
        #expect(engine.frames(in: context, focused: 3) == [
            1: CGRect(x: 0, y: 0, width: 1000, height: 300),
            2: CGRect(x: 0, y: 300, width: 500, height: 300),
            3: CGRect(x: 500, y: 300, width: 500, height: 300),
        ])
        let back = engine.perform(.rotateLayout, focused: 3, in: context)
        #expect(back)
        #expect(engine.frames(in: context, focused: 3) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 600),
            2: CGRect(x: 500, y: 0, width: 500, height: 300),
            3: CGRect(x: 500, y: 300, width: 500, height: 300),
        ])
    }

    @Test func rotateLayoutNeedsMoreThanOneWindow() {
        var engine = engine(1)
        let flipped = engine.perform(.rotateLayout, focused: 1, in: context)
        #expect(!flipped)
    }

    @Test func scrollingHasNoRotateLayout() {
        var engine = ScrollingEngine(settings: Settings())
        engine.insert(1, after: nil)
        engine.insert(2, after: 1)
        let flipped = engine.perform(.rotateLayout, focused: 1, in: context)
        #expect(!flipped)
    }
}
