import CoreGraphics
import Foundation
import Core

public enum WindowList {
    /// The window that is in front at `point`, whoever owns it (also windows that wm does not manage), with its owner.
    public static func frontmost(at point: CGPoint) -> (id: WindowID, pid: pid_t)? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for entry in list {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let number = entry[kCGWindowNumber as String] as? Int,
                  let owner = entry[kCGWindowOwnerPID as String] as? Int,
                  let bounds = (entry[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) }),
                  bounds.contains(point) else { continue }
            return (WindowID(number), pid_t(owner))
        }
        return nil
    }

    /// The window at `point` that is in front, when it is one of `ids`. A normal window of another app on top of the
    /// point means the user is pointing at that window, so the answer is `nil`. Windows above the normal layer (menus,
    /// the Dock) are skipped.
    public static func topmost(at point: CGPoint, among ids: Set<WindowID>) -> WindowID? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        // The list is ordered from the front to the back.
        for entry in list {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let number = entry[kCGWindowNumber as String] as? Int,
                  let bounds = (entry[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) }),
                  bounds.contains(point) else { continue }
            return ids.contains(WindowID(number)) ? WindowID(number) : nil
        }
        return nil
    }

    public static func bounds(of id: WindowID) -> CGRect? {
        let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(id)) as? [[String: Any]] ?? []
        guard let entry = list.first(where: { ($0[kCGWindowNumber as String] as? Int) == Int(id) }),
              let bounds = entry[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }
}
