import CoreGraphics
import Testing
@testable import Core

struct MouseGestureTests {
    private let window = CGRect(x: 100, y: 100, width: 600, height: 400)

    @Test func aClickInsideTheContentIsNoGesture() {
        #expect(!MouseGesture.mayRearrange(at: CGPoint(x: 400, y: 300), frames: [window]))
    }

    @Test(arguments: [
        CGPoint(x: 400, y: 120),  // title bar
        CGPoint(x: 400, y: 155),  // a toolbar under it
        CGPoint(x: 102, y: 300),  // left edge, inside
        CGPoint(x: 95, y: 300),   // left edge, just outside
        CGPoint(x: 700, y: 300),  // right edge
        CGPoint(x: 400, y: 496),  // bottom edge
        CGPoint(x: 704, y: 504),  // bottom-right corner, outside
    ])
    func anEdgeOrTheTitleBarCanStartOne(point: CGPoint) {
        #expect(MouseGesture.mayRearrange(at: point, frames: [window]))
    }

    @Test func farFromEveryWindowOrWithNoWindowIsNoGesture() {
        #expect(!MouseGesture.mayRearrange(at: CGPoint(x: 900, y: 900), frames: [window]))
        #expect(!MouseGesture.mayRearrange(at: CGPoint(x: 400, y: 120), frames: []))
    }
}
