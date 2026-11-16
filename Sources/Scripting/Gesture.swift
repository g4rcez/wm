import Foundation

public enum GestureDirection: String, Sendable, Equatable, CaseIterable {
    case left, right, up, down

    var isHorizontal: Bool { self == .left || self == .right }
}

/// A swipe with a modifier held (`wm.gesture`): a two-finger scroll that goes far enough in one direction runs the
/// command, once. macOS scroll events do not say how many fingers are down, so a gesture is a modifier and a direction.
/// With natural scrolling (the macOS default) the direction is the direction of the fingers.
public struct Gesture: Sendable, Equatable {
    public var modifiers: Modifiers
    public var direction: GestureDirection
    public var action: BindAction
    /// How far the scroll has to go, in points.
    public var threshold: Double
    public var description: String?

    public init(modifiers: Modifiers, direction: GestureDirection, action: BindAction, threshold: Double = 100, description: String? = nil) {
        self.modifiers = modifiers
        self.direction = direction
        self.action = action
        self.threshold = threshold
        self.description = description
    }
}

public enum GesturePhase: Sendable { case began, changed, ended, none }

/// Decides what a scroll event means for the gestures. No event tap and no clock in here, so it can be tested.
///
/// The first event of a swipe decides its axis (sideways or up and down). When no gesture with these modifiers uses
/// that axis, the swipe is `ignored`, so the scrolling of the strip (Option + scroll) still works there. A swipe that a
/// gesture claims is `consumed` to its end, and also while it coasts; the command runs once, when the distance is
/// reached.
public struct GestureTracker: Sendable {
    public enum Outcome: Sendable, Equatable {
        case ignored
        case consumed
        case fire(BindAction)
    }

    private struct Session {
        var modifiers: Modifiers
        var horizontal: Bool?
        var claimed = false
        var x = 0.0, y = 0.0
        var fired = false
        var ended = false
        var lastTime: TimeInterval
    }

    /// A pause this long, in seconds, starts a new swipe when the device sends no phases (a mouse wheel).
    private static let pause: TimeInterval = 0.25

    private var session: Session?

    public init() {}

    public mutating func scroll(
        dx: Double, dy: Double, modifiers: Modifiers, phase: GesturePhase, time: TimeInterval, gestures: [Gesture]
    ) -> Outcome {
        if phase == .began { session = nil }
        let matching = gestures.filter { $0.modifiers == modifiers }
        guard !matching.isEmpty else {
            session = nil
            return .ignored
        }
        if let current = session, current.modifiers != modifiers || time - current.lastTime > Self.pause { session = nil }
        var state = session ?? Session(modifiers: modifiers, lastTime: time)
        state.lastTime = time
        defer { session = state }

        if state.horizontal == nil {
            guard dx != 0 || dy != 0 else { return .ignored }
            state.horizontal = abs(dx) >= abs(dy)
            state.claimed = matching.contains { $0.direction.isHorizontal == state.horizontal }
        }
        guard state.claimed else {
            if phase == .ended { state.ended = true }
            return .ignored
        }
        if phase == .ended { state.ended = true }
        // Coasting after the fingers lifted, or after the command ran: nothing more happens.
        guard !state.fired, !state.ended || phase == .ended else { return .consumed }
        state.x += dx
        state.y += dy
        for gesture in matching where gesture.direction.isHorizontal == state.horizontal {
            let distance: Double
            switch gesture.direction {
            case .left: distance = -state.x
            case .right: distance = state.x
            case .up: distance = -state.y
            case .down: distance = state.y
            }
            if distance >= gesture.threshold {
                state.fired = true
                return .fire(gesture.action)
            }
        }
        return .consumed
    }
}
