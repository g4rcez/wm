/// Floating windows grouped as tabs: they share one frame, one of them shows and the others wait out of sight. A Cmd-drop of a
/// floating window on the middle of another makes or grows a group. A group of one is no group.
public struct FloatGroups: Sendable, Equatable {
    private var groups: [[WindowID]] = []
    private var shown: [WindowID] = []

    public init() {}

    /// The members of the group of `window`, in tab order, or `nil` when it is in none.
    public func group(of window: WindowID) -> [WindowID]? {
        groups.first { $0.contains(window) }
    }

    /// The member of the group of `window` that shows.
    public func shownMember(of window: WindowID) -> WindowID? {
        guard let index = groups.firstIndex(where: { $0.contains(window) }) else { return nil }
        return shown[index]
    }

    /// Members that wait out of sight: in a group, and not the one that shows.
    public var waiting: Set<WindowID> {
        Set(zip(groups, shown).flatMap { group, front in group.filter { $0 != front } })
    }

    /// `window` joins the group of `target` (a new group when `target` has none), after it, and shows.
    public mutating func join(_ window: WindowID, with target: WindowID) {
        guard window != target else { return }
        leave(window)
        if let index = groups.firstIndex(where: { $0.contains(target) }) {
            let at = groups[index].firstIndex(of: target)! + 1
            groups[index].insert(window, at: at)
            shown[index] = window
        } else {
            groups.append([target, window])
            shown.append(window)
        }
    }

    /// `window` leaves its group. The next member shows when it was the one in front; a group of one ends.
    public mutating func leave(_ window: WindowID) {
        guard let index = groups.firstIndex(where: { $0.contains(window) }) else { return }
        let position = groups[index].firstIndex(of: window)!
        groups[index].remove(at: position)
        if groups[index].count < 2 {
            groups.remove(at: index)
            shown.remove(at: index)
            return
        }
        if shown[index] == window { shown[index] = groups[index][min(position, groups[index].count - 1)] }
    }

    /// The member `step` places away from the one that shows (wrapping) shows instead. Returns it, or `nil` with no group.
    @discardableResult
    public mutating func cycle(_ window: WindowID, by step: Int) -> WindowID? {
        guard let index = groups.firstIndex(where: { $0.contains(window) }) else { return nil }
        let members = groups[index]
        let current = members.firstIndex(of: shown[index])!
        shown[index] = members[((current + step) % members.count + members.count) % members.count]
        return shown[index]
    }

    /// `window` shows in its group (it got the focus another way: the switcher, a click, a command).
    public mutating func show(_ window: WindowID) {
        guard let index = groups.firstIndex(where: { $0.contains(window) }) else { return }
        shown[index] = window
    }
}
