import CoreGraphics
import Testing
@testable import Core

struct RotationTests {
    // 2 x 2 grid: 1 top-left, 2 top-right, 3 bottom-right, 4 bottom-left.
    private let grid: [WindowID: CGRect] = [
        1: CGRect(x: 0, y: 0, width: 100, height: 100),
        2: CGRect(x: 100, y: 0, width: 100, height: 100),
        3: CGRect(x: 100, y: 100, width: 100, height: 100),
        4: CGRect(x: 0, y: 100, width: 100, height: 100),
    ]

    @Test func ringGoesClockwiseAroundTheCentre() {
        let ring = clockwiseRing(grid)
        // The ring is cyclic; check the order of neighbours: 1 -> 2 -> 3 -> 4 -> 1.
        let start = ring.firstIndex(of: 1)!
        #expect([ring[start], ring[(start + 1) % 4], ring[(start + 2) % 4], ring[(start + 3) % 4]] == [1, 2, 3, 4])
    }

    @Test func spiralOfThreeWindowsGoesLeftTopRightBottomRight() {
        // dwindle: A fills the left half, B the top right, C the bottom right.
        let frames: [WindowID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 100, height: 200),
            2: CGRect(x: 100, y: 0, width: 100, height: 100),
            3: CGRect(x: 100, y: 100, width: 100, height: 100),
        ]
        let ring = clockwiseRing(frames)
        let start = ring.firstIndex(of: 1)!
        #expect([ring[start], ring[(start + 1) % 3], ring[(start + 2) % 3]] == [1, 2, 3])
    }

    @Test func clockwiseRotationMovesEveryWindowToTheNextSlot() {
        #expect(rotation(of: [1, 2, 3, 4], clockwise: true) == [1: 4, 2: 1, 3: 2, 4: 3])
    }

    @Test func counterclockwiseRotationMovesEveryWindowToThePreviousSlot() {
        #expect(rotation(of: [1, 2, 3, 4], clockwise: false) == [1: 2, 2: 3, 3: 4, 4: 1])
    }

    @Test func oneWindowOrNoneHasNothingToRotate() {
        #expect(rotation(of: [1], clockwise: true).isEmpty)
        #expect(clockwiseRing([:]).isEmpty)
    }
}
