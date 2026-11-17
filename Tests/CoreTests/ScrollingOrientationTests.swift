import CoreGraphics
import Testing
@testable import Core

// A portrait screen: 800 wide, 1000 high, no gaps. A window that must disappear goes to (4000, 3000).
struct ScrollingOrientationTests {
    private let portrait = LayoutContext(
        viewport: CGRect(x: 0, y: 0, width: 800, height: 1000), gaps: Gaps(), hiddenCorner: CGPoint(x: 4000, y: 3000))
    private let landscape = LayoutContext(
        viewport: CGRect(x: 0, y: 0, width: 1000, height: 800), gaps: Gaps(), hiddenCorner: CGPoint(x: 4000, y: 3000))

    private func engine(_ count: WindowID, _ orientation: ScrollOrientation) -> ScrollingEngine {
        var settings = Settings()
        settings.scrolling.singleWindowFit = .keep  // these tests are about widths; a lone column fills by default
        settings.scrolling.orientation = orientation
        var engine = ScrollingEngine(settings: settings)
        for id in 1...count { engine.insert(id, after: id == 1 ? nil : id - 1) }
        return engine
    }

    @Test func rowsFillTheWidthAndTakeHalfTheHeight() {
        var engine = engine(1, .vertical)
        #expect(engine.frames(in: portrait, focused: 1) == [1: CGRect(x: 0, y: 0, width: 800, height: 500)])
    }

    @Test func theStripScrollsDownToTheFocusedRow() {
        var engine = engine(3, .vertical)
        #expect(engine.frames(in: portrait, focused: 3) == [
            1: CGRect(x: 4000, y: 3000, width: 800, height: 500),
            2: CGRect(x: 0, y: 0, width: 800, height: 500),
            3: CGRect(x: 0, y: 500, width: 800, height: 500),
        ])
    }

    @Test func downAndUpMoveAlongTheStripAndSidewaysHasNowhereToGo() {
        var engine = engine(2, .vertical)
        #expect(engine.neighbor(of: 1, .down, wrap: false, in: portrait) == 2)
        #expect(engine.neighbor(of: 2, .up, wrap: false, in: portrait) == 1)
        #expect(engine.neighbor(of: 1, .right, wrap: false, in: portrait) == nil)
    }

    @Test func aStackSitsSideBySideInsideARow() {
        var engine = engine(2, .vertical)
        let joined = engine.perform(.stack(.up), focused: 2, in: portrait)
        #expect(joined)
        #expect(engine.frames(in: portrait, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 400, height: 500),
            2: CGRect(x: 400, y: 0, width: 400, height: 500),
        ])
    }

    @Test func resizingTheHeightResizesTheRow() {
        var engine = engine(2, .vertical)
        let resized = engine.perform(.resize(.height, 100), focused: 1, in: portrait)
        #expect(resized)
        let frames = engine.frames(in: portrait, focused: 1)
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(frames[2] == CGRect(x: 0, y: 600, width: 800, height: 500))
    }

    @Test func overviewDrawsTheRowsInScreenSpace() {
        let engine = engine(2, .vertical)
        let overview = engine.overview(in: portrait, focused: 1)
        #expect(overview.frames == [
            1: CGRect(x: 0, y: 0, width: 800, height: 500),
            2: CGRect(x: 0, y: 500, width: 800, height: 500),
        ])
        #expect(overview.viewports == [CGRect(x: 0, y: 0, width: 800, height: 1000)])
    }

    @Test func aWindowKnowsWhichScreenAxisItsStripScrollsAlong() {
        let vertical = engine(1, .vertical)
        #expect(vertical.screenAxis(of: 1, in: portrait) == .vertical)
        let horizontal = engine(1, .horizontal)
        #expect(horizontal.screenAxis(of: 1, in: portrait) == .horizontal)
        #expect(horizontal.screenAxis(of: 9, in: portrait) == nil)
    }

    @Test func autoRunsDownAPortraitScreenAndAcrossALandscapeOne() {
        var tall = engine(2, .auto)
        #expect(tall.frames(in: portrait, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 800, height: 500),
            2: CGRect(x: 0, y: 500, width: 800, height: 500),
        ])
        var wide = engine(2, .auto)
        #expect(wide.frames(in: landscape, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 500, height: 800),
            2: CGRect(x: 500, y: 0, width: 500, height: 800),
        ])
    }

    @Test func horizontalStaysHorizontalOnAPortraitScreen() {
        var engine = engine(2, .horizontal)
        #expect(engine.frames(in: portrait, focused: 1) == [
            1: CGRect(x: 0, y: 0, width: 400, height: 1000),
            2: CGRect(x: 400, y: 0, width: 400, height: 1000),
        ])
    }
}
