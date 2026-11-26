import Foundation

public enum WorkspaceLimit {
    /// The most workspaces that `workspaces balance` spreads over, as `workspaces = <max>` allows in the config.
    public static let largest = 999

    public static func exceeds(_ name: String, limit: Int?) -> Bool {
        guard let limit, let number = Int(name), number >= 1 else { return false }
        return number > limit
    }

    /// Why `name` cannot be a workspace, or `nil`. A name needs a letter or a digit that is not a space. With a limit the
    /// numbers are 1 to the limit: `0` and `-1` would be workspaces that no key reaches and that balance never fills.
    public static func problem(_ name: String, limit: Int?) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "a workspace needs a name" }
        guard let limit, let number = Int(name) else { return nil }
        if number < 1 { return "workspace \(name) is not one of the workspaces 1 to \(limit) (`workspaces` in the config)" }
        if number > limit { return "workspace \(name) is above the limit of \(limit) workspaces (`workspaces` in the config)" }
        return nil
    }
}

public enum WorkspaceBalance {
    public static func plan(windows: [(id: WindowID, workspace: String)], pool: [String]) -> [WindowID: String] {
        guard !pool.isEmpty, !windows.isEmpty else { return [:] }
        let base = windows.count / pool.count
        let extra = windows.count % pool.count
        var counts: [String: Int] = [:]
        for window in windows { counts[window.workspace, default: 0] += 1 }
        let byCrowd = pool.enumerated().sorted {
            let (a, b) = (counts[$0.element] ?? 0, counts[$1.element] ?? 0)
            return a != b ? a > b : $0.offset < $1.offset
        }
        var quota: [String: Int] = Dictionary(uniqueKeysWithValues: pool.map { ($0, base) })
        for entry in byCrowd.prefix(extra) { quota[entry.element, default: 0] += 1 }

        var used: [String: Int] = [:]
        var moving: [WindowID] = []
        for window in windows {
            if let room = quota[window.workspace], used[window.workspace, default: 0] < room {
                used[window.workspace, default: 0] += 1
            } else {
                moving.append(window.id)
            }
        }
        var plan: [WindowID: String] = [:]
        var next = 0
        for id in moving {
            while used[pool[next], default: 0] >= quota[pool[next]] ?? 0 { next += 1 }
            plan[id] = pool[next]
            used[pool[next], default: 0] += 1
        }
        return plan
    }
}
