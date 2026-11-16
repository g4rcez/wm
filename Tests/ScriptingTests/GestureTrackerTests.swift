import Testing
@testable import Scripting

struct GestureTrackerTests {
    private let left = Gesture(modifiers: .option, direction: .left, action: .command("workspace prev"), threshold: 100)
    private let right = Gesture(modifiers: .option, direction: .right, action: .command("workspace next"), threshold: 100)
    private let down = Gesture(modifiers: .option, direction: .down, action: .command("layout balance"), threshold: 50)

    @Test func aSwipeFarEnoughRunsTheCommandOnce() {
        var tracker = GestureTracker()
        let gestures = [left, right]
        #expect(tracker.scroll(dx: -40, dy: 0, modifiers: .option, phase: .began, time: 0, gestures: gestures) == .consumed)
        #expect(tracker.scroll(dx: -40, dy: 0, modifiers: .option, phase: .changed, time: 0.01, gestures: gestures) == .consumed)
        #expect(tracker.scroll(dx: -40, dy: 0, modifiers: .option, phase: .changed, time: 0.02, gestures: gestures) == .fire(.command("workspace prev")))
        // The rest of the swipe, and the coasting after it, run nothing more.
        #expect(tracker.scroll(dx: -80, dy: 0, modifiers: .option, phase: .changed, time: 0.03, gestures: gestures) == .consumed)
        #expect(tracker.scroll(dx: -10, dy: 0, modifiers: .option, phase: .ended, time: 0.04, gestures: gestures) == .consumed)
        #expect(tracker.scroll(dx: -200, dy: 0, modifiers: .option, phase: .none, time: 0.05, gestures: gestures) == .consumed)
    }

    @Test func theNextSwipeRunsAgain() {
        var tracker = GestureTracker()
        let gestures = [left, right]
        _ = tracker.scroll(dx: -150, dy: 0, modifiers: .option, phase: .began, time: 0, gestures: gestures)
        _ = tracker.scroll(dx: 0, dy: 0, modifiers: .option, phase: .ended, time: 0.01, gestures: gestures)
        #expect(tracker.scroll(dx: 150, dy: 0, modifiers: .option, phase: .began, time: 1, gestures: gestures) == .fire(.command("workspace next")))
    }

    @Test func aShortSwipeRunsNothing() {
        var tracker = GestureTracker()
        #expect(tracker.scroll(dx: -30, dy: 0, modifiers: .option, phase: .began, time: 0, gestures: [left]) == .consumed)
        #expect(tracker.scroll(dx: -30, dy: 0, modifiers: .option, phase: .ended, time: 0.01, gestures: [left]) == .consumed)
        // Coasting does not add up to the command after the fingers lifted.
        #expect(tracker.scroll(dx: -500, dy: 0, modifiers: .option, phase: .none, time: 0.02, gestures: [left]) == .consumed)
    }

    @Test func otherModifiersAreNotTouched() {
        var tracker = GestureTracker()
        #expect(tracker.scroll(dx: -300, dy: 0, modifiers: [], phase: .began, time: 0, gestures: [left]) == .ignored)
        #expect(tracker.scroll(dx: -300, dy: 0, modifiers: [.option, .shift], phase: .began, time: 1, gestures: [left]) == .ignored)
    }

    @Test func aSwipeOnAnAxisNoGestureUsesIsLeftAlone() {
        var tracker = GestureTracker()
        // Only sideways gestures: an up and down swipe goes on to the scrolling of the strip.
        #expect(tracker.scroll(dx: 2, dy: 30, modifiers: .option, phase: .began, time: 0, gestures: [left, right]) == .ignored)
        #expect(tracker.scroll(dx: 2, dy: 30, modifiers: .option, phase: .changed, time: 0.01, gestures: [left, right]) == .ignored)
    }

    @Test func theDirectionIsTheSignOfTheScroll() {
        var tracker = GestureTracker()
        #expect(tracker.scroll(dx: 150, dy: 0, modifiers: .option, phase: .began, time: 0, gestures: [left]) == .consumed)
        var other = GestureTracker()
        #expect(other.scroll(dx: 0, dy: 60, modifiers: .option, phase: .began, time: 0, gestures: [down]) == .fire(.command("layout balance")))
    }

    @Test func aPauseStartsANewSwipeWhenThereAreNoPhases() {
        var tracker = GestureTracker()
        let gestures = [left]
        #expect(tracker.scroll(dx: -150, dy: 0, modifiers: .option, phase: .none, time: 0, gestures: gestures) == .fire(.command("workspace prev")))
        #expect(tracker.scroll(dx: -150, dy: 0, modifiers: .option, phase: .none, time: 0.1, gestures: gestures) == .consumed)
        #expect(tracker.scroll(dx: -150, dy: 0, modifiers: .option, phase: .none, time: 1, gestures: gestures) == .fire(.command("workspace prev")))
    }
}
