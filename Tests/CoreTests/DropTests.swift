import CoreGraphics
import Testing
@testable import Core

// Viewport 1000x600, no gaps.
struct DropZoneTests {
    private let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
    private let tiles: [WindowID: CGRect] = [
        1: CGRect(x: 0, y: 0, width: 500, height: 600),
        2: CGRect(x: 500, y: 0, width: 500, height: 600),
    ]

    @Test func theSidesOfAWindowAndItsMiddle() {
        #expect(DropZone.find(pointer: CGPoint(x: 560, y: 300), dragged: 1, tiles: tiles, area: area) == .beside(2, .left))
        #expect(DropZone.find(pointer: CGPoint(x: 940, y: 300), dragged: 1, tiles: tiles, area: area) == .beside(2, .right))
        #expect(DropZone.find(pointer: CGPoint(x: 750, y: 60), dragged: 1, tiles: tiles, area: area) == .beside(2, .up))
        #expect(DropZone.find(pointer: CGPoint(x: 750, y: 550), dragged: 1, tiles: tiles, area: area) == .beside(2, .down))
        #expect(DropZone.find(pointer: CGPoint(x: 750, y: 300), dragged: 1, tiles: tiles, area: area) == .middle(2))
    }

    @Test func theDraggedWindowIsNoTarget() {
        #expect(DropZone.find(pointer: CGPoint(x: 250, y: 300), dragged: 1, tiles: tiles, area: area) == .none)
    }

    @Test func anEdgeOfTheScreenComesFirst() {
        #expect(DropZone.find(pointer: CGPoint(x: 995, y: 300), dragged: 1, tiles: tiles, area: area) == .screenEdge(.right))
        #expect(DropZone.find(pointer: CGPoint(x: 400, y: 4), dragged: 2, tiles: tiles, area: area) == .screenEdge(.up))
        #expect(DropZone.find(pointer: CGPoint(x: -5, y: 300), dragged: 2, tiles: tiles, area: area) == .screenEdge(.left))
    }

    @Test func overTwoWindowsTheSmallerOneIsTheTarget() {
        var stacked = tiles
        stacked[3] = CGRect(x: 600, y: 200, width: 200, height: 200)
        #expect(DropZone.find(pointer: CGPoint(x: 700, y: 300), dragged: 1, tiles: stacked, area: area) == .middle(3))
    }
}

struct DropPlanTests {
    private let context = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1000, height: 600))

    private func filled(_ engine: any LayoutEngine, _ ids: [WindowID]) -> any LayoutEngine {
        var copy = engine
        for id in ids { copy.insert(id, after: copy.windows.last) }
        _ = copy.frames(in: context, focused: ids.first)
        return copy
    }

    private func frames(_ engine: (any LayoutEngine)?) -> [WindowID: CGRect] {
        guard var engine else { return [:] }
        return engine.frames(in: context, focused: nil)
    }

    @Test func tilingOpensASpaceOnTheSideOfTheTarget() {
        // 1 | 2 over 3. Window 3 dropped on the left side of 1.
        let engine = filled(DwindleEngine(settings: Settings()), [1, 2, 3])
        let after = frames(DropPlan.apply(.beside(1, .left), dragged: 3, to: engine, in: context))
        #expect(after[3]!.minX == 0)
        #expect(after[3]!.maxX == after[1]!.minX)
        #expect(after[3]!.height == after[1]!.height)
    }

    @Test func tilingOpensASpaceAboveTheTarget() {
        let engine = filled(DwindleEngine(settings: Settings()), [1, 2])
        let after = frames(DropPlan.apply(.beside(1, .up), dragged: 2, to: engine, in: context))
        #expect(after[2] == CGRect(x: 0, y: 0, width: 1000, height: 300))
        #expect(after[1] == CGRect(x: 0, y: 300, width: 1000, height: 300))
    }

    @Test func tilingScreenEdgeTakesTheWholeSide() {
        let engine = filled(DwindleEngine(settings: Settings()), [1, 2, 3])
        let after = frames(DropPlan.apply(.screenEdge(.down), dragged: 1, to: engine, in: context))
        #expect(after[1]!.width == 1000)
        #expect(after[1]!.maxY == 600)
    }

    @Test func theMiddleSwapsInEveryLayout() {
        for engine in [filled(DwindleEngine(settings: Settings()), [1, 2]), filled(ScrollingEngine(settings: Settings()), [1, 2]),
                       filled(MasterEngine(settings: Settings()), [1, 2])] {
            let before = frames(engine)
            let after = frames(DropPlan.apply(.middle(2), dragged: 1, to: engine, in: context))
            #expect(after[1] == before[2] && after[2] == before[1], "\(type(of: engine))")
        }
    }

    @Test func scrollingMakesAColumnBeforeOrAfterTheTarget() throws {
        let engine = filled(ScrollingEngine(settings: Settings()), [1, 2, 3])
        let left = try #require(DropPlan.apply(.beside(2, .left), dragged: 3, to: engine, in: context) as? ScrollingEngine)
        #expect(left.lanes(of: .horizontal) == [[1], [3], [2]])
        let right = try #require(DropPlan.apply(.beside(1, .right), dragged: 3, to: engine, in: context) as? ScrollingEngine)
        #expect(right.lanes(of: .horizontal) == [[1], [3], [2]])
    }

    @Test func scrollingStacksAboveOrBelowTheTarget() throws {
        let engine = filled(ScrollingEngine(settings: Settings()), [1, 2, 3])
        let below = try #require(DropPlan.apply(.beside(1, .down), dragged: 3, to: engine, in: context) as? ScrollingEngine)
        #expect(below.lanes(of: .horizontal) == [[1, 3], [2]])
        let above = try #require(DropPlan.apply(.beside(1, .up), dragged: 3, to: engine, in: context) as? ScrollingEngine)
        #expect(above.lanes(of: .horizontal) == [[3, 1], [2]])
    }

    @Test func scrollingScreenEdgeIsTheFirstOrLastColumn() throws {
        let engine = filled(ScrollingEngine(settings: Settings()), [1, 2, 3])
        let first = try #require(DropPlan.apply(.screenEdge(.left), dragged: 3, to: engine, in: context) as? ScrollingEngine)
        #expect(first.lanes(of: .horizontal) == [[3], [1], [2]])
        let last = try #require(DropPlan.apply(.screenEdge(.right), dragged: 1, to: engine, in: context) as? ScrollingEngine)
        #expect(last.lanes(of: .horizontal) == [[2], [3], [1]])
    }

    @Test func masterMovesTheWindowInTheOrder() {
        let engine = filled(MasterEngine(settings: Settings()), [1, 2, 3])
        // New windows go after the masters, so the order is 1, 3, 2.
        #expect(engine.windows == [1, 3, 2])
        #expect(DropPlan.apply(.beside(2, .down), dragged: 1, to: engine, in: context)?.windows == [3, 2, 1])
        #expect(DropPlan.apply(.beside(3, .up), dragged: 2, to: engine, in: context)?.windows == [1, 2, 3])
        #expect(DropPlan.apply(.screenEdge(.left), dragged: 2, to: engine, in: context)?.windows == [2, 1, 3])
    }

    @Test func noTargetAndMonocleChangeNothing() {
        let engine = filled(DwindleEngine(settings: Settings()), [1, 2])
        #expect(DropPlan.apply(.none, dragged: 1, to: engine, in: context) == nil)
        #expect(DropPlan.apply(.beside(1, .left), dragged: 1, to: engine, in: context) == nil)
        #expect(DropPlan.apply(.middle(2), dragged: 1, to: filled(MonocleEngine(settings: Settings()), [1, 2]), in: context) == nil)
    }

    @Test func theEngineThatWasPassedIsNotChanged() {
        let engine = filled(DwindleEngine(settings: Settings()), [1, 2, 3])
        let before = frames(engine)
        _ = DropPlan.apply(.beside(1, .left), dragged: 3, to: engine, in: context)
        #expect(frames(engine) == before)
    }
}
