import CoreGraphics
import Testing
@testable import Core

struct MovePreviewTests {
    private let tiles: [WindowID: CGRect] = [
        1: CGRect(x: 0, y: 0, width: 500, height: 800),
        2: CGRect(x: 500, y: 0, width: 500, height: 400),
        3: CGRect(x: 500, y: 400, width: 500, height: 400),
    ]

    @Test func overAnotherTileTheWindowTakesThatTile() {
        #expect(MovePreview.target(pointer: CGPoint(x: 700, y: 600), dragged: 1, tiles: tiles) == tiles[3])
    }

    @Test func overItsOwnTileOrNoTileItGoesBack() {
        #expect(MovePreview.target(pointer: CGPoint(x: 200, y: 300), dragged: 1, tiles: tiles) == tiles[1])
        #expect(MovePreview.target(pointer: CGPoint(x: 2000, y: 300), dragged: 1, tiles: tiles) == tiles[1])
    }

    @Test func aWindowWithNoTileHasNoSlot() {
        #expect(MovePreview.target(pointer: CGPoint(x: 2000, y: 300), dragged: 9, tiles: tiles) == nil)
    }

    @Test func aMoveNeedsTravelAndTheSameSize() {
        let start = CGRect(x: 0, y: 0, width: 500, height: 800)
        #expect(!MovePreview.isMoving(from: start, to: start))
        #expect(!MovePreview.isMoving(from: start, to: start.offsetBy(dx: 2, dy: 1)))
        #expect(MovePreview.isMoving(from: start, to: start.offsetBy(dx: 30, dy: 10)))
        // A resize from the left edge moves the origin too, but changes the size.
        #expect(!MovePreview.isMoving(from: start, to: CGRect(x: 40, y: 0, width: 460, height: 800)))
    }
}
