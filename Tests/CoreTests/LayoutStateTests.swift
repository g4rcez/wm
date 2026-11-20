import CoreGraphics
import Foundation
import Testing
@testable import Core

// A layout is saved as JSON and built again by the next daemon. Viewport 1000x600 (tiling) and 1000x800 (scrolling),
// no gaps, default settings.
struct LayoutStateTests {
    private let tilingContext = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1000, height: 600))
    private let scrollingContext = LayoutContext(
        viewport: CGRect(x: 0, y: 0, width: 1000, height: 800), gaps: Gaps(), hiddenCorner: CGPoint(x: 4000, y: 3000))

    private func restored(_ engine: some LayoutEngine) throws -> any LayoutEngine {
        let data = try JSONEncoder().encode(engine.state)
        return makeEngine(restoring: try JSONDecoder().decode(LayoutState.self, from: data), settings: Settings())
    }

    @Test func aFloatingLayoutIsSavedAsFloating() throws {
        var engine = DwindleEngine(settings: Settings())
        engine.insert(1, after: nil)
        guard case .tiling(let state) = engine.state else { Issue.record("a dwindle engine saves as tiling"); return }
        let data = try JSONEncoder().encode(LayoutState.floating(state))
        let saved = try JSONDecoder().decode(LayoutState.self, from: data)
        #expect(saved.kind == .floating)
        #expect(makeEngine(restoring: saved, settings: Settings()).windows == [1])
    }

    @Test func tilingKeepsSplitDirectionAndRatio() throws {
        var engine = DwindleEngine(settings: Settings())
        engine.insert(1, after: nil)
        engine.insert(2, after: 1)
        engine.insert(3, after: 2)
        // 3 goes next to 2 (side by side instead of stacked), and grows by 100 points.
        let ok1 = engine.perform(.toggleSplit, focused: 3, in: tilingContext)
        #expect(ok1)
        let ok2 = engine.perform(.resize(.width, 100), focused: 3, in: tilingContext)
        #expect(ok2)

        var copy = try restored(engine)

        #expect(copy.windows == [1, 2, 3])
        #expect(copy.frames(in: tilingContext, focused: 3) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 600),
            2: CGRect(x: 500, y: 0, width: 150, height: 600),
            3: CGRect(x: 650, y: 0, width: 350, height: 600),
        ])
    }

    @Test func tilingRestoredLayoutLosesAWindowLikeAnyLayout() throws {
        var engine = DwindleEngine(settings: Settings())
        engine.insert(1, after: nil)
        engine.insert(2, after: 1)
        engine.insert(3, after: 2)

        var copy = try restored(engine)
        copy.remove(2)

        #expect(copy.frames(in: tilingContext, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 600),
            3: CGRect(x: 500, y: 0, width: 500, height: 600),
        ])
    }

    @Test func scrollingKeepsATemplateBlock() throws {
        var engine = ScrollingEngine(settings: Settings())
        for (id, anchor) in [(1, nil), (2, 1), (3, 2), (4, 3)] as [(WindowID, WindowID?)] { engine.insert(id, after: anchor) }
        let ok3 = engine.perform(.applyTemplate(.stackLeft), focused: 1, in: scrollingContext)
        #expect(ok3)

        var copy = try restored(engine) as! ScrollingEngine
        let frames = copy.frames(in: scrollingContext, focused: 1)

        #expect(copy.windows == [1, 2, 3, 4])
        #expect(copy.template(of: 2) == .stackLeft)
        #expect(copy.template(of: 4) == nil)
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 500, height: 400))
        #expect(frames[2] == CGRect(x: 0, y: 400, width: 500, height: 400))
        #expect(frames[3] == CGRect(x: 500, y: 0, width: 500, height: 800))
    }

    @Test func scrollingKeepsBothStripsTheScrollOffsetAndAMaximizedColumn() throws {
        var engine = ScrollingEngine(settings: Settings())
        for (id, anchor) in [(1, nil), (2, 1), (3, 2), (4, 3)] as [(WindowID, WindowID?)] { engine.insert(id, after: anchor) }
        let ok4 = engine.perform(.sendToStrip(.vertical), focused: 4, in: scrollingContext)
        #expect(ok4)
        let ok5 = engine.perform(.maximize, focused: 1, in: scrollingContext)
        #expect(ok5)
        // The horizontal zone is 750 wide: column 1 fills it, columns 2 and 3 are 375 wide. Showing 3 scrolls to the end.
        _ = engine.frames(in: scrollingContext, focused: 3)

        var copy = try restored(engine) as! ScrollingEngine
        let frames = copy.frames(in: scrollingContext, focused: 3)

        #expect(copy.windows == [1, 2, 3, 4])
        #expect(copy.strip(of: 4) == .vertical)
        #expect(copy.isMaximized(1))
        #expect(!copy.isMaximized(2))
        #expect(copy.verticalWidth == 0.25)
        #expect(copy.scrollOffset == 750)
        #expect(frames[4] == CGRect(x: 750, y: 0, width: 250, height: 400))
    }

    @Test func monocleKeepsTheOrderAndTheWindowInView() throws {
        var engine = MonocleEngine(settings: Settings())
        for (id, anchor) in [(1, nil), (2, 1), (3, 2)] as [(WindowID, WindowID?)] { engine.insert(id, after: anchor) }
        let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
        _ = engine.frames(in: LayoutContext(viewport: area, hiddenCorner: CGPoint(x: 4000, y: 3000)), focused: 2)

        var copy = try restored(engine) as! MonocleEngine

        #expect(engine.state.kind == .monocle)
        #expect(copy.windows == [1, 2, 3])
        let frames = copy.frames(in: LayoutContext(viewport: area, hiddenCorner: CGPoint(x: 4000, y: 3000)), focused: nil)
        #expect(frames[2] == area)
    }
}
