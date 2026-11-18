import Testing
@testable import Scripting

struct PinchTrackerTests {
    /// Two fingers `gap` apart (pad widths), in the middle of the pad.
    private func pair(_ gap: Double) -> [TouchPoint] {
        [TouchPoint(id: 0, x: 0.5 - gap / 2, y: 0.5), TouchPoint(id: 1, x: 0.5 + gap / 2, y: 0.5)]
    }

    /// Puts two fingers down `gap` apart and holds them until the pinch can start.
    private func settle(_ tracker: inout PinchTracker, gap: Double = 0.2) {
        for _ in 0..<FingerTracker.settleFrames { _ = tracker.frame(pair(gap)) }
    }

    @Test func twoFingersThatMoveApartFireAPinchOutOnce() {
        var tracker = PinchTracker()
        settle(&tracker)
        #expect(tracker.frame(pair(0.25)) == nil)
        #expect(tracker.frame(pair(0.4)) == .pinchOut)
        #expect(tracker.frame(pair(0.6)) == nil)
    }

    @Test func twoFingersThatComeTogetherFireAPinchIn() {
        var tracker = PinchTracker()
        settle(&tracker)
        #expect(tracker.frame(pair(0.15)) == nil)
        #expect(tracker.frame(pair(0.1)) == .pinchIn)
    }

    @Test func twoFingersThatScrollKeepTheirDistanceAndFireNothing() {
        var tracker = PinchTracker()
        settle(&tracker)
        for step in 0..<20 {
            let shift = Double(step) * 0.02
            let moved = [TouchPoint(id: 0, x: 0.4 + shift, y: 0.5), TouchPoint(id: 1, x: 0.6 + shift, y: 0.5)]
            #expect(tracker.frame(moved) == nil)
        }
    }

    @Test func aThirdFingerCancelsThePinchUntilAllFingersLift() {
        var tracker = PinchTracker()
        settle(&tracker)
        let three = pair(0.2) + [TouchPoint(id: 2, x: 0.9, y: 0.9)]
        #expect(tracker.frame(three) == nil)
        #expect(tracker.frame(pair(0.5)) == nil)
        #expect(tracker.frame([]) == nil)
        settle(&tracker)
        #expect(tracker.frame(pair(0.5)) == .pinchOut)
    }

    @Test func aPinchBeforeTheFingersSettleDoesNothing() {
        var tracker = PinchTracker()
        #expect(tracker.frame(pair(0.2)) == nil)
        #expect(tracker.frame(pair(0.6)) == nil)
    }

    @Test func oneFingerNeverPinches() {
        var tracker = PinchTracker()
        for _ in 0..<10 { #expect(tracker.frame([TouchPoint(id: 0, x: 0.5, y: 0.5)]) == nil) }
    }
}
