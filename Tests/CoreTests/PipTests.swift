import CoreGraphics
import Testing
@testable import Core

struct PipTests {
    private let area = CGRect(x: 0, y: 25, width: 1000, height: 800)

    @Test func theFirstPictureSitsInItsCornerWithTheShapeOfTheWindow() {
        let frames = pipFrames([CGSize(width: 800, height: 400)], corner: .bottomRight, widthFraction: 0.25, in: area)
        #expect(frames == [CGRect(x: 734, y: 684, width: 250, height: 125)])
    }

    @Test func morePicturesStackAwayFromTheCorner() {
        let shapes = [CGSize(width: 2, height: 1), CGSize(width: 2, height: 1)]
        #expect(pipFrames(shapes, corner: .topLeft, widthFraction: 0.2, in: area) == [
            CGRect(x: 16, y: 41, width: 200, height: 100),
            CGRect(x: 16, y: 149, width: 200, height: 100),
        ])
        let bottom = pipFrames(shapes, corner: .bottomLeft, widthFraction: 0.2, in: area)
        #expect(bottom[1].maxY < bottom[0].minY)
    }

    @Test func aTallWindowIsAtMostHalfTheAreaHigh() {
        let frames = pipFrames([CGSize(width: 100, height: 1000)], corner: .topRight, widthFraction: 0.25, in: area)
        #expect(frames == [CGRect(x: 944, y: 41, width: 40, height: 400)])
    }

    @Test(arguments: [
        (CGPoint(x: 10, y: 30), PipCorner.topLeft), (CGPoint(x: 900, y: 30), .topRight),
        (CGPoint(x: 10, y: 800), .bottomLeft), (CGPoint(x: 900, y: 800), .bottomRight),
    ])
    func aDraggedPictureGoesToTheNearestCorner(point: CGPoint, corner: PipCorner) {
        #expect(nearestCorner(to: point, in: area) == corner)
    }
}
