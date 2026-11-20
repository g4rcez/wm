import Foundation
import Testing
@testable import Core

struct UrgentTrackerTests {
    private func primed(_ badges: [String: String] = [:]) -> UrgentTracker {
        var tracker = UrgentTracker()
        _ = tracker.update(badges: badges, frontmost: nil)
        return tracker
    }

    @Test func theFirstReadingIsOnlyTheStartingPoint() {
        var tracker = UrgentTracker()
        let alerts = tracker.update(badges: ["com.tdesktop.Telegram": "12"], frontmost: nil)
        #expect(alerts.isEmpty)
        #expect(tracker.urgentApps.isEmpty)
    }

    @Test func aBadgeThatAppearsMakesTheAppUrgent() {
        var tracker = primed()
        let alerts = tracker.update(badges: ["com.apple.mail": "1"], frontmost: "com.apple.Safari")
        #expect(alerts == [UrgentTracker.Alert(app: "com.apple.mail", badge: "1")])
        #expect(tracker.urgentApps == ["com.apple.mail"])
        #expect(tracker.isUrgent("COM.APPLE.MAIL"))
    }

    @Test func aBadgeThatGrowsMakesTheAppUrgentAgain() {
        var tracker = primed(["slack": "2"])
        let same = tracker.update(badges: ["slack": "2"], frontmost: nil)
        let more = tracker.update(badges: ["slack": "3"], frontmost: nil)
        #expect(same.isEmpty)
        #expect(more.map(\.app) == ["slack"])
    }

    @Test func aBadgeThatShrinksIsNotUrgentButKeepsTheAppUrgent() {
        var tracker = primed()
        _ = tracker.update(badges: ["slack": "5"], frontmost: nil)
        let fewer = tracker.update(badges: ["slack": "2"], frontmost: nil)
        #expect(fewer.isEmpty)
        #expect(tracker.urgentApps == ["slack"])
    }

    @Test func aBadgeThatGoesAwayEndsTheUrgency() {
        var tracker = primed()
        _ = tracker.update(badges: ["slack": "1"], frontmost: nil)
        _ = tracker.update(badges: [:], frontmost: nil)
        #expect(tracker.urgentApps.isEmpty)
    }

    @Test func theAppYouAreInIsNotUrgent() {
        var tracker = primed()
        let alerts = tracker.update(badges: ["slack": "1"], frontmost: "slack")
        #expect(alerts.isEmpty)
        #expect(tracker.urgentApps.isEmpty)
    }

    @Test func goingToTheAppClearsIt() {
        var tracker = primed()
        _ = tracker.update(badges: ["com.apple.mail": "1", "slack": "1"], frontmost: nil)
        tracker.focused("Mail", "com.apple.MAIL")
        #expect(tracker.urgentApps == ["slack"])
    }

    @Test func theAppThatAskedLastIsFirst() {
        var tracker = primed()
        _ = tracker.update(badges: ["a": "1"], frontmost: nil)
        _ = tracker.update(badges: ["a": "1", "b": "1"], frontmost: nil)
        #expect(tracker.urgentApps == ["b", "a"])
        _ = tracker.update(badges: ["a": "2", "b": "1"], frontmost: nil)
        #expect(tracker.urgentApps == ["a", "b"])
    }

    @Test func aBadgeWithoutANumberCountsAsOne() {
        #expect(UrgentTracker.count(of: "•") == 1)
        #expect(UrgentTracker.count(of: " 7 ") == 7)
        var tracker = primed()
        let first = tracker.update(badges: ["x": "•"], frontmost: nil)
        let same = tracker.update(badges: ["x": "!"], frontmost: nil)
        #expect(first.count == 1)
        #expect(same.isEmpty)
    }
}
