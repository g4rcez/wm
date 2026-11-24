import CoreGraphics
import Foundation
import Testing
@testable import Core

// Viewport 1000x800, no gaps.
struct MasterEngineTests {
    private let context = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1000, height: 800))

    private func engine(_ count: WindowID, _ configure: (inout Settings) -> Void = { _ in }) -> MasterEngine {
        var settings = Settings()
        settings.master.ratio = 0.5
        configure(&settings)
        var engine = MasterEngine(settings: settings)
        for id in 1...max(count, 1) where id <= count { engine.insert(id, after: id == 1 ? nil : id - 1) }
        return engine
    }

    // MARK: Geometry

    @Test func aLoneWindowFillsTheArea() {
        var engine = engine(1)
        #expect(engine.frames(in: context, focused: 1) == [1: CGRect(x: 0, y: 0, width: 1000, height: 800)])
    }

    @Test func theMasterIsOnTheLeftAndTheStackSharesTheRight() {
        var engine = engine(3) { $0.master.newWindow = .master }
        // Windows opened in order 1, 2, 3 and a new window is the master: the order is 3, 2, 1.
        #expect(engine.frames(in: context, focused: 3) == [
            3: CGRect(x: 0, y: 0, width: 500, height: 800),
            2: CGRect(x: 500, y: 0, width: 500, height: 400),
            1: CGRect(x: 500, y: 400, width: 500, height: 400),
        ])
    }

    @Test func theMasterOnTheRight() {
        var engine = engine(3) { $0.master.orientation = .right }
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 500, y: 0, width: 500, height: 800),
            3: CGRect(x: 0, y: 0, width: 500, height: 400),
            2: CGRect(x: 0, y: 400, width: 500, height: 400),
        ])
    }

    @Test func theMasterOnTopSharesTheStackAcrossTheBottom() {
        var engine = engine(3) { $0.master.orientation = .top }
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 1000, height: 400),
            3: CGRect(x: 0, y: 400, width: 500, height: 400),
            2: CGRect(x: 500, y: 400, width: 500, height: 400),
        ])
    }

    @Test func theMasterAtTheBottom() {
        var engine = engine(2) { $0.master.orientation = .bottom }
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 400, width: 1000, height: 400),
            2: CGRect(x: 0, y: 0, width: 1000, height: 400),
        ])
    }

    @Test func aMasterInTheMiddleHasTheStackOnBothSides() {
        var engine = engine(4) { $0.master.orientation = .center }
        // Order: 1 (master), then the stack 4, 3, 2 (a new window goes to the top of the stack): right, left, right.
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 250, y: 0, width: 500, height: 800),
            4: CGRect(x: 750, y: 0, width: 250, height: 400),
            3: CGRect(x: 0, y: 0, width: 250, height: 800),
            2: CGRect(x: 750, y: 400, width: 250, height: 400),
        ])
    }

    @Test func aCenteredMasterWithOneStackWindowIsTheLeftLayout() {
        var engine = engine(2) { $0.master.orientation = .center }
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 800),
            2: CGRect(x: 500, y: 0, width: 500, height: 800),
        ])
    }

    @Test func twoMastersShareTheMasterArea() {
        var engine = engine(3) { $0.master.count = 2 }
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 400),
            2: CGRect(x: 0, y: 400, width: 500, height: 400),
            3: CGRect(x: 500, y: 0, width: 500, height: 800),
        ])
    }

    @Test func whenEveryWindowIsAMasterTheyShareTheWholeArea() {
        var engine = engine(2) { $0.master.count = 3 }
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 1000, height: 400),
            2: CGRect(x: 0, y: 400, width: 1000, height: 400),
        ])
    }

    @Test func gapsKeepTheirSpaceBetweenAndAroundWindows() {
        let gapped = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1000, height: 800), gaps: Gaps(inner: 20, outer: 10))
        var engine = engine(2)
        #expect(engine.frames(in: gapped, focused: 1) == [
            1: CGRect(x: 10, y: 10, width: 480, height: 780),
            2: CGRect(x: 510, y: 10, width: 480, height: 780),
        ])
    }

    // MARK: Membership

    @Test func aNewWindowGoesToTheTopOfTheStackByDefault() {
        let engine = engine(3)
        #expect(engine.windows == [1, 3, 2])
    }

    @Test func aNewWindowCanBecomeTheMaster() {
        let engine = engine(3) { $0.master.newWindow = .master }
        #expect(engine.windows == [3, 2, 1])
    }

    @Test func aWindowIsAddedOnlyOnceAndRemovedByItsId() {
        var engine = engine(3)
        engine.insert(2, after: nil)
        #expect(engine.windows == [1, 3, 2])
        engine.remove(3)
        #expect(engine.windows == [1, 2])
    }

    @Test func anEngineBuiltFromAnOrderKeepsIt() {
        let engine = MasterEngine(settings: Settings(), windows: [5, 6, 7])
        #expect(engine.windows == [5, 6, 7])
    }

    @Test func relabelingChangesTheIdsAndKeepsTheOrder() {
        var engine = engine(3)
        engine.relabel([1: 10, 2: 20])
        #expect(engine.windows == [10, 3, 20])
    }

    // MARK: Navigation and commands

    @Test func focusMovesAcrossTheLayoutByItsShape() {
        var engine = engine(3)
        // Order 1 (master), 3 (stack top), 2 (stack bottom).
        #expect(engine.neighbor(of: 3, .down, wrap: false, in: context) == 2)
        #expect(engine.neighbor(of: 3, .left, wrap: false, in: context) == 1)
        #expect(engine.neighbor(of: 1, .left, wrap: false, in: context) == nil)
    }

    @Test func movingSwapsTheWindowWithItsNeighbour() {
        var engine = engine(3)
        let moved = engine.perform(.move(.left), focused: 3, in: context)
        #expect(moved)
        #expect(engine.windows == [3, 1, 2])
        let edge = engine.perform(.move(.left), focused: 3, in: context)
        #expect(!edge)
    }

    @Test func resizingTheMasterMovesTheDividerAndAStackWindowMovesItTheOtherWay() {
        var engine = engine(2)
        let grown = engine.perform(.resize(.width, 250), focused: 1, in: context)
        #expect(grown)
        #expect(engine.frames(in: context, focused: 1)[1] == CGRect(x: 0, y: 0, width: 750, height: 800))
        let stackGrown = engine.perform(.resize(.width, 500), focused: 2, in: context)
        #expect(stackGrown)
        #expect(engine.frames(in: context, focused: 1)[1] == CGRect(x: 0, y: 0, width: 250, height: 800))
    }

    @Test func theRatioIsClampedAndTheOtherAxisIsRefused() {
        var engine = engine(2)
        let clamped = engine.perform(.resize(.width, 5000), focused: 1, in: context)
        #expect(clamped)
        let width = engine.frames(in: context, focused: 1)[1]?.width ?? 0
        #expect(abs(width - 900) < 0.001)
        let again = engine.perform(.resize(.width, 5000), focused: 1, in: context)
        #expect(!again)
        let crossAxis = engine.perform(.resize(.height, 100), focused: 1, in: context)
        #expect(!crossAxis)
    }

    @Test func aMouseResizeOnlyHonoursTheDividerSide() {
        var engine = engine(2)
        let wrong = engine.perform(.resizeEdge(.left, 100), focused: 1, in: context)
        #expect(!wrong)
        let right = engine.perform(.resizeEdge(.right, 250), focused: 1, in: context)
        #expect(right)
        #expect(engine.frames(in: context, focused: 1)[1]?.width == 750)
        let fromStack = engine.perform(.resizeEdge(.left, 250), focused: 2, in: context)
        #expect(fromStack)
        #expect(engine.frames(in: context, focused: 1)[1]?.width == 500)
    }

    @Test func aDirectionMovesTheDividerForMasterAndStack() {
        var engine = engine(2)
        let r832 = engine.perform(.resizeDirection(.right, 100), focused: 1, in: context)
        #expect(r832)
        #expect(engine.frames(in: context, focused: 1)[1]?.width == 600)
        let r304 = engine.perform(.resizeDirection(.right, 100), focused: 2, in: context)
        #expect(r304)
        #expect(engine.frames(in: context, focused: 1)[1]?.width == 700)
        let r998 = engine.perform(.resizeDirection(.left, 200), focused: 2, in: context)
        #expect(r998)
        #expect(abs((engine.frames(in: context, focused: 1)[1]?.width ?? 0) - 500) < 0.001)
        let r99 = engine.perform(.resizeDirection(.down, 100), focused: 1, in: context)
        #expect(!r99)
    }

    @Test func balanceGivesTheMasterAndTheStackTheSameWidth() {
        var engine = engine(2) { $0.master.ratio = 0.75 }
        let balanced = engine.perform(.balance, focused: 1, in: context)
        #expect(balanced)
        #expect(engine.frames(in: context, focused: 1)[1]?.width == 500)
        let again = engine.perform(.balance, focused: 1, in: context)
        #expect(!again)
    }

    @Test func balanceNeedsNoWindowInFocus() {
        var engine = engine(2) { $0.master.ratio = 0.75 }
        let balanced = engine.perform(.balance, focused: nil, in: context)
        #expect(balanced)
        #expect(engine.frames(in: context, focused: nil)[1]?.width == 500)
    }

    @Test func rotatingShiftsEveryWindowOneSlot() {
        var engine = engine(3)
        let clockwise = engine.perform(.rotate(clockwise: true), focused: 1, in: context)
        #expect(clockwise)
        #expect(engine.windows == [2, 1, 3])
        let counter = engine.perform(.rotate(clockwise: false), focused: 1, in: context)
        #expect(counter)
        #expect(engine.windows == [1, 3, 2])
    }

    @Test func promotingSwapsWithTheMasterAndTheMasterTakesTheStackTop() {
        var engine = engine(3)
        let fromStack = engine.perform(.promote, focused: 2, in: context)
        #expect(fromStack)
        #expect(engine.windows == [2, 3, 1])
        let fromMaster = engine.perform(.promote, focused: 2, in: context)
        #expect(fromMaster)
        #expect(engine.windows == [3, 2, 1])
    }

    @Test func theMasterCountChangesAndNeverDropsBelowOne() {
        var engine = engine(3)
        let more = engine.perform(.masterCount(1, relative: true), focused: 1, in: context)
        #expect(more)
        #expect(engine.frames(in: context, focused: 1)[3] == CGRect(x: 0, y: 400, width: 500, height: 400))
        let floor = engine.perform(.masterCount(-9, relative: true), focused: 1, in: context)
        #expect(floor)
        let same = engine.perform(.masterCount(1, relative: false), focused: 1, in: context)
        #expect(!same)
    }

    @Test func aHugeRelativeMasterCountIsClampedAndNeverOverflows() {
        var engine = engine(3)
        // Int.max would trap in `count + value`.
        let up = engine.perform(.masterCount(Int.max, relative: true), focused: 1, in: context)
        #expect(up)
        let sameTop = engine.perform(.masterCount(Int.max, relative: true), focused: 1, in: context)
        #expect(!sameTop)
        let down = engine.perform(.masterCount(Int.min, relative: true), focused: 1, in: context)
        #expect(down)
        let sameBottom = engine.perform(.masterCount(Int.min, relative: true), focused: 1, in: context)
        #expect(!sameBottom)
    }

    @Test func theRatioCommandSetsOrChangesTheShare() {
        var engine = engine(2)
        let exact = engine.perform(.masterRatio(0.75, relative: false), focused: 1, in: context)
        #expect(exact)
        #expect(engine.frames(in: context, focused: 1)[1]?.width == 750)
        let relative = engine.perform(.masterRatio(-0.25, relative: true), focused: 1, in: context)
        #expect(relative)
        #expect(engine.frames(in: context, focused: 1)[1]?.width == 500)
    }

    @Test func theOrientationCyclesOrIsSet() {
        var engine = engine(2)
        let next = engine.perform(.masterOrientation(nil), focused: 1, in: context)
        #expect(next)
        #expect(engine.frames(in: context, focused: 1)[1]?.minX == 500)
        let centered = engine.perform(.masterOrientation(.center), focused: 1, in: context)
        #expect(centered)
        let same = engine.perform(.masterOrientation(.center), focused: 1, in: context)
        #expect(!same)
    }

    @Test func tileTemplatesAndOtherLayoutCommandsAreRefused() {
        var engine = engine(2)
        #expect(engine.templateError(.two, focused: 1) == "tile templates are for the tiling and scrolling layouts")
        let template = engine.perform(.applyTemplate(.two), focused: 1, in: context)
        #expect(!template)
        let tabs = engine.perform(.toggleTabs, focused: 1, in: context)
        #expect(!tabs)
    }

    // MARK: Saving

    @Test func theLayoutSurvivesSavingAndLoading() throws {
        var original = engine(3)
        _ = original.perform(.masterRatio(0.75, relative: false), focused: 1, in: context)
        _ = original.perform(.masterOrientation(.right), focused: 1, in: context)
        let data = try JSONEncoder().encode(original.state)
        var settings = Settings()
        settings.master.ratio = 0.5
        var restored = makeEngine(restoring: try JSONDecoder().decode(LayoutState.self, from: data), settings: settings)
        #expect(restored.windows == [1, 3, 2])
        #expect(restored.frames(in: context, focused: 1)[1] == CGRect(x: 250, y: 0, width: 750, height: 800))
    }

    @Test func aChangedConfigWinsOverTheSavedLiveValues() throws {
        var original = engine(2)
        _ = original.perform(.masterRatio(0.75, relative: false), focused: 1, in: context)
        let data = try JSONEncoder().encode(original.state)
        var settings = Settings()
        settings.master.ratio = 0.25
        var restored = makeEngine(restoring: try JSONDecoder().decode(LayoutState.self, from: data), settings: settings)
        #expect(restored.frames(in: context, focused: 1)[1]?.width == 250)
    }
}
