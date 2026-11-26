import CoreGraphics
import Testing
@testable import Platform

@MainActor
struct DragPictureTests {
    @Test func thePictureIsSmallerWithTheSameShape() {
        let size = DragPicture.pictureSize(of: CGSize(width: 1000, height: 600))
        #expect(size == CGSize(width: 350, height: 210))
    }

    @Test func aLargeWindowStopsAtTheLargestWidthAndASmallOneAtTheSmallest() {
        #expect(DragPicture.pictureSize(of: CGSize(width: 3000, height: 1500)).width == DragPicture.maxWidth)
        #expect(DragPicture.pictureSize(of: CGSize(width: 200, height: 100)) == CGSize(width: 160, height: 80))
    }
}
