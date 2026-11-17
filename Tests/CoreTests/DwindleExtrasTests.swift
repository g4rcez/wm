import CoreGraphics
import Testing
@testable import Core

// Viewport 1000x600, no gaps.
struct DwindleExtrasTests {
    private let context = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1000, height: 600))

    private func engine(_ count: WindowID, _ configure: (inout Settings) -> Void = { _ in }) -> DwindleEngine {
        var settings = Settings()
        configure(&settings)
        var engine = DwindleEngine(settings: settings)
        for id in 1...count { engine.insert(id, after: id == 1 ? nil : id - 1) }
        return engine
    }

    // MARK: preselect

    @Test func preselectDownPutsTheNextWindowBelow() {
        var engine = engine(1)
        let set = engine.perform(.preselect(.down), focused: 1, in: context)
        #expect(set)
        engine.insert(2, after: 1)
        #expect(engine.frames(in: context, focused: 2) == [
            1: CGRect(x: 0, y: 0, width: 1000, height: 300),
            2: CGRect(x: 0, y: 300, width: 1000, height: 300),
        ])
    }

    @Test func preselectLeftPutsTheNextWindowOnTheLeft() {
        var engine = engine(1)
        _ = engine.perform(.preselect(.left), focused: 1, in: context)
        engine.insert(2, after: 1)
        #expect(engine.frames(in: context, focused: 2) == [
            2: CGRect(x: 0, y: 0, width: 500, height: 600),
            1: CGRect(x: 500, y: 0, width: 500, height: 600),
        ])
    }

    @Test func preselectIsUsedOnce() {
        var engine = engine(1)
        _ = engine.perform(.preselect(.left), focused: 1, in: context)
        engine.insert(2, after: 1)
        engine.insert(3, after: 2)
        // 3 splits the 500x600 cell of 2 the automatic way: stacked.
        #expect(engine.frames(in: context, focused: 3) == [
            2: CGRect(x: 0, y: 0, width: 500, height: 300),
            3: CGRect(x: 0, y: 300, width: 500, height: 300),
            1: CGRect(x: 500, y: 0, width: 500, height: 600),
        ])
    }

    // MARK: settings

    @Test func splitWidthMultiplierKeepsColumnsOnAWideScreen() {
        // Without it the third window is stacked (500x600 cells are taller than wide); with 2 it stays beside.
        var engine = engine(3) { $0.tiling.splitWidthMultiplier = 2 }
        #expect(engine.frames(in: context, focused: 3) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 600),
            2: CGRect(x: 500, y: 0, width: 250, height: 600),
            3: CGRect(x: 750, y: 0, width: 250, height: 600),
        ])
    }

    @Test func forceSplitFirstPutsNewWindowsOnTheLeftOrTop() {
        var engine = engine(3) { $0.tiling.forceSplit = .first }
        #expect(engine.frames(in: context, focused: 3) == [
            1: CGRect(x: 500, y: 0, width: 500, height: 600),
            3: CGRect(x: 0, y: 0, width: 500, height: 300),
            2: CGRect(x: 0, y: 300, width: 500, height: 300),
        ])
    }

    @Test func forceSplitDefaultsToTheSecondSide() {
        var engine = engine(2)
        #expect(engine.frames(in: context, focused: 2) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 600),
            2: CGRect(x: 500, y: 0, width: 500, height: 600),
        ])
    }

    // MARK: split ratio

    // 1 | (2 over 3), the focused window is 3.
    @Test func splitRatioSetsTheShareOfTheFocusedWindow() {
        var engine = engine(3)
        let changed = engine.perform(.splitRatio(0.75, relative: false), focused: 3, in: context)
        #expect(changed)
        let frames = engine.frames(in: context, focused: 3)
        #expect(frames[2] == CGRect(x: 500, y: 0, width: 500, height: 150))
        #expect(frames[3] == CGRect(x: 500, y: 150, width: 500, height: 450))
    }

    @Test func splitRatioChangesTheShareByADelta() {
        var engine = engine(3)
        let changed = engine.perform(.splitRatio(0.25, relative: true), focused: 2, in: context)
        #expect(changed)
        // 2 is the first child: its share goes from 0.5 to 0.75.
        #expect(engine.frames(in: context, focused: 2)[2] == CGRect(x: 500, y: 0, width: 500, height: 450))
    }

    @Test func splitRatioIsClampedAndNeedsASplit() {
        var engine = engine(3)
        _ = engine.perform(.splitRatio(0.95, relative: false), focused: 3, in: context)
        let height = engine.frames(in: context, focused: 3)[3]?.height ?? 0
        #expect(abs(height - 540) < 1e-9)
        var single = self.engine(1)
        let changed = single.perform(.splitRatio(0.7, relative: false), focused: 1, in: context)
        #expect(!changed)
    }

    // MARK: move to root

    @Test func moveToRootGivesTheDeepWindowHalfOfTheScreen() {
        // 1 | (2 over (3 | 4)): 4 moves up to the root.
        var engine = engine(4)
        let moved = engine.perform(.moveToRoot, focused: 4, in: context)
        #expect(moved)
        #expect(engine.frames(in: context, focused: 4) == [
            1: CGRect(x: 0, y: 0, width: 250, height: 600),
            2: CGRect(x: 250, y: 0, width: 250, height: 300),
            3: CGRect(x: 250, y: 300, width: 250, height: 300),
            4: CGRect(x: 500, y: 0, width: 500, height: 600),
        ])
    }

    @Test func moveToRootDoesNothingForAChildOfTheRoot() {
        var engine = engine(3)
        let moved = engine.perform(.moveToRoot, focused: 1, in: context)
        #expect(!moved)
    }

    // MARK: smart split

    @Test func smartSplitPicksTheSideThePointerIsNearest() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(smartSplitSide(of: frame, at: CGPoint(x: 100, y: 400)) == .left)
        #expect(smartSplitSide(of: frame, at: CGPoint(x: 900, y: 400)) == .right)
        #expect(smartSplitSide(of: frame, at: CGPoint(x: 500, y: 40)) == .up)
        #expect(smartSplitSide(of: frame, at: CGPoint(x: 500, y: 760)) == .down)
    }

    @Test func aCornerGoesToTheSideWithTheLongerRun() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(smartSplitSide(of: frame, at: CGPoint(x: 10, y: 300)) == .left)
        #expect(smartSplitSide(of: frame, at: CGPoint(x: 400, y: 790)) == .down)
    }

    @Test func aPreselectedSideIsReadableUntilTheNextWindowTakesIt() {
        var engine = DwindleEngine(settings: Settings())
        engine.insert(1, after: nil)
        #expect(engine.preselection == nil)
        _ = engine.perform(.preselect(.left), focused: 1, in: LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1000, height: 800)))
        #expect(engine.preselection == .left)
        engine.insert(2, after: 1)
        #expect(engine.preselection == nil)
        #expect(engine.windows == [2, 1])
    }

    // MARK: split under the pointer

    @Test func theWindowUnderThePointerIsTheOneWhoseFrameContainsIt() {
        let frames: [WindowID: CGRect] = [1: CGRect(x: 0, y: 0, width: 500, height: 600), 2: CGRect(x: 500, y: 0, width: 500, height: 600)]
        #expect(windowUnder(CGPoint(x: 700, y: 300), in: frames) == 2)
        #expect(windowUnder(CGPoint(x: 100, y: 300), in: frames) == 1)
        #expect(windowUnder(CGPoint(x: 1200, y: 300), in: frames) == nil)
    }

    @Test func onASharedEdgeTheLowestIdWins() {
        let frames: [WindowID: CGRect] = [4: CGRect(x: 0, y: 0, width: 500, height: 600), 3: CGRect(x: 500, y: 0, width: 500, height: 600)]
        #expect(windowUnder(CGPoint(x: 500, y: 300), in: frames) == 3)
    }
}
