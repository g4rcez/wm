import AppKit
import ApplicationServices
import Core
import Foundation
import PrivateApi

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
    static let maxNodes = 6000
    static let maxDepth = 40
    /// Smaller scroll areas are not worth a number.
    private static let minScrollSide: CGFloat = 40

    private static let targetRoles: Set<String> = [
        "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXMenuBarItem", "AXTextField",
        "AXTextArea", "AXComboBox", "AXDisclosureTriangle", "AXSlider", "AXIncrementor", "AXRow", "AXTab", "AXDockItem",
    ]
    private static let rowRoles: Set<String> = ["AXTable", "AXOutline"]
    static let scrollRoles: Set<String> = ["AXScrollArea", "AXWebArea"]
    /// The order is the one of `Slot`.
    private static let attributeNames: [String] = [
        kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute, kAXPositionAttribute,
        kAXSizeAttribute, kAXEnabledAttribute, kAXChildrenAttribute, "AXVisibleRows", kAXSubroleAttribute,
    ]

    private enum Slot: Int { case role, title, description, value, help, position, size, enabled, children, visibleRows, subrole }

    struct Node {
        var role = ""
        var subrole = ""
        /// Title, description, value and help, cut to `maxText`: what the search of the hints looks at.
        var text = ""
        /// The title and the value alone, not cut: the text that the element shows.
        var title = ""
        var value = ""
        var frame: CGRect?
        var enabled = true
        var children: [AXUIElement] = []
    }

    let thread = AXThread(name: "wm-hints")
    /// The rest is used on the thread only.
    var budget = 0
    private var nextID = 0
    private var found: [HintElement] = []
    private var areas: [CGRect] = []
    private var screens: [CGRect] = []
    /// The frames of the windows that were read and are in front of the next one.
    private var occluders: [CGRect] = []
    /// A web area with no children was seen: the app has not built the tree of its page.
    var sawEmptyWebArea = false
    /// Apps that were asked for their web content tree.
    private var prepared: Set<pid_t> = []

    public init() {}

    // MARK: - Reading

    /// The clickable elements of the app `pid`, and of the menu bar, the menu extras and the Dock. With `allWindows` the
    /// elements of every window that shows on the screen; without it, of the focused window of the app only.
    /// `screens` are the frames of the displays: an element outside of them is not on the screen.
    public func clickables(pid: pid_t, screens: [CGRect], allWindows: Bool) async -> [HintElement] {
        await thread.run { [self] in readClickables(pid: pid, screens: screens, allWindows: allWindows) }
    }

    /// The focused window of the app `pid` and its scroll areas, or `nil` when the app has no focused window.
    public func scrollTarget(pid: pid_t) async -> ScrollTarget? {
        await thread.run { [self] in readScrollTarget(pid: pid) }
    }

    private func readClickables(pid: pid_t, screens: [CGRect], allWindows: Bool) -> [HintElement] {
        let app = application(pid)
        reset(screens: screens)
        if allWindows {
            walkVisibleWindows(screens: screens)
        } else {
            walkWindow(of: app)
            // A browser builds the tree of a page only for an assistive tool. After the ask, the walk goes again.
            if sawEmptyWebArea, enableWebContent(app, pid: pid) {
                reset(screens: screens)
                walkWindow(of: app)
            }
        }
        // The bars and the Dock are in front of the windows.
        occluders = []
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        if let bar: AXUIElement = attribute(app, kAXMenuBarAttribute) { visitBarItems(of: bar, system: system) }
        for extras in Self.statusItemPIDs() {
            let owner = application(extras, timeout: 0.25)
            if let bar: AXUIElement = attribute(owner, "AXExtrasMenuBar") { visitBarItems(of: bar, system: system) }
        }
        if let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
            visitDock(application(dock.processIdentifier))
        }
        return found
    }

    private func walkWindow(of app: AXUIElement) {
        if let window = focusedWindow(of: app), let frame = read(window).frame { visit(window, clip: frame, depth: 0) }
    }

    /// Every window that shows on a display, the one in front first. An element under a window in front is not clickable, so
    /// it gets no label. Each window has its own node budget, so a window behind is not left with nothing.
    private func walkVisibleWindows(screens: [CGRect]) {
        let own = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let shown = list.compactMap { entry -> (id: CGWindowID, pid: pid_t, frame: CGRect)? in
            guard (entry[kCGWindowLayer as String] as? Int) == 0, let pid = entry[kCGWindowOwnerPID as String] as? Int, pid_t(pid) != own,
                  let id = entry[kCGWindowNumber as String] as? Int, let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.width >= 40, frame.height >= 40 else { return nil }
            return (CGWindowID(id), pid_t(pid), frame)
        }
        // Only a window that the Accessibility API knows counts: an app can have a clear window over the whole display.
        var elements: [CGWindowID: AXUIElement] = [:]
        for pid in Set(shown.map(\.pid)) {
            let windows: [AXUIElement] = attribute(application(pid), kAXWindowsAttribute) ?? []
            for window in windows {
                var id: CGWindowID = 0
                if _AXUIElementGetWindow(window, &id) == .success { elements[id] = window }
            }
        }
        for window in shown {
            guard let element = elements[window.id], !occluders.contains(where: { $0.contains(window.frame) }) else { continue }
            let start = found.count
            func walk() {
                budget = Self.maxNodes
                sawEmptyWebArea = false
                visit(element, clip: window.frame, depth: 0)
            }
            walk()
            // A browser builds the tree of a page only for an assistive tool. After the ask, the walk goes again.
            if sawEmptyWebArea, enableWebContent(application(window.pid), pid: window.pid) {
                found.removeSubrange(start...)
                walk()
            }
            occluders.append(window.frame)
        }
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
        occluders = []
        areas = []
        sawEmptyWebArea = false
        self.screens = screens
    }

    func application(_ pid: pid_t, timeout: Float = 1) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        return app
    }

    private func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        attribute(app, kAXFocusedWindowAttribute) ?? attribute(app, kAXMainWindowAttribute)
    }

    /// Chromium and Electron build the tree of a web page only when an assistive tool asks. `AXManualAccessibility` is for
    /// Chrome and Electron; `AXEnhancedUserInterface` is the one that others (Helium) answer to. wm turns the second one off
    /// and on again around its own moves (`AppWatcher.setFrame`), so the animations do not slow down. Asked once for each app:
    /// returns `true` when it asked now, after a wait for the tree.
    func enableWebContent(_ app: AXUIElement, pid: pid_t) -> Bool {
        guard prepared.insert(pid).inserted else { return false }
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        Thread.sleep(forTimeInterval: 0.4)
        return true
    }

    /// The apps that can own an item of the menu bar on the right. Current macOS has no windows at the status level for them,
    /// so every app that is not a background daemon is asked (the system items belong to `MenuBarAgent`, an accessory app).
    /// The owners of status windows and the two system UI apps stay, for the macOS that still uses them.
    private static func statusItemPIDs() -> [pid_t] {
        var pids = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy != .prohibited }.map(\.processIdentifier))
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let status = Int(CGWindowLevelForKey(.statusWindow))
        for entry in list where (entry[kCGWindowLayer as String] as? Int) == status {
            if let owner = entry[kCGWindowOwnerPID as String] as? Int { pids.insert(pid_t(owner)) }
        }
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
    private func visitBarItems(of bar: AXUIElement, system: AXUIElement) {
        visitBarChildren(read(bar).children, system: system, depth: 0)
    }

    /// The system items sit in a hosting group, so the walk goes two levels down. A button that is a child of the bar itself
    /// (the one that shows the hidden items) counts too.
    private func visitBarChildren(_ children: [AXUIElement], system: AXUIElement, depth: Int) {
        for item in children {
            let node = read(item)
            if node.role == "AXMenu" { continue }
            if node.role == "AXMenuBarItem" || (node.role == "AXButton" && depth == 0) {
                if node.enabled, let frame = node.frame, isShown(item, frame: frame, system: system) {
                    add(role: node.role, frame: frame, text: node.text)
                }
            } else if depth < 2 {
                visitBarChildren(node.children, system: system, depth: depth + 1)
            }
        }
    }

    /// An item that the menu bar hides (behind the button for the hidden items, or under the notch) still has a frame, but the
    /// element at its center is another one. When the check fails, the item stays.
    private func isShown(_ item: AXUIElement, frame: CGRect, system: AXUIElement) -> Bool {
        var owner: pid_t = 0
        var hit: AXUIElement?
        guard AXUIElementGetPid(item, &owner) == .success,
              AXUIElementCopyElementAtPosition(system, Float(frame.midX), Float(frame.midY), &hit) == .success, let hit else { return true }
        var other: pid_t = 0
        return AXUIElementGetPid(hit, &other) != .success || other == owner
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
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if !screens.isEmpty, !screens.contains(where: { $0.contains(center) }) { return }
        if occluders.contains(where: { $0.contains(center) }) { return }
        found.append(HintElement(id: nextID, frame: frame, role: role, text: text))
        nextID += 1
    }

    // MARK: - Attributes

    /// The attributes of a node in one call, because each call to a slow app costs a round trip.
    func read(_ element: AXUIElement) -> Node {
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
        node.subrole = value(.subrole) as? String ?? ""
        node.title = value(.title) as? String ?? ""
        node.value = value(.value) as? String ?? ""
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

    func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
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
