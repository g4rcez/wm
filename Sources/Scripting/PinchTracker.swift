import Foundation

/// Turns the frames of a trackpad into a pinch: two fingers that come together (`pinchIn`) or move apart (`pinchOut`). Pure: the
/// caller brings the frames.
///
/// A pinch starts when exactly two fingers have touched for `FingerTracker.settleFrames` frames in a row. It fires once, when the
/// distance between the fingers is `inRatio` of the start distance or less, or `outRatio` of it or more. Then it waits until
/// all fingers are up. A third finger, or a finger that leaves, cancels the pinch the same way. Two fingers that only scroll keep
/// their distance, so they do not fire.
public struct PinchTracker: Sendable {
    public enum Event: Sendable, Equatable { case pinchIn, pinchOut }

    public static let inRatio = 0.6
    public static let outRatio = 1.6

    private var steady = 0
    private var start: Double?
    private var locked = false

    public init() {}

    public mutating func frame(_ touches: [TouchPoint]) -> Event? {
        let active = touches.filter(\.touching)
        guard !active.isEmpty else {
            self = PinchTracker()
            return nil
        }
        guard !locked else { return nil }
        if active.count > 2 || (start != nil && active.count != 2) {
            locked = true
            start = nil
            steady = 0
            return nil
        }
        guard active.count == 2 else {
            steady = 0
            return nil
        }
        let distance = hypot(active[0].x - active[1].x, active[0].y - active[1].y)
        guard let first = start else {
            steady += 1
            if steady >= FingerTracker.settleFrames, distance > 0 { start = distance }
            return nil
        }
        let ratio = distance / first
        guard ratio <= Self.inRatio || ratio >= Self.outRatio else { return nil }
        locked = true
        start = nil
        return ratio <= Self.inRatio ? .pinchIn : .pinchOut
    }
}
