import CoreGraphics
import Testing
@testable import Core

struct FloatPlacementTests {
    private let area = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func aWindowKeepsItsSizeAndGoesToTheMiddle() {
        #expect(floatFrame(current: CGRect(x: 10, y: 10, width: 400, height: 300), in: area) == CGRect(x: 300, y: 250, width: 400, height: 300))
    }

    @Test func aFilledWindowGetsSixtyPercentOfTheArea() {
        let expected = CGRect(x: 200, y: 160, width: 600, height: 480)
        #expect(floatFrame(current: CGRect(x: 0, y: 0, width: 1000, height: 800), in: area) == expected)
        #expect(floatFrame(current: CGRect(x: 0, y: 0, width: 950, height: 760), in: area) == expected)
        #expect(floatFrame(current: CGRect(x: 0, y: 0, width: 1200, height: 900), in: area) == expected)
    }

    @Test func aWindowThatIsWideButNotTallKeepsItsSize() {
        #expect(floatFrame(current: CGRect(x: 0, y: 0, width: 950, height: 400), in: area) == CGRect(x: 25, y: 200, width: 950, height: 400))
    }

    @Test func aWindowTooWideForTheAreaIsClampedToIt() {
        #expect(floatFrame(current: CGRect(x: 0, y: 0, width: 1400, height: 300), in: area) == CGRect(x: 0, y: 250, width: 1000, height: 300))
    }

    @Test func theMiddleFollowsTheOriginOfTheArea() {
        let second = CGRect(x: 100, y: 50, width: 1000, height: 800)
        #expect(floatFrame(current: CGRect(x: 0, y: 0, width: 400, height: 300), in: second) == CGRect(x: 400, y: 300, width: 400, height: 300))
    }

    @Test func aWindowThatFitsIsNotFitted() {
        #expect(fittedFrame(CGRect(x: 600, y: 500, width: 400, height: 300), in: area) == nil)
        #expect(fittedFrame(area, in: area) == nil)
    }

    @Test func aWindowBiggerThanTheAreaIsShrunkAndCentered() {
        #expect(fittedFrame(CGRect(x: -50, y: 20, width: 1400, height: 900), in: area) == area)
    }

    @Test func aWindowTooTallKeepsItsWidthAndGoesToTheMiddle() {
        #expect(fittedFrame(CGRect(x: 0, y: 0, width: 400, height: 1200), in: area) == CGRect(x: 300, y: 0, width: 400, height: 800))
    }

    @Test func theFitFollowsTheOriginOfTheArea() {
        let second = CGRect(x: 1000, y: 0, width: 800, height: 600)
        #expect(fittedFrame(CGRect(x: 0, y: 0, width: 1000, height: 400), in: second) == CGRect(x: 1000, y: 100, width: 800, height: 400))
    }

    @Test func framesWithinTheToleranceAreTheSame() {
        #expect(sameFrame(CGRect(x: 10, y: 10, width: 400, height: 300), CGRect(x: 11, y: 9, width: 402, height: 300)))
        #expect(!sameFrame(CGRect(x: 10, y: 10, width: 400, height: 300), CGRect(x: 40, y: 10, width: 400, height: 300)))
    }
}
