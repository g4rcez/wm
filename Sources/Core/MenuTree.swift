import Foundation

/// One entry of the menu bar of an app, as the Accessibility API shows it.
public struct MenuNode: Sendable, Equatable {
    public var title: String
    public var enabled: Bool
    /// The key equivalent as text, for example `⌘S`.
    public var shortcut: String?
    /// Names the item to press. Only items that can be pressed have one (a menu with sub-items does not).
    public var token: Int?
    public var children: [MenuNode]

    public init(title: String, enabled: Bool = true, shortcut: String? = nil, token: Int? = nil, children: [MenuNode] = []) {
        self.title = title
        self.enabled = enabled
        self.shortcut = shortcut
        self.token = token
        self.children = children
    }

    public struct Entry: Sendable, Equatable {
        /// The titles from the menu bar down, for example `File > Open Recent > Notes`.
        public var path: String
        public var token: Int
        public var shortcut: String?
    }

    /// Every item that can be pressed and is enabled, with its path. The node itself (the menu bar) is not in the path.
    public func flattened() -> [Entry] {
        var entries: [Entry] = []
        func walk(_ node: MenuNode, _ trail: [String]) {
            for child in node.children {
                let next = trail + [child.title]
                if child.children.isEmpty {
                    if child.enabled, let token = child.token {
                        entries.append(Entry(path: next.joined(separator: " > "), token: token, shortcut: child.shortcut))
                    }
                } else if child.enabled {
                    walk(child, next)
                }
            }
        }
        walk(self, [])
        return entries
    }
}

/// How the modifier bits of `AXMenuItemCmdModifiers` and the key of a menu item read as one text. Bit 0 is shift, bit 1
/// option, bit 2 control, and bit 3 says that the command key is NOT part of the shortcut.
public func menuShortcut(key: String, modifiers: Int) -> String {
    var text = ""
    if modifiers & 4 != 0 { text += "⌃" }
    if modifiers & 2 != 0 { text += "⌥" }
    if modifiers & 1 != 0 { text += "⇧" }
    if modifiers & 8 == 0 { text += "⌘" }
    return text + key.uppercased()
}
