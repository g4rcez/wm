import Foundation

/// The 3 and 4 finger swipes that macOS uses itself. wm reads the trackpad next to macOS and cannot hide a swipe from it, so
/// wm leaves those swipes alone: otherwise both act on one swipe.
///
/// Built from the preferences of the trackpads and of the Dock. A trackpad domain with no value in it does not exist. A key that
/// a domain does not have has the macOS default, which is on, and so has a Mac with no domain at all.
public struct SystemSwipes: Sendable, Equatable {
    private struct Swipe: Hashable, Sendable {
        var fingers: Int
        var horizontal: Bool
    }

    private var taken: Set<Swipe> = []

    public init(trackpads: [[String: Any]], dock: [String: Any]) {
        let domains = trackpads.filter { !$0.isEmpty }
        func number(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }
        // Up opens Mission Control, down opens App Exposé and closes Mission Control, so the two directions go together.
        let missionControl = number(dock["showMissionControlGestureEnabled"]) != 0
        let appExpose = (number(dock["showAppExposeGestureEnabled"]) ?? 0) != 0
        for domain in domains.isEmpty ? [[:]] : domains {
            let threeFingerDrag = (number(domain["TrackpadThreeFingerDrag"]) ?? 0) != 0
            for (fingers, name) in [(3, "Three"), (4, "Four")] {
                let drags = fingers == 3 && threeFingerDrag
                if drags || number(domain["Trackpad\(name)FingerHorizSwipeGesture"]) != 0 {
                    taken.insert(Swipe(fingers: fingers, horizontal: true))
                }
                if drags || (number(domain["Trackpad\(name)FingerVertSwipeGesture"]) != 0 && (missionControl || appExpose)) {
                    taken.insert(Swipe(fingers: fingers, horizontal: false))
                }
            }
        }
    }

    /// Whether macOS acts on a swipe with this many fingers along this axis.
    public func takes(fingers: Int, horizontal: Bool) -> Bool {
        taken.contains(Swipe(fingers: fingers, horizontal: horizontal))
    }

    /// Whether macOS acts on the swipe of the gesture. A title bar gesture and a gesture with no finger count are scroll events,
    /// which wm takes before any app. A held modifier does not stop macOS, so `modifiers` change nothing.
    public func takes(_ gesture: Gesture) -> Bool {
        guard gesture.zone == .anywhere, let fingers = gesture.fingers else { return false }
        return takes(fingers: fingers, horizontal: gesture.direction.isHorizontal)
    }
}
