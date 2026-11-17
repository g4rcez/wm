import Foundation

/// How a rule names a monitor: a role (`main`, `secondary`, `tertiary`), its number (1 is the leftmost) or part of its
/// name, ignoring case.
public enum MonitorSelector {
    /// The role words, in order. `main` is the display with the menu bar; the others follow from left to right.
    public static let roles = ["main", "secondary", "tertiary"]

    /// `index` is the position of the monitor from the left. `mainIndex` is the position of the main monitor.
    public static func matches(_ spec: String, index: Int, name: String, mainIndex: Int = 0) -> Bool {
        if let role = roles.firstIndex(of: spec.lowercased()) { return role == self.role(of: index, mainIndex: mainIndex) }
        if let number = Int(spec) { return number == index + 1 }
        return name.range(of: spec, options: .caseInsensitive) != nil
    }

    /// `main`, `secondary` or `tertiary`, the roles that a monitor selector accepts; `nil` for a fourth monitor or more.
    public static func roleName(index: Int, mainIndex: Int = 0) -> String? {
        let role = role(of: index, mainIndex: mainIndex)
        return roles.indices.contains(role) ? roles[role] : nil
    }

    /// 0 for the main monitor. The others count from 1, from left to right, without the main monitor.
    static func role(of index: Int, mainIndex: Int) -> Int {
        if index == mainIndex { return 0 }
        return index < mainIndex ? index + 1 : index
    }
}
