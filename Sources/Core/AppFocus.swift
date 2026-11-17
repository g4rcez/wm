import Foundation

/// The window that `focus app` raises. `ids` are the windows of the app. When the focus is already on one of them, the next
/// one in id order (around the end), so a key pressed again walks through the windows of the app. Else the one that had the
/// focus most recently (`recent` lists ids, most recent first), and the lowest id among windows that never had it.
public func windowToRaise(ofApp ids: [WindowID], focused: WindowID?, recent: [WindowID]) -> WindowID? {
    guard !ids.isEmpty else { return nil }
    let ordered = ids.sorted()
    if let focused, let index = ordered.firstIndex(of: focused) { return ordered[(index + 1) % ordered.count] }
    return ordered.min { (recent.firstIndex(of: $0) ?? Int.max, $0) < (recent.firstIndex(of: $1) ?? Int.max, $1) }
}
