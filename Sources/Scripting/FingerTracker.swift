import Foundation

/// One finger of a trackpad frame. Positions are 0 to 1 across the pad, with the origin at the bottom left.
public struct TouchPoint: Sendable, Equatable {
    public var id: Int32
    public var x: Double
    public var y: Double
    public var touching: Bool

    public init(id: Int32, x: Double, y: Double, touching: Bool = true) {
        self.id = id
        self.x = x
        self.y = y
        self.touching = touching
    }
}

/// Turns the frames of a trackpad into swipes with 3 or 4 fingers. Pure: the caller brings the frames and the time.
///
/// A swipe starts when the same number of fingers (3 or 4) has touched for `settleFrames` frames in a row, so putting down
/// four fingers does not start a three-finger swipe on the way. It ends when the fingers lift, or when their number changes
/// (and then no new swipe starts until all fingers are up). Movement is in pad widths, with y growing downward like the
/// screen, so a swipe up has a negative `dy`, as a scroll event does.
public struct FingerTracker: Sendable {
    public enum Event: Sendable, Equatable {
        case began(fingers: Int)
        case moved(dx: Double, dy: Double)
        /// The speed of the fingers at the end, in pad widths per second.
        case ended(vx: Double, vy: Double)
    }

    public static let settleFrames = 5
    private static let velocityWindow: TimeInterval = 0.1

    private var candidate = 0
    private var steady = 0
    private var fingers: Int?
    private var locked = false
    private var last = (x: 0.0, y: 0.0)
    private var samples: [(time: TimeInterval, x: Double, y: Double)] = []

    public init() {}

    public mutating func frame(_ touches: [TouchPoint], time: TimeInterval) -> [Event] {
        let active = touches.filter(\.touching)
        let count = active.count
        guard count > 0 else {
            defer { reset() }
            return fingers == nil ? [] : [.ended(vx: velocity().x, vy: velocity().y)]
        }
        let centre = (x: active.map(\.x).reduce(0, +) / Double(count), y: active.map(\.y).reduce(0, +) / Double(count))

        if let current = fingers {
            guard count == current else {
                let event = Event.ended(vx: velocity().x, vy: velocity().y)
                fingers = nil
                locked = true
                samples = []
                return [event]
            }
            let move = Event.moved(dx: centre.x - last.x, dy: -(centre.y - last.y))
            last = centre
            samples.append((time, centre.x, centre.y))
            samples.removeAll { time - $0.time > Self.velocityWindow }
            return [move]
        }

        guard !locked, count == 3 || count == 4 else {
            candidate = 0
            steady = 0
            return []
        }
        steady = candidate == count ? steady + 1 : 1
        candidate = count
        guard steady >= Self.settleFrames else { return [] }
        fingers = count
        last = centre
        samples = [(time, centre.x, centre.y)]
        return [.began(fingers: count)]
    }

    private mutating func reset() {
        candidate = 0
        steady = 0
        fingers = nil
        locked = false
        samples = []
    }

    private func velocity() -> (x: Double, y: Double) {
        guard let first = samples.first, let end = samples.last, end.time > first.time else { return (0, 0) }
        let span = end.time - first.time
        return ((end.x - first.x) / span, -(end.y - first.y) / span)
    }
}
