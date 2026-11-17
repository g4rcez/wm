import CoreGraphics
import Foundation
import Testing
@testable import Core

// Viewport 1200x600, no gaps: the middle two thirds are x 200...1000 (800 wide, so a second window goes beside the first).
struct DwindleFrameTemplateTests {
    private let context = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1200, height: 600))

    private func engine(_ count: WindowID) -> DwindleEngine {
        var engine = DwindleEngine(settings: Settings())
        for id in 1...count { engine.insert(id, after: id == 1 ? nil : id - 1) }
        return engine
    }

    @Test func aLoneWindowIsCenteredInTwoThirdsOfTheWidth() {
        var engine = engine(1)
        let result1 = engine.perform(.applyTemplate(.centered), focused: 1, in: context)
        #expect(result1)
        #expect(engine.frames(in: context, focused: 1) == [1: CGRect(x: 200, y: 0, width: 800, height: 600)])
    }

    @Test func manyWindowsShareTheMiddleTwoThirds() {
        var engine = engine(2)
        let result2 = engine.perform(.applyTemplate(.centered), focused: 1, in: context)
        #expect(result2)
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 200, y: 0, width: 400, height: 600),
            2: CGRect(x: 600, y: 0, width: 400, height: 600),
        ])
    }

    @Test func aWindowThatOpensLaterStaysInsideTheFrame() {
        var engine = engine(1)
        _ = engine.perform(.applyTemplate(.centered), focused: 1, in: context)
        engine.insert(2, after: 1)
        #expect(engine.frames(in: context, focused: 2) == [
            1: CGRect(x: 200, y: 0, width: 400, height: 600),
            2: CGRect(x: 600, y: 0, width: 400, height: 600),
        ])
    }

    @Test func aFrameTakesAnyNumberOfWindowsButAGridNeedsAnExactCount() {
        let three = engine(3)
        #expect(three.templateError(.centered, focused: 1) == nil)
        #expect(three.templateError(.two, focused: 1) == "tile needs exactly 2 windows in this layout (the workspace has 3)")
    }

    @Test func theChainRemovesTheFrameEvenForOneWindow() {
        var engine = engine(1)
        _ = engine.perform(.applyTemplate(.centered), focused: 1, in: context)
        let result3 = engine.perform(.releaseTemplate, focused: 1, in: context)
        #expect(result3)
        #expect(engine.frames(in: context, focused: 1) == [1: CGRect(x: 0, y: 0, width: 1200, height: 600)])
        let result4 = engine.perform(.releaseTemplate, focused: 1, in: context)
        #expect(!result4)
    }

    @Test func aGridAfterTheFrameFillsTheWholeWidthAgain() {
        var engine = engine(2)
        _ = engine.perform(.applyTemplate(.centered), focused: 1, in: context)
        let result5 = engine.perform(.applyTemplate(.two), focused: 1, in: context)
        #expect(result5)
        #expect(engine.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 600, height: 600),
            2: CGRect(x: 600, y: 0, width: 600, height: 600),
        ])
    }

    @Test func theFrameSurvivesSavingAndLoading() throws {
        var engine = engine(2)
        _ = engine.perform(.applyTemplate(.centered), focused: 1, in: context)
        let data = try JSONEncoder().encode(engine.state)
        let state = try JSONDecoder().decode(LayoutState.self, from: data)
        var restored = makeEngine(restoring: state, settings: Settings())
        #expect(restored.frames(in: context, focused: 1) == [
            1: CGRect(x: 200, y: 0, width: 400, height: 600),
            2: CGRect(x: 600, y: 0, width: 400, height: 600),
        ])
    }

    @Test func aStateWithoutAFrameLoadsAsTheWholeArea() throws {
        let engine = engine(2)
        let data = try JSONEncoder().encode(engine.state)
        var restored = makeEngine(restoring: try JSONDecoder().decode(LayoutState.self, from: data), settings: Settings())
        #expect(restored.frames(in: context, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 600, height: 600),
            2: CGRect(x: 600, y: 0, width: 600, height: 600),
        ])
    }

    @Test func theScrollingLayoutRefusesAFrame() {
        var engine = ScrollingEngine(settings: Settings())
        engine.insert(1, after: nil)
        #expect(engine.templateError(.centered, focused: 1) == "this template is for the tiling layout")
    }
}
