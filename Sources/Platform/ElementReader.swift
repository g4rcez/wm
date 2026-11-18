import AppKit
import ApplicationServices
import Core
import Foundation

/// What `ElementReader.scrollTarget` finds: the focused window and the scroll areas that show in it.
public struct ScrollTarget: Sendable, Equatable {
    public var window: CGRect
    public var areas: [CGRect]
}

/// Reads the clickable elements and the scroll areas of the screen through the Accessibility API, and posts the clicks and
/// the scrolls. It has its own thread, so a slow app cannot stall the windows. All frames are in screen coordinates, origin
/// at the top left.
public final class ElementReader: @unchecked Sendable {
    /// The most nodes that one read looks at, and the deepest level of the walk.
    private static let maxNodes = 6000
    private static let maxDepth = 40
    /// Smaller scroll areas are not worth a number.
    private static let minScrollSide: CGFloat = 40

    private static let targetRoles: Set<String> = [
        "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXMenuBarItem", "AXTextField",
        "AXTextArea", "AXComboBox", "AXDisclosureTriangle", "AXSlider", "AXIncrementor", "AXRow", "AXTab", "AXDockItem",
    ]
    private static let rowRoles: Set<String> = ["AXTable", "AXOutline"]
    private static let scrollRoles: Set<String> = ["AXScrollArea", "AXWebArea"]
    /// The order is the one of `Slot`.
    private static let attributeNames: [String] = [
        kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute, kAXPositionAttribute,
        kAXSizeAttribute, kAXEnabledAttribute, kAXChildrenAttribute, "AXVisibleRows",
    ]

    private enum Slot: Int { case role, title, description, value, help, position, size, enabled, children, visibleRows }

    private struct Node {
        var role = ""
        var text = ""
        var frame: CGRect?
        var enabled = true
        var children: [AXUIElement] = []
    }

    private let thread = AXThread(name: "wm-hints")
    /// The rest is used on the thread only.
    private var budget = 0
    private var nextID = 0
    private var found: [HintElement] = []
    private var areas: [CGRect] = []
    private var screens: [CGRect] = []
    /// A web area with no children was seen: the app has not built the tree of its page.
    private var sawEmptyWebArea = false
    /// Apps that were asked for their web content tree.
    private var prepared: Set<pid_t> = []

    public init() {}

    // MARK: - Reading

    /// The clickable elements of the focused window of the app `pid`, and of the menu bar, the menu extras and the Dock.
    /// `screens` are the frames of the displays: an element outside of them is not on the screen.
    public func clickables(pid: pid_t, screens: [CGRect]) async -> [HintElement] {
        await thread.run { [self] in readClickables(pid: pid, screens: screens) }
    }

    /// The focused window of the app `pid` and its scroll areas, or `nil` when the app has no focused window.
    public func scrollTarget(pid: pid_t) async -> ScrollTarget? {
        await thread.run { [self] in readScrollTarget(pid: pid) }
    }

    private func readClickables(pid: pid_t, screens: [CGRect]) -> [HintElement] {
        let app = application(pid)
        reset(screens: screens)
        walkWindow(of: app)
        // A browser builds the tree of a page only for an assistive tool. After the ask, the walk goes again.
        if sawEmptyWebArea, enableWebContent(app, pid: pid) {
            reset(screens: screens)
            walkWindow(of: app)
        }
        if let bar: AXUIElement = attribute(app, kAXMenuBarAttribute) { visitBarItems(of: bar) }
        for extras in Self.statusItemPIDs() {
            let owner = application(extras)
            if let bar: AXUIElement = attribute(owner, "AXExtrasMenuBar") { visitBarItems(of: bar) }
        }
        if let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
            visitDock(application(dock.processIdentifier))
        }
        return found
    }

    private func walkWindow(of app: AXUIElement) {
        if let window = focusedWindow(of: app), let frame = read(window).frame { visit(window, clip: frame, depth: 0) }
    }

    private func readScrollTarget(pid: pid_t) -> ScrollTarget? {
        let app = application(pid)
        func collect() -> CGRect? {
            reset(screens: [])
            guard let window = focusedWindow(of: app), let frame = read(window).frame else { return nil }
            collectScrollAreas(window, clip: frame, depth: 0)
            return frame
        }
        guard var frame = collect() else { return nil }
        if sawEmptyWebArea, enableWebContent(app, pid: pid), let again = collect() { frame = again }
        return ScrollTarget(window: frame, areas: areas)
    }

    private func reset(screens: [CGRect]) {
        budget = Self.maxNodes
        nextID = 0
        found = []
        areas = []
        sawEmptyWebArea = false
        self.screens = screens
    }

    private func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        return app
    }

    private func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        attribute(app, kAXFocusedWindowAttribute) ?? attribute(app, kAXMainWindowAttribute)
    }

    /// Chromium and Electron build the tree of a web page only when an assistive tool asks. `AXManualAccessibility` is for
    /// Chrome and Electron; `AXEnhancedUserInterface` is the one that others (Helium) answer to. wm turns the second one off
    /// and on again around its own moves (`AppWatcher.setFrame`), so the animations do not slow down. Asked once for each app:
    /// returns `true` when it asked now, after a wait for the tree.
    private func enableWebContent(_ app: AXUIElement, pid: pid_t) -> Bool {
        guard prepared.insert(pid).inserted else { return false }
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        Thread.sleep(forTimeInterval: 0.4)
        return true
    }

    /// The apps that own an item of the menu bar on the right: they own windows at the status level.
    private static func statusItemPIDs() -> [pid_t] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let status = Int(CGWindowLevelForKey(.statusWindow))
        var pids = Set(list.compactMap { entry -> pid_t? in
            guard (entry[kCGWindowLayer as String] as? Int) == status, let owner = entry[kCGWindowOwnerPID as String] as? Int else { return nil }
            return pid_t(owner)
        })
        for bundle in ["com.apple.systemuiserver", "com.apple.controlcenter"] {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundle) { pids.insert(app.processIdentifier) }
        }
        return pids.sorted()
    }

    // MARK: - Walking

    /// Returns the text of the subtree, so a link or a button without a title is found by the text inside it.
    @discardableResult
    private func visit(_ element: AXUIElement, clip: CGRect, depth: Int) -> String {
        guard budget > 0, depth <= Self.maxDepth else { return "" }
        budget -= 1
        let node = read(element)
        // A menu that is closed has no place on the screen, and a subtree outside of its clip cannot be seen.
        if node.role == "AXMenu" { return "" }
        if node.role == "AXWebArea", node.children.isEmpty { sawEmptyWebArea = true }
        if let frame = node.frame, !frame.isEmpty, !frame.intersects(clip) { return "" }
        var childClip = clip
        if Self.scrollRoles.contains(node.role), let frame = node.frame { childClip = clip.intersection(frame) }
        var text = node.text
        var inside = ""
        for child in node.children {
            let childText = visit(child, clip: childClip, depth: depth + 1)
            if inside.count < Self.maxText { inside += " " + childText }
        }
        if text.isEmpty { text = inside }
        if Self.targetRoles.contains(node.role), node.enabled, let frame = node.frame {
            add(role: node.role, frame: frame.intersection(clip), text: text)
        }
        return String(text.prefix(Self.maxText))
    }

    private static let maxText = 120

    /// The items of the menu bar of an app, or of its extras. The menus under them are not read.
    private func visitBarItems(of bar: AXUIElement) {
        for item in read(bar).children {
            let node = read(item)
            if node.role == "AXMenuBarItem", node.enabled, let frame = node.frame { add(role: node.role, frame: frame, text: node.text) }
        }
    }

    /// The items of the Dock: the list is the first child of the Dock.
    private func visitDock(_ dock: AXUIElement) {
        for list in read(dock).children {
            for item in read(list).children {
                let node = read(item)
                if node.role == "AXDockItem", let frame = node.frame { add(role: node.role, frame: frame, text: node.text) }
            }
        }
    }

    private func collectScrollAreas(_ element: AXUIElement, clip: CGRect, depth: Int) {
        guard budget > 0, depth <= Self.maxDepth else { return }
        budget -= 1
        let node = read(element)
        if node.role == "AXMenu" { return }
        if node.role == "AXWebArea", node.children.isEmpty { sawEmptyWebArea = true }
        var childClip = clip
        if let frame = node.frame, !frame.isEmpty {
            if !frame.intersects(clip) { return }
            if Self.scrollRoles.contains(node.role) {
                childClip = clip.intersection(frame)
                if childClip.width >= Self.minScrollSide, childClip.height >= Self.minScrollSide { areas.append(childClip) }
            }
        }
        for child in node.children { collectScrollAreas(child, clip: childClip, depth: depth + 1) }
    }

    /// Keeps the element when it has a visible size, and (for `screens`) lies on a display.
    private func add(role: String, frame: CGRect, text: String) {
        guard frame.width >= 1, frame.height >= 1 else { return }
        if !screens.isEmpty, !screens.contains(where: { $0.contains(CGPoint(x: frame.midX, y: frame.midY)) }) { return }
        found.append(HintElement(id: nextID, frame: frame, role: role, text: text))
        nextID += 1
    }

    // MARK: - Attributes

    /// The attributes of a node in one call, because each call to a slow app costs a round trip.
    private func read(_ element: AXUIElement) -> Node {
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, Self.attributeNames as CFArray, [], &values) == .success,
              let list = values as? [CFTypeRef], list.count == Self.attributeNames.count else { return Node() }
        func value(_ slot: Slot) -> CFTypeRef? {
            let item = list[slot.rawValue]
            // A missing attribute comes back as an AXValue of the error type.
            if CFGetTypeID(item) == AXValueGetTypeID(), AXValueGetType(item as! AXValue) == .axError { return nil }
            return item
        }
        var node = Node()
        node.role = value(.role) as? String ?? ""
        node.text = [.title, .description, .value, .help]
            .compactMap { value($0) as? String }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        node.text = String(node.text.prefix(Self.maxText))
        node.enabled = (value(.enabled) as? Bool) ?? true
        if let position = value(.position), let size = value(.size),
           CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
            var origin = CGPoint.zero
            var extent = CGSize.zero
            if AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent) {
                node.frame = CGRect(origin: origin, size: extent)
            }
        }
        // A table shows a few rows at a time: ask for those, not for the thousands that are off the screen. Only a table has
        // them: Chromium answers an empty list for a web area, and that would hide the whole page.
        let visible = Self.rowRoles.contains(node.role) ? value(.visibleRows) as? [AXUIElement] : nil
        node.children = visible.flatMap { $0.isEmpty ? nil : $0 } ?? (value(.children) as? [AXUIElement]) ?? []
        return node
    }

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    // MARK: - Events

    /// Clicks at `point`. `clickState` is 2 for the second click of a double click. The events carry `EventTap.ownEventTag`.
    public static func click(at point: CGPoint, button: MouseButton, flags: CGEventFlags = [], clickState: Int = 1) {
        let source = CGEventSource(stateID: .hidSystemState)
        let (down, up, other): (CGEventType, CGEventType, CGMouseButton) = button == .right
            ? (.rightMouseDown, .rightMouseUp, .right) : (.leftMouseDown, .leftMouseUp, .left)
        let moved = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        moved?.setIntegerValueField(.eventSourceUserData, value: EventTap.ownEventTag)
        moved?.post(tap: .cghidEventTap)
        for type in [down, up] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: other) else { continue }
            event.flags = flags
            event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
            event.setIntegerValueField(.eventSourceUserData, value: EventTap.ownEventTag)
            event.post(tap: .cghidEventTap)
        }
    }

    /// Scrolls the view under `point`. A positive `dy` scrolls down and a positive `dx` scrolls right, in points.
    public static func scroll(at point: CGPoint, dx: Double, dy: Double) {
        // The wheel counts the other way: a positive value moves the content down and to the right.
        guard let event = CGEvent(
            scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState), units: .pixel, wheelCount: 2,
            wheel1: Int32(clamping: Int((-dy).rounded())), wheel2: Int32(clamping: Int((-dx).rounded())), wheel3: 0) else { return }
        event.location = point
        event.setIntegerValueField(.eventSourceUserData, value: EventTap.ownEventTag)
        event.post(tap: .cghidEventTap)
    }
}
