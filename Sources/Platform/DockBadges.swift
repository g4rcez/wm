import AppKit
import ApplicationServices

/// The badges that the Dock shows on app icons (the red number of Mail or Slack), read through the Accessibility API. The Dock gives
/// the text of a badge as `AXStatusLabel` on its item for the app.
public enum DockBadges {
    /// The badge text of each app in the Dock that has one, by bundle id (by name for an item that has no bundle). It reads the
    /// Dock's accessibility tree, which takes a moment, so call it off the main thread. Empty when the Dock cannot be read.
    public static func read() -> [String: String] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [:] }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        // A Dock that does not answer must not hold the poll for the default 6 seconds.
        AXUIElementSetMessagingTimeout(root, 1)
        var badges: [String: String] = [:]
        for list in children(of: root) {
            for item in children(of: list) {
                guard let badge = attribute(item, "AXStatusLabel") as? String, !badge.isEmpty else { continue }
                let bundle = (attribute(item, kAXURLAttribute) as? URL).flatMap { Bundle(url: $0)?.bundleIdentifier }
                guard let key = bundle ?? attribute(item, kAXTitleAttribute) as? String else { continue }
                badges[key] = badge
            }
        }
        return badges
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
