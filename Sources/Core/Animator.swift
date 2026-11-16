import CoreGraphics
import Foundation

/// Moves windows toward their target frames with a critically damped spring. A window starts at rest, speeds up, and
/// slows down without overshoot. When the target changes during a move the window keeps its speed, so the motion has
/// no sudden change. The step is exact for any time step, so the motion does not depend on the frame rate.
public struct Animator: Sendable {
    /// The spring stiffness: higher is faster. A move of 1000 points ends in about `10 / rate` seconds.
    public var rate: Double
    public var enabled: Bool
    private var current: [WindowID: CGRect] = [:]
    private var target: [WindowID: CGRect] = [:]
    /// Points per second of x, y, width and height of each window that moves.
    private var speed: [WindowID: Speed] = [:]

    private struct Speed: Sendable {
        var x = 0.0, y = 0.0, width = 0.0, height = 0.0
    }

    /// A frame step never exceeds this many seconds, so a stalled frame does not make windows jump.
    private static let maxStep = 1.0 / 30
    /// Closer than this (in points) counts as arrived.
    private static let epsilon: CGFloat = 0.5

    public init(rate: Double = 14, enabled: Bool = true) {
        self.rate = rate
        self.enabled = enabled
    }

    public var isSettled: Bool { current == target }

    /// Sets the targets. Windows in `snap`, unseen windows, and every window when animations are off jump straight
    /// to their target. Windows that are no longer in `targets` are forgotten.
    public mutating func setTargets(_ targets: [WindowID: CGRect], snap: Set<WindowID> = []) {
        target = targets
        current = current.filter { targets[$0.key] != nil }
        speed = speed.filter { targets[$0.key] != nil }
        for (id, frame) in targets where !enabled || snap.contains(id) || current[id] == nil {
            current[id] = frame
        }
        for (id, frame) in targets where current[id] == frame { speed[id] = nil }
    }

    /// Starts a window's animation from `frame` (its real position) instead of jumping to the first target.
    public mutating func seed(_ id: WindowID, at frame: CGRect) {
        if current[id] == nil { current[id] = frame }
    }

    /// Moves a window's current frame to where it really is, for example after the user resized it with the mouse,
    /// so that the next animation starts there and not at the old target.
    public mutating func place(_ id: WindowID, at frame: CGRect) {
        guard target[id] != nil else { return }
        current[id] = frame
        speed[id] = nil
    }

    /// Advances by `dt` seconds. Returns the frames that changed, which the caller applies to the real windows.
    public mutating func step(dt: Double) -> [WindowID: CGRect] {
        let time = min(dt, Self.maxStep)
        var changed: [WindowID: CGRect] = [:]
        for (id, goal) in target {
            guard let from = current[id], from != goal else { continue }
            var moving = speed[id] ?? Speed()
            let next = Self.advance(from, to: goal, speed: &moving, rate: rate, time: time)
            if Self.close(next, to: goal) {
                current[id] = goal
                speed[id] = nil
                changed[id] = goal
            } else {
                current[id] = next
                speed[id] = moving
                changed[id] = next
            }
        }
        return changed
    }

    /// The frames the windows should have right now.
    public var frames: [WindowID: CGRect] { current }

    private static func close(_ a: CGRect, to b: CGRect) -> Bool {
        abs(a.minX - b.minX) < epsilon && abs(a.minY - b.minY) < epsilon
            && abs(a.width - b.width) < epsilon && abs(a.height - b.height) < epsilon
    }

    private static func advance(_ from: CGRect, to goal: CGRect, speed: inout Speed, rate: Double, time: Double) -> CGRect {
        CGRect(
            x: spring(from.minX, goal.minX, &speed.x, rate, time),
            y: spring(from.minY, goal.minY, &speed.y, rate, time),
            width: spring(from.width, goal.width, &speed.width, rate, time),
            height: spring(from.height, goal.height, &speed.height, rate, time)
        )
    }

    /// One value of the exact solution of a critically damped spring: with `d` the distance to the goal and `v` the
    /// speed, `d(t) = (d0 + (v0 + w d0) t) e^(-w t)` and `v(t) = (v0 - w (v0 + w d0) t) e^(-w t)`.
    private static func spring(_ value: CGFloat, _ goal: CGFloat, _ speed: inout Double, _ rate: Double, _ time: Double) -> CGFloat {
        let offset = Double(value - goal)
        let decay = exp(-rate * time)
        let push = speed + rate * offset
        speed = (speed - rate * push * time) * decay
        return goal + CGFloat((offset + push * time) * decay)
    }
}
