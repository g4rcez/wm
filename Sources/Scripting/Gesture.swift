import Foundation

public enum GestureDirection: String, Sendable, Equatable, CaseIterable {
    case left, right, up, down
    /// Two fingers that come together or move apart on the trackpad. Only in the title bar zone.
    case pinchIn = "pinch-in", pinchOut = "pinch-out"

    var isHorizontal: Bool { self == .left || self == .right }
    var isPinch: Bool { self == .pinchIn || self == .pinchOut }
}

/// Where the pointer has to be for a gesture. `titleBar`: over the top strip of a window (`trackpad.title_bar_height`), with no
/// modifier held. The gesture then acts on that window and not on the focused one.
public enum GestureZone: String, Sendable, Equatable, CaseIterable {
    case anywhere
    case titleBar = "title_bar"
}

/// A swipe with a modifier held (`wm.gesture`): a two-finger scroll that goes far enough in one direction runs the
/// command, once. macOS scroll events do not say how many fingers are down, so a gesture is a modifier and a direction.
/// With natural scrolling (the macOS default) the direction is the direction of the fingers.
///
/// With `fingers` set (3 or 4) it is a swipe on the trackpad itself, read from the private MultitouchSupport framework:
/// the finger count is known there. `modifiers` can still be required, and are empty when the swipe needs none.
public struct Gesture: Sendable, Equatable {
    public var modifiers: Modifiers
    public var fingers: Int?
    public var zone: GestureZone
    public var direction: GestureDirection
    public var action: BindAction
    /// How far the scroll has to go, in points.
    public var threshold: Double
    public var description: String?
    /// A swipe that wm has without a config (`Gesture.defaults`). `wm.gesture` for the same swipe replaces it.
    public var isBuiltIn: Bool

    public init(
        modifiers: Modifiers = [], fingers: Int? = nil, zone: GestureZone = .anywhere, direction: GestureDirection, action: BindAction,
        threshold: Double = 100, description: String? = nil, isBuiltIn: Bool = false
    ) {
        self.modifiers = modifiers
        self.fingers = fingers
        self.zone = zone
        self.direction = direction
        self.action = action
        self.threshold = threshold
        self.description = description
        self.isBuiltIn = isBuiltIn
    }

    /// The swipe as `wm list binds` shows it, for example `alt-scroll left` or `4-finger up`.
    public var label: String {
        if zone == .titleBar { return direction.isPinch ? "title_bar \(direction.rawValue)" : "title_bar-scroll \(direction.rawValue)" }
        return (modifiers.names + [fingers.map { "\($0)-finger" } ?? "scroll"]).joined(separator: "-") + " " + direction.rawValue
    }

    /// The swipes that work without a config. Fingers going left is the next workspace, as the Spaces of macOS do.
    public static func defaults(fingers: Int) -> [Gesture] {
        func make(_ direction: GestureDirection, _ command: String, _ description: String) -> Gesture {
            Gesture(
                fingers: fingers, direction: direction, action: .command(command), threshold: 300, description: description,
                isBuiltIn: true)
        }
        return [
            make(.left, "workspace next", "Next workspace"),
            make(.right, "workspace prev", "Previous workspace"),
            make(.up, "overview open", "Open the overview"),
            make(.down, "overview close", "Close the overview"),
        ]
    }

    /// The title bar gestures that work with `trackpad.title_bar = true` and no config.
    public static let titleBarDefaults: [Gesture] = [
        ("left", GestureDirection.left, "window swipe left", "Left half, or move left"),
        ("right", .right, "window swipe right", "Right half, or move right"),
        ("up", .up, "window swipe up", "Fullscreen, or maximize"),
        ("down", .down, "window swipe down", "Minimize"),
        ("pinch-in", .pinchIn, "window close", "Close the window"),
        ("pinch-out", .pinchOut, "window fullscreen", "Fill the screen"),
    ].map { _, direction, command, description in
        Gesture(zone: .titleBar, direction: direction, action: .command(command), description: description, isBuiltIn: true)
    }

    /// The built-in title bar gestures that the user's gestures do not replace.
    public static func missingTitleBarDefaults(_ user: [Gesture]) -> [Gesture] {
        titleBarDefaults.filter { builtIn in !user.contains { $0.zone == .titleBar && $0.direction == builtIn.direction } }
    }

    /// The built-in swipes that the user's gestures do not replace.
    public static func missingDefaults(_ user: [Gesture], fingers: Int) -> [Gesture] {
        defaults(fingers: fingers).filter { builtIn in
            !user.contains { $0.modifiers == builtIn.modifiers && $0.fingers == builtIn.fingers && $0.direction == builtIn.direction }
        }
    }

    /// The gestures to use for one swipe. On a scrolling workspace the swipe that scrolls the strip keeps its sideways
    /// movement, so the built-in sideways swipes step aside; a gesture of the user does not.
    public static func effective(_ gestures: [Gesture], scrollsStrip: Bool) -> [Gesture] {
        guard scrollsStrip else { return gestures }
        return gestures.filter { !($0.isBuiltIn && $0.direction.isHorizontal) }
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
        var fingers: Int?
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
        dx: Double, dy: Double, modifiers: Modifiers, phase: GesturePhase, time: TimeInterval, gestures: [Gesture],
        fingers: Int? = nil, zone: GestureZone = .anywhere
    ) -> Outcome {
        if phase == .began { session = nil }
        let matching = gestures.filter { $0.modifiers == modifiers && $0.fingers == fingers && $0.zone == zone && !$0.direction.isPinch }
        guard !matching.isEmpty else {
            session = nil
            return .ignored
        }
        if let current = session, current.modifiers != modifiers || current.fingers != fingers || time - current.lastTime > Self.pause {
            session = nil
        }
        var state = session ?? Session(modifiers: modifiers, fingers: fingers, lastTime: time)
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
            case .pinchIn, .pinchOut: continue
            }
            if distance >= gesture.threshold {
                state.fired = true
                return .fire(gesture.action)
            }
        }
        return .consumed
    }
}
