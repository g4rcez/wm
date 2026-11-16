import CoreGraphics
import Testing
@testable import Core

struct NavigationTests {
    // Two columns, the right one split in two rows:
    //  1 | 2
    //    | 3
    private let frames: [WindowID: CGRect] = [
        1: CGRect(x: 0, y: 0, width: 100, height: 100),
        2: CGRect(x: 100, y: 0, width: 100, height: 50),
        3: CGRect(x: 100, y: 50, width: 100, height: 50),
    ]

    @Test func rightFromTheLeftWindowPicksTheTopOneAtTheSameHeight() {
        #expect(nearestWindow(from: 1, .right, in: frames, wrap: false) == 2)
    }

    @Test func downFromTheTopRightWindowPicksTheBottomOne() {
        #expect(nearestWindow(from: 2, .down, in: frames, wrap: false) == 3)
    }

    @Test func leftFromTheBottomRightWindowPicksTheLeftWindow() {
        #expect(nearestWindow(from: 3, .left, in: frames, wrap: false) == 1)
    }

    @Test func nothingBeyondTheEdgeWithoutWrap() {
        #expect(nearestWindow(from: 1, .left, in: frames, wrap: false) == nil)
    }

    @Test func wrapJumpsToTheFarSideOverlappingWindow() {
        #expect(nearestWindow(from: 1, .left, in: frames, wrap: true) == 2)
        #expect(nearestWindow(from: 3, .right, in: frames, wrap: true) == 1)
    }

    @Test func gapsLeaveOuterAtTheEdgeAndInnerBetweenCells() {
        let gaps = Gaps(inner: 10, outer: 20)
        let area = gaps.tilingArea(CGRect(x: 0, y: 0, width: 200, height: 100))
        #expect(area == CGRect(x: 15, y: 15, width: 170, height: 70))
        #expect(gaps.tile(CGRect(x: 15, y: 15, width: 85, height: 70)) == CGRect(x: 20, y: 20, width: 75, height: 60))
    }

    @Test func outerAreaKeepsOnlyTheOuterGaps() {
        let gaps = Gaps(inner: 10, top: 20, right: 30, bottom: 40, left: 50)
        #expect(gaps.outerArea(CGRect(x: 0, y: 0, width: 400, height: 300)) == CGRect(x: 50, y: 20, width: 320, height: 240))
    }

    // A floating window 9 on top of two tiles: the tiles are beside it although they overlap it.
    private let overlapping: [WindowID: CGRect] = [
        1: CGRect(x: 0, y: 0, width: 500, height: 800),
        2: CGRect(x: 500, y: 0, width: 500, height: 800),
        9: CGRect(x: 300, y: 200, width: 400, height: 400),
    ]

    @Test func aFloatingWindowReachesTheTilesItCovers() {
        #expect(nearestWindowByCenter(from: 9, .left, in: overlapping, wrap: false) == 1)
        #expect(nearestWindowByCenter(from: 9, .right, in: overlapping, wrap: false) == 2)
    }

    @Test func theStrictSearchFindsNothingFromAFloatingWindowThatCoversTheTiles() {
        #expect(nearestWindow(from: 9, .left, in: overlapping, wrap: false) == nil)
    }

    @Test func nothingAboveOrBelowWhenTheCentresAreOnTheSameLine() {
        #expect(nearestWindowByCenter(from: 9, .up, in: overlapping, wrap: false) == nil)
        #expect(nearestWindowByCenter(from: 9, .down, in: overlapping, wrap: true) == nil)
    }

    @Test func aStraightWindowBeatsASidewaysOne() {
        let grid: [WindowID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 500, height: 400),
            2: CGRect(x: 500, y: 0, width: 500, height: 400),
            3: CGRect(x: 500, y: 400, width: 500, height: 400),
            9: CGRect(x: 600, y: 500, width: 200, height: 200),
        ]
        #expect(nearestWindowByCenter(from: 9, .up, in: grid, wrap: false) == 2)
        #expect(nearestWindowByCenter(from: 9, .left, in: grid, wrap: false) == 1)
    }

    @Test func wrapGoesToTheFarthestWindowOnTheOtherSide() {
        #expect(nearestWindowByCenter(from: 2, .right, in: overlapping, wrap: true) == 1)
    }
}
