/// A session name is also a file name, so only a few characters go into it.
public func isValidSessionName(_ name: String) -> Bool {
    guard let first = name.first, first != ".", first != "-", name.count <= 64 else { return false }
    return name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
}

/// A window that is open now and can take the place of a saved one.
public struct OpenWindow: Sendable, Equatable {
    public var id: WindowID
    public var bundleID: String
    public var title: String

    public init(id: WindowID, bundleID: String, title: String) {
        self.id = id
        self.bundleID = bundleID
        self.title = title
    }
}

/// Which open window takes which saved place: the key of the candidate, by window id. Windows with the title of a saved one
/// are matched first, so that a window without it does not take their place. Then the others go by app, in saved order.
public func matchOpenWindows(_ open: [OpenWindow], to candidates: [RestoreCandidate]) -> [WindowID: Int] {
    var left = candidates
    var result: [WindowID: Int] = [:]
    for sameTitle in [true, false] {
        for window in open.sorted(by: { $0.id < $1.id }) where result[window.id] == nil {
            let pool = sameTitle ? left.filter { !window.title.isEmpty && $0.title == window.title } : left
            guard let match = bestRestoreMatch(bundleID: window.bundleID, title: window.title, among: pool) else { continue }
            result[window.id] = match.key
            left.removeAll { $0.key == match.key }
        }
    }
    return result
}
