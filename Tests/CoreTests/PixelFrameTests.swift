import CoreGraphics
import Testing
@testable import Core

struct PixelFrameTests {
    @Test func aMoveByAFractionKeepsTheSize() {
        #expect(PixelFrame.rounded(CGRect(x: 10.3, y: 0, width: 500, height: 300)) == CGRect(x: 10, y: 0, width: 500, height: 300))
        #expect(PixelFrame.rounded(CGRect(x: 10.8, y: 0, width: 500, height: 300)) == CGRect(x: 11, y: 0, width: 500, height: 300))
    }

    @Test func originAndSizeRoundToTheNearestWholeNumber() {
        #expect(PixelFrame.rounded(CGRect(x: 10.5, y: 20.5, width: 99.5, height: 10.4)) == CGRect(x: 11, y: 21, width: 100, height: 10))
    }

    @Test func negativeOriginsRoundToTheNearestWholeNumber() {
        #expect(PixelFrame.rounded(CGRect(x: -748.4, y: -0.6, width: 756, height: 854)) == CGRect(x: -748, y: -1, width: 756, height: 854))
    }

    @Test func wholeNumbersStayAsTheyAre() {
        #expect(PixelFrame.rounded(CGRect(x: 756, y: 34, width: 756, height: 948)) == CGRect(x: 756, y: 34, width: 756, height: 948))
    }

    @Test func aPseudotiledWindowIsCenteredInItsCell() {
        #expect(PixelFrame.centered(CGSize(width: 300, height: 200), in: CGRect(x: 0, y: 0, width: 500, height: 600))
            == CGRect(x: 100, y: 200, width: 300, height: 200))
    }

    @Test func aPseudotiledWindowThatDoesNotFitIsCutToTheCell() {
        #expect(PixelFrame.centered(CGSize(width: 900, height: 200), in: CGRect(x: 100, y: 0, width: 500, height: 600))
            == CGRect(x: 100, y: 200, width: 500, height: 200))
    }
}
