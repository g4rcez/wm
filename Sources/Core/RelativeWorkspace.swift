import Foundation

/// `next`, `prev` and `empty` as workspace names. They need no config: the workspaces that exist are the ones that hold
/// windows or are shown.
public enum RelativeWorkspace {
    public static let words = ["next", "prev", "empty"]

    /// Numbers by value, then the other names in alphabetical order. Special workspaces are not part of the cycle.
    public static func ordered(_ names: Set<String>) -> [String] {
        names.filter { !SpecialWorkspace.isSpecial($0) }.sorted { lhs, rhs in
            switch (Int(lhs), Int(rhs)) {
            case let (a?, b?): return a < b
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
        }
    }

    /// The workspace that `word` names, seen from `current` with `used` workspaces (those with windows or shown).
    /// `next` and `prev` wrap around; `empty` is the lowest number that nobody uses. `nil` for any other word.
    public static func resolve(_ word: String, from current: String, used: Set<String>) -> String? {
        let all = ordered(used.union([current]))
        switch word {
        case "next", "prev":
            guard let index = all.firstIndex(of: current) else { return all.first }
            let step = word == "next" ? 1 : -1
            return all[((index + step) % all.count + all.count) % all.count]
        case "empty":
            let taken = used.union([current])
            return (1...).lazy.map(String.init).first { !taken.contains($0) }
        default:
            return nil
        }
    }
}
