/// The bookkeeping that has to agree: a window's record says its workspace and whether it tiles, and the layout of that
/// workspace holds exactly the tiled windows. When they disagree a window shows on the wrong workspace or leaves a hole, so a
/// debug build of wm checks this after every refresh.
public enum LayoutInvariants {
    public struct Window: Sendable, Equatable {
        public var workspace: String
        /// Tiled and in the layout: not floating, minimized, hidden or swallowed.
        public var tiled: Bool

        public init(workspace: String, tiled: Bool) {
            self.workspace = workspace
            self.tiled = tiled
        }
    }

    public struct Workspace: Sendable, Equatable {
        public var engine: [WindowID]
        public var fullscreen: WindowID?
        public var maximized: Set<WindowID>

        public init(engine: [WindowID], fullscreen: WindowID? = nil, maximized: Set<WindowID> = []) {
            self.engine = engine
            self.fullscreen = fullscreen
            self.maximized = maximized
        }
    }

    /// What disagrees, one line each, sorted. A window of a restore that has not opened yet (`isPlaceholder`) may be in a layout.
    public static func problems(
        windows: [WindowID: Window], workspaces: [String: Workspace], isPlaceholder: (WindowID) -> Bool = Placeholder.isPlaceholder
    ) -> [String] {
        var found: [String] = []
        for (name, space) in workspaces {
            var seen: Set<WindowID> = []
            for id in space.engine {
                if !seen.insert(id).inserted { found.append("window \(id) is twice in the layout of workspace \(name)") }
                if isPlaceholder(id) { continue }
                guard let window = windows[id] else {
                    found.append("the layout of workspace \(name) holds window \(id), which wm does not know")
                    continue
                }
                if window.workspace != name {
                    found.append("window \(id) is in the layout of workspace \(name), but on workspace \(window.workspace)")
                } else if !window.tiled {
                    found.append("window \(id) is in the layout of workspace \(name), but does not tile")
                }
            }
            for id in [space.fullscreen].compactMap({ $0 }) + space.maximized.sorted() where windows[id]?.workspace != name {
                found.append("workspace \(name) has window \(id) in fullscreen or maximized, but it is not on it")
            }
        }
        for (id, window) in windows where window.tiled && workspaces[window.workspace]?.engine.contains(id) != true {
            found.append("window \(id) tiles on workspace \(window.workspace), but its layout does not hold it")
        }
        return found.sorted()
    }
}
