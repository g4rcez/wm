import CoreGraphics
import Testing
@testable import Core

struct RecentlyClosedTests {
    private func place(_ title: String, _ workspace: String, pid: pid_t = 10, floating: Bool = false) -> RecentlyClosed.Place {
        RecentlyClosed.Place(bundleID: "com.rex", pid: pid, title: title, workspace: workspace, floating: floating, floatFrame: nil)
    }

    @Test func anAppThatComesBackGetsItsWorkspacesBack() {
        var closed = RecentlyClosed()
        closed.add(place("claude", "2"), now: 0)
        closed.add(place("notes", "5"), now: 0)
        #expect(closed.take(bundleID: "com.rex", pid: 11, title: "notes", now: 10)?.workspace == "5")
        #expect(closed.take(bundleID: "com.rex", pid: 11, title: "", now: 10)?.workspace == "2")
        #expect(closed.take(bundleID: "com.rex", pid: 11, title: "", now: 10) == nil)
    }

    @Test func aWindowOfTheSameProcessIsANewWindow() {
        var closed = RecentlyClosed()
        closed.add(place("doc", "3"), now: 0)
        #expect(closed.take(bundleID: "com.rex", pid: 10, title: "doc", now: 1) == nil)
    }

    @Test func anotherAppGetsNothing() {
        var closed = RecentlyClosed()
        closed.add(place("doc", "3"), now: 0)
        #expect(closed.take(bundleID: "com.other", pid: 99, title: "doc", now: 1) == nil)
    }

    @Test func aPlaceWaitsFiveMinutes() {
        var closed = RecentlyClosed()
        closed.add(place("doc", "3"), now: 0)
        #expect(closed.take(bundleID: "com.rex", pid: 11, title: "doc", now: RecentlyClosed.keep + 1) == nil)
        closed.add(place("doc", "3"), now: 1000)
        #expect(closed.take(bundleID: "com.rex", pid: 11, title: "doc", now: 1000 + RecentlyClosed.keep - 1)?.workspace == "3")
    }
}
