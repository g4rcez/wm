import CoreGraphics
import Testing
@testable import Core

struct GapsTests {
    @Test func smartGapsTakeAwayTheGapsOfOneTiledWindow() {
        var gaps = Gaps(inner: 8, outer: 12)
        gaps.smart = true
        #expect(gaps.effective(tiledCount: 1) == Gaps())
    }

    @Test func smartGapsStayForTwoWindowsAndForNone() {
        var gaps = Gaps(inner: 8, outer: 12)
        gaps.smart = true
        #expect(gaps.effective(tiledCount: 2) == gaps)
        #expect(gaps.effective(tiledCount: 0) == gaps)
    }

    @Test func gapsThatAreNotSmartStayForOneWindow() {
        let gaps = Gaps(inner: 8, outer: 12)
        #expect(gaps.effective(tiledCount: 1) == gaps)
    }

    @Test func aLoneWindowFillsTheViewportWithoutGaps() {
        var gaps = Gaps(inner: 8, outer: 12)
        gaps.smart = true
        let viewport = CGRect(x: 0, y: 0, width: 1000, height: 600)
        #expect(gaps.effective(tiledCount: 1).outerArea(viewport) == viewport)
    }
}
