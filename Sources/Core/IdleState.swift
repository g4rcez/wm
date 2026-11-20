import Foundation

/// Turns the seconds since the last keyboard or mouse input into events: `idle` once for each threshold that the idle time passes,
/// and `resume` when input comes back after at least one `idle`.
///
/// Readings come every few seconds, so an `idle` event is up to one reading late, and `resume` tells the idle time at the last reading
/// before the input, not the exact time.
public struct IdleState: Sendable {
    public enum Change: Equatable, Sendable {
        /// The idle time passed this threshold, in seconds.
        case idle(seconds: Double)
        /// Input came back after this many idle seconds (at the last reading before it).
        case resumed(idle: Double)
    }

    /// The thresholds of the config, sorted, without repeats.
    public let thresholds: [Double]
    private var crossed: Set<Double> = []
    private var last: Double = 0

    public init(thresholds: [Double]) {
        self.thresholds = Array(Set(thresholds.filter { $0 > 0 })).sorted()
    }

    /// The seconds between two readings: about a quarter of the shortest threshold, between 1 and 5. `nil` without thresholds.
    public var pollInterval: Double? {
        thresholds.first.map { min(5, max(1, $0 / 4)) }
    }

    /// Takes a reading. `idleSeconds` is the time since the last input; a value lower than the one before means that there was input.
    public mutating func update(idleSeconds: Double) -> [Change] {
        var changes: [Change] = []
        if idleSeconds < last, !crossed.isEmpty {
            changes.append(.resumed(idle: last))
            crossed = []
        }
        for threshold in thresholds where idleSeconds >= threshold && !crossed.contains(threshold) {
            crossed.insert(threshold)
            changes.append(.idle(seconds: threshold))
        }
        last = idleSeconds
        return changes
    }
}
