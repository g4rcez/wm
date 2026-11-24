public enum WorkspaceLimit {
    public static func exceeds(_ name: String, limit: Int?) -> Bool {
        guard let limit, let number = Int(name), number >= 1 else { return false }
        return number > limit
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
