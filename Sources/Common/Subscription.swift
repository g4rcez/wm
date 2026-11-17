/// What a `wm subscribe` client asked for: the events it wants (all of them when it names none) and whether the first line is
/// the state of the window manager now.
public struct Subscription: Sendable, Equatable {
    public var events: Set<String>
    public var snapshot: Bool

    public init(events: Set<String> = [], snapshot: Bool = false) {
        self.events = events
        self.snapshot = snapshot
    }

    public func wants(_ event: String) -> Bool { events.isEmpty || events.contains(event) }

    /// The words after `subscribe`: event names, and `--snapshot`. The error is a message for the user.
    public static func parse(_ words: [String]) -> Result<Subscription, SubscriptionError> {
        var subscription = Subscription()
        for word in words {
            if word == "--snapshot" {
                subscription.snapshot = true
            } else if word.hasPrefix("--") {
                return .failure(SubscriptionError(message: "unknown option '\(word)'"))
            } else if subscribableEvents.contains(word) {
                subscription.events.insert(word)
            } else {
                return .failure(SubscriptionError(message: "unknown event '\(word)'"))
            }
        }
        return .success(subscription)
    }
}

public struct SubscriptionError: Error, Equatable {
    public var message: String

    public init(message: String) { self.message = message }
}
