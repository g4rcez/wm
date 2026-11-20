import Foundation
import Testing
@testable import Core

struct DynamicRuleTrackerTests {
    @Test func aWindowThatStartsToMatchIsAppliedOnce() {
        var tracker = DynamicRuleTracker()
        let first = tracker.update(window: 1, matching: [2], now: 0)
        let again = tracker.update(window: 1, matching: [2], now: 10)
        #expect(first == .applied)
        #expect(again == .none)
        #expect(tracker.matching(1) == [2])
    }

    @Test func aWindowThatMatchesNothingIsLeftAlone() {
        var tracker = DynamicRuleTracker()
        let change = tracker.update(window: 1, matching: [], now: 0)
        #expect(change == .none)
    }

    @Test func aWindowThatStopsMatchingIsReverted() {
        var tracker = DynamicRuleTracker()
        _ = tracker.update(window: 1, matching: [0], now: 0)
        let change = tracker.update(window: 1, matching: [], now: 5)
        let after = tracker.update(window: 1, matching: [], now: 6)
        #expect(change == .reverted)
        #expect(after == .none)
        #expect(tracker.matching(1).isEmpty)
    }

    @Test func otherRulesAreAppliedAgain() {
        var tracker = DynamicRuleTracker()
        _ = tracker.update(window: 1, matching: [0], now: 0)
        let change = tracker.update(window: 1, matching: [0, 3], now: 5)
        #expect(change == .applied)
        #expect(tracker.matching(1) == [0, 3])
    }

    @Test func windowsAreIndependent() {
        var tracker = DynamicRuleTracker()
        _ = tracker.update(window: 1, matching: [0], now: 0)
        let other = tracker.update(window: 2, matching: [0], now: 0)
        #expect(other == .applied)
    }

    @Test func aWindowThatFlickersIsLeftAloneUntilItCalmsDown() {
        var tracker = DynamicRuleTracker()
        var results: [DynamicRuleTracker.Change] = []
        for step in 0..<6 {
            results.append(tracker.update(window: 1, matching: step % 2 == 0 ? [0] : [], now: Double(step) * 0.1))
        }
        #expect(results == [.applied, .reverted, .applied, .reverted, .none, .none])
        // The state did not change while it was ignored, so the same title is reported once it is calm.
        let calm = tracker.update(window: 1, matching: [0], now: 5)
        #expect(calm == .applied)
    }

    @Test func forgetStartsOver() {
        var tracker = DynamicRuleTracker()
        _ = tracker.update(window: 1, matching: [0], now: 0)
        tracker.forget(1)
        let change = tracker.update(window: 1, matching: [0], now: 1)
        #expect(change == .applied)
    }
}
