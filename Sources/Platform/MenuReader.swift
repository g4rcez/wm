import ApplicationServices
import Core
import Foundation

/// Reads the menu bar of an app through the Accessibility API, and presses its items. It has its own thread, so a slow
/// app cannot stall the windows (the reads of a big menu take some hundreds of milliseconds).
public final class MenuReader: @unchecked Sendable {
    /// The depth of the menu tree that is read, and the most items that one read looks at.
    private static let maxDepth = 4
    private static let maxItems = 3000

    private let thread = AXThread(name: "wm-menu")
    /// The elements of the last read, by token. Only the thread touches them.
    private var elements: [Int: AXUIElement] = [:]
    private var budget = 0
    private var nextToken = 0

    public init() {}

    /// The menu bar of the app with this process id, or `nil` when it cannot be read.
    public func read(pid: pid_t) async -> MenuNode? {
        await thread.run { [self] in readMenuBar(pid: pid) }
    }

    /// Presses an item of the last read.
    public func press(token: Int) {
        thread.async { [self] in
            guard let element = elements[token] else { return }
            AXUIElementPerformAction(element, kAXPressAction as CFString)
        }
    }

    private func readMenuBar(pid: pid_t) -> MenuNode? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        guard let bar: AXUIElement = attribute(app, kAXMenuBarAttribute) else { return nil }
        elements = [:]
        budget = Self.maxItems
        nextToken = 0
        let items = nodes(in: bar, depth: 0)
        return items.isEmpty ? nil : MenuNode(title: "", children: items)
    }

    private func nodes(in container: AXUIElement, depth: Int) -> [MenuNode] {
        guard depth <= Self.maxDepth, budget > 0, let children: [AXUIElement] = attribute(container, kAXChildrenAttribute) else { return [] }
        var result: [MenuNode] = []
        for child in children {
            budget -= 1
            if budget <= 0 { break }
            let role: String = attribute(child, kAXRoleAttribute) ?? ""
            // The AXMenu between an item and its sub-items carries no title of its own.
            if role == kAXMenuRole as String {
                result += nodes(in: child, depth: depth)
                continue
            }
            let title: String = attribute(child, kAXTitleAttribute) ?? ""
            // A separator has no title. The Apple menu is the system's, not the app's.
            guard !title.isEmpty, !(depth == 0 && title == "Apple") else { continue }
            let children = nodes(in: child, depth: depth + 1)
            var token: Int?
            var shortcut: String?
            if children.isEmpty {
                token = nextToken
                elements[nextToken] = child
                nextToken += 1
                if let key: String = attribute(child, kAXMenuItemCmdCharAttribute), !key.isEmpty {
                    let modifiers: Int = attribute(child, kAXMenuItemCmdModifiersAttribute) ?? 0
                    shortcut = menuShortcut(key: key, modifiers: modifiers)
                }
            }
            result.append(MenuNode(
                title: title, enabled: attribute(child, kAXEnabledAttribute) ?? true, shortcut: shortcut, token: token, children: children))
        }
        return result
    }

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
