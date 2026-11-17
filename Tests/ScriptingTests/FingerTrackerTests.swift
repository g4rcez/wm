import Testing
@testable import Scripting

struct FingerTrackerTests {
    /// `count` fingers in a row at height `y`, from `x`, 0.01 apart.
    private func touches(_ count: Int, x: Double, y: Double = 0.5) -> [TouchPoint] {
        (0..<count).map { TouchPoint(id: Int32($0), x: x + Double($0) * 0.0, y: y) }
    }

    /// Puts `count` fingers down and holds them until the swipe has begun.
    private func begin(_ tracker: inout FingerTracker, _ count: Int, x: Double = 0.25, y: Double = 0.25) -> [FingerTracker.Event] {
        var events: [FingerTracker.Event] = []
        for frame in 0..<FingerTracker.settleFrames {
            events += tracker.frame(touches(count, x: x, y: y), time: Double(frame) * 0.0625)
        }
        return events
    }

    @Test func threeFingersThatStayBeginASwipeAfterTheSettleFrames() {
        var tracker = FingerTracker()
        #expect(tracker.frame(touches(3, x: 0.25), time: 0) == [])
        #expect(tracker.frame(touches(3, x: 0.25), time: 0.01) == [])
        var tracker2 = FingerTracker()
        #expect(begin(&tracker2, 3) == [.began(fingers: 3)])
    }

    @Test func fourFingersPutDownThroughThreeDoNotBeginAThreeFingerSwipe() {
        var tracker = FingerTracker()
        #expect(tracker.frame(touches(3, x: 0.25), time: 0) == [])
        #expect(tracker.frame(touches(3, x: 0.25), time: 0.01) == [])
        var events: [FingerTracker.Event] = []
        for frame in 2..<(2 + FingerTracker.settleFrames) { events += tracker.frame(touches(4, x: 0.25), time: Double(frame) * 0.01) }
        #expect(events == [.began(fingers: 4)])
    }

    @Test func twoFingersNeverBeginASwipe() {
        var tracker = FingerTracker()
        #expect(begin(&tracker, 2) == [])
    }

    @Test func theCentreOfTheFingersMoves() {
        var tracker = FingerTracker()
        _ = begin(&tracker, 3, x: 0.25, y: 0.25)
        #expect(tracker.frame(touches(3, x: 0.75, y: 0.25), time: 0.1) == [.moved(dx: 0.5, dy: 0)])
    }

    @Test func movingUpOnThePadIsANegativeDyLikeAScrollUp() {
        var tracker = FingerTracker()
        _ = begin(&tracker, 3, x: 0.25, y: 0.25)
        #expect(tracker.frame(touches(3, x: 0.25, y: 0.75), time: 0.1) == [.moved(dx: 0, dy: -0.5)])
    }

    @Test func liftingTheFingersEndsTheSwipeWithItsSpeed() {
        var tracker = FingerTracker()
        _ = begin(&tracker, 3, x: 0.25)
        // The swipe began at 0.25 s with the fingers at 0.25; at 0.3125 s they are at 0.75: 0.5 pad widths in 0.0625 s.
        _ = tracker.frame(touches(3, x: 0.75, y: 0.25), time: 0.3125)
        #expect(tracker.frame([], time: 0.375) == [.ended(vx: 8, vy: 0)])
    }

    @Test func aChangeInTheNumberOfFingersEndsTheSwipeAndNoNewOneBeginsUntilAllAreUp() {
        var tracker = FingerTracker()
        _ = begin(&tracker, 3)
        #expect(tracker.frame(touches(4, x: 0.25), time: 0.1) == [.ended(vx: 0, vy: 0)])
        for frame in 0..<10 { #expect(tracker.frame(touches(4, x: 0.25), time: 0.2 + Double(frame) * 0.01) == []) }
        #expect(tracker.frame([], time: 0.5) == [])
        #expect(begin(&tracker, 3) == [.began(fingers: 3)])
    }

    @Test func fingersThatOnlyHoverAreNotCounted() {
        var tracker = FingerTracker()
        let hovering = (0..<3).map { TouchPoint(id: Int32($0), x: 0.25, y: 0.25, touching: false) }
        var events: [FingerTracker.Event] = []
        for frame in 0..<FingerTracker.settleFrames { events += tracker.frame(hovering, time: Double(frame) * 0.01) }
        #expect(events == [])
    }
}
