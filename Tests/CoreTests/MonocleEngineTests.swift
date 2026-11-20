import CoreGraphics
import Foundation
import Testing
@testable import Core

// Viewport 1000x800, hidden corner (4000, 3000).
struct MonocleEngineTests {
    private let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let corner = CGPoint(x: 4000, y: 3000)
    private var context: LayoutContext { LayoutContext(viewport: area, gaps: Gaps(), hiddenCorner: corner) }

    private func engine(_ count: WindowID) -> MonocleEngine {
        var engine = MonocleEngine(settings: Settings())
        for id in 1...max(count, 1) where id <= count { engine.insert(id, after: id == 1 ? nil : id - 1) }
        return engine
    }

    @Test func aLoneWindowFillsTheArea() {
        var engine = engine(1)
        let frames = engine.frames(in: context, focused: 1)
        #expect(frames == [1: area])
    }

    @Test func theFocusedWindowFillsTheAreaAndTheOthersAreParked() {
        var engine = engine(3)
        let parked = CGRect(origin: corner, size: area.size)
        let shown = engine.frames(in: context, focused: 2)
        // Focus on a floating window (not in the layout): the window in view stays.
        let floatingFocus = engine.frames(in: context, focused: 99)
        let noFocus = engine.frames(in: context, focused: nil)
        #expect(shown == [1: parked, 2: area, 3: parked])
        #expect(floatingFocus == [1: parked, 2: area, 3: parked])
        #expect(noFocus[2] == area)
    }

    @Test func gapsAreKept() {
        var engine = engine(2)
        let gapped = LayoutContext(viewport: area, gaps: Gaps(inner: 10, outer: 20), hiddenCorner: corner)
        let frames = engine.frames(in: gapped, focused: 1)
        #expect(frames[1] == CGRect(x: 20, y: 20, width: 960, height: 760))
    }

    @Test func aNewWindowOpensAfterTheFocusedOne() {
        var engine = engine(3)
        engine.insert(4, after: 1)
        #expect(engine.windows == [1, 4, 2, 3])
        engine.insert(4, after: 3)
        #expect(engine.windows == [1, 4, 2, 3])
    }

    @Test func theNextWindowComesIntoViewWhenTheShownOneCloses() {
        var engine = engine(3)
        _ = engine.frames(in: context, focused: 2)
        engine.remove(2)
        let afterFirst = engine.frames(in: context, focused: nil)
        engine.remove(3)
        let afterSecond = engine.frames(in: context, focused: nil)
        #expect(afterFirst[3] == area)
        #expect(afterSecond[1] == area)
    }

    @Test func theNeighborIsThePreviousOrTheNextWindow() {
        var engine = engine(3)
        let right = engine.neighbor(of: 2, .right, wrap: false, in: context)
        let down = engine.neighbor(of: 2, .down, wrap: false, in: context)
        let left = engine.neighbor(of: 2, .left, wrap: false, in: context)
        let up = engine.neighbor(of: 2, .up, wrap: false, in: context)
        let pastTheEnd = engine.neighbor(of: 3, .right, wrap: false, in: context)
        let wrappedEnd = engine.neighbor(of: 3, .right, wrap: true, in: context)
        let wrappedStart = engine.neighbor(of: 1, .left, wrap: true, in: context)
        #expect(right == 3)
        #expect(down == 3)
        #expect(left == 1)
        #expect(up == 1)
        #expect(pastTheEnd == nil)
        #expect(wrappedEnd == 1)
        #expect(wrappedStart == 3)
    }

    @Test func aLoneWindowHasNoNeighborEvenWithWrap() {
        var engine = engine(1)
        let neighbor = engine.neighbor(of: 1, .right, wrap: true, in: context)
        #expect(neighbor == nil)
    }

    @Test func moveSwapsWithTheNeighborAndRotateGoesAround() {
        var engine = engine(3)
        let moved = engine.perform(.move(.right), focused: 1, in: context)
        #expect(moved)
        #expect(engine.windows == [2, 1, 3])
        let atTheStart = engine.perform(.move(.left), focused: 2, in: context)
        #expect(!atTheStart)
        let rotated = engine.perform(.rotate(clockwise: true), focused: 1, in: context)
        #expect(rotated)
        #expect(engine.windows == [3, 2, 1])
        let rotatedBack = engine.perform(.rotate(clockwise: false), focused: 1, in: context)
        #expect(rotatedBack)
        #expect(engine.windows == [2, 1, 3])
        let balanced = engine.perform(.balance, focused: 1, in: context)
        #expect(!balanced)
    }

    @Test func relabelKeepsTheWindowInView() {
        var engine = engine(2)
        _ = engine.frames(in: context, focused: 2)
        engine.relabel([2: 5])
        #expect(engine.windows == [1, 5])
        let frames = engine.frames(in: context, focused: nil)
        #expect(frames[5] == area)
    }

    @Test func theOverviewShowsEveryWindowInTheArea() {
        let engine = engine(2)
        let overview = engine.overview(in: context, focused: 1)
        #expect(overview.frames == [1: area, 2: area])
        #expect(overview.viewports == [area])
    }

    @Test func templatesAreRefused() {
        #expect(engine(1).templateError(SplitTemplate.two, focused: 1) != nil)
    }
}
