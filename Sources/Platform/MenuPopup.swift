import AppKit
import Core

/// Shows a menu tree as an `NSMenu` at the pointer. Choosing an item calls `onChoose` with its token.
@MainActor
public final class MenuPopup: NSObject {
    private var onChoose: ((Int) -> Void)?

    public override init() { super.init() }

    /// Blocks while the menu is open, like every `NSMenu` pop-up.
    public func show(_ root: MenuNode, at point: NSPoint = NSEvent.mouseLocation, onChoose: @escaping (Int) -> Void) {
        self.onChoose = onChoose
        let menu = build(root.children, title: "")
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    private func build(_ nodes: [MenuNode], title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        for node in nodes {
            let item = NSMenuItem(title: node.title, action: node.children.isEmpty ? #selector(chosen(_:)) : nil, keyEquivalent: "")
            item.target = self
            item.isEnabled = node.enabled
            if let token = node.token { item.representedObject = token }
            if let shortcut = node.shortcut { item.attributedTitle = Self.title(node.title, shortcut) }
            if !node.children.isEmpty { item.submenu = build(node.children, title: node.title) }
            menu.addItem(item)
        }
        return menu
    }

    /// The title with the shortcut at the end, in a lighter colour (an item cannot show a key equivalent that wm does not own).
    private static func title(_ title: String, _ shortcut: String) -> NSAttributedString {
        let text = NSMutableAttributedString(string: title)
        text.append(NSAttributedString(string: "   " + shortcut, attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
        return text
    }

    @objc private func chosen(_ item: NSMenuItem) {
        if let token = item.representedObject as? Int { onChoose?(token) }
    }
}
