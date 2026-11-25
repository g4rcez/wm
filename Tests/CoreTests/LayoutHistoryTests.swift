import CoreGraphics
import Testing
@testable import Core

// `layout undo` and `layout redo`. Viewport 1000x600, no gaps, default settings.
struct LayoutHistoryTests {
    private let settings = Settings()
    private let context = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1000, height: 600))

    private func engine(_ kind: LayoutKind, _ ids: [WindowID]) -> any LayoutEngine {
        var engine = makeEngine(kind, settings: settings)
        for id in ids { engine.insert(id, after: engine.windows.last) }
        _ = engine.frames(in: context, focused: ids.first)
        return engine
    }

    private func step(_ engine: any LayoutEngine, floating: [WindowID: CGRect] = [:]) -> LayoutStep {
        LayoutStep(layout: engine.state, floating: floating)
    }

    private func frames(_ step: LayoutStep) -> [WindowID: CGRect] {
        var engine = makeEngine(restoring: step.layout, settings: settings)
        return engine.frames(in: context, focused: nil)
    }

    private func record(_ history: inout LayoutHistory, from old: LayoutStep, to new: LayoutStep) {
        history.begin { ["1": old] }
        history.end({ ["1": new] }, settings: { _ in settings })
    }

    @Test(arguments: [LayoutKind.tiling, .scrolling, .master])
    func undoAndRedoOfASwap(kind: LayoutKind) throws {
        var history = LayoutHistory()
        var live = engine(kind, [1, 2, 3])
        let old = step(live)
        live.relabel([1: 3, 3: 1])
        let new = step(live)
        record(&history, from: old, to: new)

        let undoneStep = history.take(.undo, of: "1", from: new, settings: settings)
        let undone = try #require(undoneStep)
        #expect(frames(undone) == frames(old))
        let redoneStep = history.take(.redo, of: "1", from: undone, settings: settings)
        let redone = try #require(redoneStep)
        #expect(frames(redone) == frames(new))
        #expect(history.take(.redo, of: "1", from: redone, settings: settings) == nil)
    }

    @Test func monocleOrderIsALayoutChange() {
        var live = engine(.monocle, [1, 2])
        let old = step(live)
        live.relabel([1: 2, 2: 1])
        #expect(old.isRearranged(by: step(live), settings: settings))
    }

    @Test func nothingIsRecordedWhenNothingChanged() {
        var history = LayoutHistory()
        let old = step(engine(.tiling, [1, 2]))
        record(&history, from: old, to: old)
        #expect(history.take(.undo, of: "1", from: old, settings: settings) == nil)
    }

    @Test func scrollingTheStripIsNotALayoutChange() {
        var live = engine(.scrolling, [1, 2, 3, 4])
        let old = step(live)
        let moved = live.perform(.scroll(300), focused: 1, in: context)
        #expect(moved)
        #expect(!old.isRearranged(by: step(live), settings: settings))
    }

    @Test func aWindowThatOpensOrClosesIsNotAStep() {
        let old = step(engine(.tiling, [1, 2]))
        #expect(!old.isRearranged(by: step(engine(.tiling, [1, 2, 3])), settings: settings))
        #expect(!old.isRearranged(by: step(engine(.tiling, [1])), settings: settings))
    }

    @Test func undoDropsAWindowThatClosed() throws {
        var history = LayoutHistory()
        var live = engine(.master, [1, 2, 3])
        let old = step(live)
        live.relabel([1: 2, 2: 1])
        record(&history, from: old, to: step(live))
        live.remove(3)

        let undoneStep = history.take(.undo, of: "1", from: step(live), settings: settings)
        let undone = try #require(undoneStep)
        #expect(makeEngine(restoring: undone.layout, settings: settings).windows == [1, 2])
    }

    // The master layout puts a new window at the top of the stack.
    @Test func undoKeepsAWindowThatOpened() throws {
        var history = LayoutHistory()
        var live = engine(.master, [1, 2])
        let old = step(live)
        live.relabel([1: 2, 2: 1])
        record(&history, from: old, to: step(live))
        live.insert(3, after: 2)

        let undoneStep = history.take(.undo, of: "1", from: step(live, floating: [4: .zero]), settings: settings)
        let undone = try #require(undoneStep)
        #expect(makeEngine(restoring: undone.layout, settings: settings).windows == [1, 3, 2])
        #expect(undone.floating == [4: .zero])
    }

    @Test func undoTilesAWindowThatWasFloated() throws {
        var history = LayoutHistory()
        var live = engine(.tiling, [1, 2])
        let old = step(live)
        live.remove(2)
        let floated = step(live, floating: [2: CGRect(x: 10, y: 10, width: 200, height: 200)])
        record(&history, from: old, to: floated)

        let undoneStep = history.take(.undo, of: "1", from: floated, settings: settings)
        let undone = try #require(undoneStep)
        #expect(undone.floating.isEmpty)
        #expect(frames(undone) == frames(old))
    }

    @Test func aStepThatOnlyDifferedByAClosedWindowIsSkipped() {
        var history = LayoutHistory()
        var live = engine(.master, [1, 2, 3])
        let old = step(live)
        live.relabel([2: 3, 3: 2])
        record(&history, from: old, to: step(live))
        live.remove(3)

        #expect(history.take(.undo, of: "1", from: step(live), settings: settings) == nil)
    }

    @Test func aNewChangeDropsTheRedoSteps() throws {
        var history = LayoutHistory()
        var live = engine(.master, [1, 2, 3])
        let first = step(live)
        live.relabel([1: 2, 2: 1])
        record(&history, from: first, to: step(live))
        let undoneStep = history.take(.undo, of: "1", from: step(live), settings: settings)
        let undone = try #require(undoneStep)

        var other = makeEngine(restoring: undone.layout, settings: settings)
        other.relabel([1: 3, 3: 1])
        record(&history, from: undone, to: step(other))

        #expect(history.take(.redo, of: "1", from: step(other), settings: settings) == nil)
    }

    @Test func nestedChangesBecomeOneStep() throws {
        var history = LayoutHistory()
        var live = engine(.master, [1, 2, 3])
        let first = step(live)
        history.begin { ["1": first] }
        live.relabel([1: 2, 2: 1])
        record(&history, from: step(live), to: step(live))
        live.relabel([2: 3, 3: 2])
        let last = step(live)
        history.end({ ["1": last] }, settings: { _ in settings })

        let undoneStep = history.take(.undo, of: "1", from: last, settings: settings)
        let undone = try #require(undoneStep)
        #expect(frames(undone) == frames(first))
        #expect(history.take(.undo, of: "1", from: undone, settings: settings) == nil)
    }

    @Test func walkingTheHistoryInsideAChangeRecordsNothingNew() throws {
        var history = LayoutHistory()
        var live = engine(.master, [1, 2])
        let old = step(live)
        live.relabel([1: 2, 2: 1])
        let new = step(live)
        record(&history, from: old, to: new)

        history.begin { ["1": new] }
        let undoneStep = history.take(.undo, of: "1", from: new, settings: settings)
        let undone = try #require(undoneStep)
        history.end({ ["1": undone] }, settings: { _ in settings })

        #expect(history.take(.redo, of: "1", from: undone, settings: settings) != nil)
    }

    @Test func theHistoryHasALimit() {
        var history = LayoutHistory()
        var live = engine(.master, [1, 2])
        for _ in 0..<(LayoutHistory.depth + 5) {
            let old = step(live)
            live.relabel([1: 2, 2: 1])
            record(&history, from: old, to: step(live))
        }
        var current = step(live)
        var count = 0
        while let undone = history.take(.undo, of: "1", from: current, settings: settings) {
            current = undone
            count += 1
        }
        #expect(count == LayoutHistory.depth)
    }

    @Test func forgetDropsBothLists() {
        var history = LayoutHistory()
        var live = engine(.master, [1, 2])
        let old = step(live)
        live.relabel([1: 2, 2: 1])
        record(&history, from: old, to: step(live))
        history.forget("1")
        #expect(history.take(.undo, of: "1", from: step(live), settings: settings) == nil)
    }
}
