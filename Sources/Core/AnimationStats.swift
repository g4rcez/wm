import Foundation

/// Counters for one animation, to see how smooth it is: the time between clock ticks, how many frames were offered to
/// the windows, written and replaced, and how long each app takes to answer a frame. `wm daemon status` shows them when
/// `WM_DEBUG` is set.
public struct AnimationStats: Sendable, Equatable {
    /// A tick later than this (in seconds) after the one before counts as slow: it is a missed frame at 60 Hz.
    private static let slowTick = 0.020

    private var ticks = 0
    private var tickTotal = 0.0
    private var tickMax = 0.0
    private var slowTicks = 0
    private var offeredCount = 0
    private var writtenCount = 0
    private var replacedCount = 0
    private var apps: [String: (count: Int, total: Double, max: Double)] = [:]

    public init() {}

    public mutating func reset() { self = AnimationStats() }

    /// A clock tick, `interval` seconds after the previous tick of the same animation.
    public mutating func tick(interval: Double) {
        ticks += 1
        tickTotal += interval
        tickMax = max(tickMax, interval)
        if interval > Self.slowTick { slowTicks += 1 }
    }

    /// A new frame for a window (it differs from the last one).
    public mutating func offered() { offeredCount += 1 }
    /// A frame that was sent to the app.
    public mutating func written() { writtenCount += 1 }
    /// A frame that was dropped because a newer frame arrived before the app was ready.
    public mutating func replaced() { replacedCount += 1 }

    /// The time that `app` took for one frame.
    public mutating func write(app: String, seconds: Double) {
        let old = apps[app] ?? (0, 0, 0)
        apps[app] = (old.count + 1, old.total + seconds, max(old.max, seconds))
    }

    /// One line, for example `ticks=18 mean=16.7ms max=24.1ms slow=1 offered=50 written=41 replaced=9`, then one
    /// ` | app n=.. avg=..ms max=..ms` part for each app.
    public var summary: String {
        func ms(_ seconds: Double) -> String { String(format: "%.1fms", seconds * 1000) }
        var text = "ticks=\(ticks) mean=\(ms(ticks == 0 ? 0 : tickTotal / Double(ticks))) max=\(ms(tickMax)) slow=\(slowTicks)"
        text += " offered=\(offeredCount) written=\(writtenCount) replaced=\(replacedCount)"
        for (name, value) in apps.sorted(by: { $0.key < $1.key }) {
            text += " | \(name) n=\(value.count) avg=\(ms(value.total / Double(value.count))) max=\(ms(value.max))"
        }
        return text
    }

    public static func == (lhs: AnimationStats, rhs: AnimationStats) -> Bool { lhs.summary == rhs.summary }
}
