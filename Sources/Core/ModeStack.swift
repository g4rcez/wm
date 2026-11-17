/// The binding mode, and the modes that led to it. `mode back` returns to the one before.
public struct ModeStack: Sendable, Equatable {
    public static let main = "main"
    /// How many earlier modes are kept.
    public static let limit = 8

    public private(set) var current = main
    private var history: [String] = []

    public init() {}

    /// Makes `name` the mode. `main` is the bottom of the stack: entering it forgets the history.
    /// Returns `false` when `name` is already the mode.
    @discardableResult
    public mutating func enter(_ name: String) -> Bool {
        guard name != current else { return false }
        if name == Self.main {
            history = []
        } else {
            history.append(current)
            if history.count > Self.limit { history.removeFirst() }
        }
        current = name
        return true
    }

    /// Goes back to the mode before this one, or to `main` when there is none. Returns `false` when the mode is `main`.
    @discardableResult
    public mutating func back() -> Bool {
        guard current != Self.main else { return false }
        current = history.popLast() ?? Self.main
        return true
    }
}
