import Common
import Foundation
import Testing

struct SubscriptionTests {
    @Test func noWordsMeansEveryEvent() {
        let subscription = try? Subscription.parse([]).get()
        #expect(subscription == Subscription(events: [], snapshot: false))
        #expect(subscription?.wants("window_focus") == true)
    }

    @Test func eventNamesKeepOnlyThoseEvents() {
        let subscription = try? Subscription.parse(["window_focus", "window_floating"]).get()
        #expect(subscription?.events == ["window_focus", "window_floating"])
        #expect(subscription?.wants("window_floating") == true)
        #expect(subscription?.wants("mode_changed") == false)
    }

    @Test func snapshotIsAnOptionThatDoesNotFilterEvents() {
        let subscription = try? Subscription.parse(["--snapshot"]).get()
        #expect(subscription == Subscription(events: [], snapshot: true))
    }

    @Test func anUnknownEventNamesItself() {
        #expect(Subscription.parse(["window_focus", "window_flies"]) == .failure(SubscriptionError(message: "unknown event 'window_flies'")))
    }

    @Test func anUnknownOptionNamesItself() {
        #expect(Subscription.parse(["--all"]) == .failure(SubscriptionError(message: "unknown option '--all'")))
    }

    @Test func theEventsThatTheWindowManagerSendsAreAllKnown() {
        #expect(subscribableEvents.count == 21)
        #expect(Set(subscribableEvents).count == 21)
        #expect(subscribableEvents.contains("displays_changed"))
    }

    @Test func aSubscriberGetsTheWordsAfterSubscribe() throws {
        let path = "/tmp/wm-test-\(UUID().uuidString.prefix(8)).sock"
        let received = Received()
        let server = try SocketServer(path: path, subscriber: { descriptor, words in
            received.set(words)
            close(descriptor)
        }) { _ in ServerAnswer(exitCode: 0) }
        defer { server.stop() }

        // A long timeout: on a small CI machine, tests that run at the same time can delay the server for several seconds.
        let connection = try connectToServer(path: path, timeoutSeconds: 60)
        defer { close(connection) }
        try writeFrame(connection, JSONEncoder().encode(ClientRequest(args: ["subscribe", "--snapshot", "window_focus"])))
        _ = try readFrame(connection)
        // The server closes the connection when the subscriber is done with it.
        #expect(throws: (any Error).self) { try readFrame(connection) }

        #expect(received.words == ["--snapshot", "window_focus"])
    }
}

private final class Received: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var words: [String] { lock.withLock { stored } }
    func set(_ words: [String]) { lock.withLock { stored = words } }
}
