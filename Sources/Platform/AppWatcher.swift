import AppKit
import ApplicationServices
import Core
import PrivateApi

/// Watches one application through the Accessibility API. Every AX call runs on the watcher's own thread.
public final class AppWatcher: @unchecked Sendable {
    public let pid: pid_t
    private let thread: AXThread
    private let onChange: @Sendable (pid_t) -> Void
    private let bundleID: String
    private let appName: String

    // Confined to `thread` from here on.
    private var app: AXUIElement?
    private var observer: AXObserver?
    private var elements: [WindowID: AXUIElement] = [:]
    private var observed: Set<WindowID> = []
    private var lastSize: [WindowID: CGSize] = [:]
    /// Whether a title change of a window is reported (see `watchTitles`).
    private var titleWatching = false

    private static let appNotifications = [
        kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
    ]
    private static let windowNotifications = [
        kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
    ]

    public var bundleIdentifier: String { bundleID }
    public var name: String { appName }

    public init(application: NSRunningApplication, onChange: @escaping @Sendable (pid_t) -> Void) {
        pid = application.processIdentifier
        bundleID = application.bundleIdentifier ?? ""
        appName = application.localizedName ?? ""
        self.onChange = onChange
        thread = AXThread(name: "ax-\(application.processIdentifier)")
        thread.async { [self] in setUp() }
    }

    private func setUp() {
        let element = AXUIElementCreateApplication(pid)
        // A hung app must fail fast instead of blocking its thread for the default 6 seconds.
        AXUIElementSetMessagingTimeout(element, 1)
        app = element

        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            let watcher = Unmanaged<AppWatcher>.fromOpaque(context).takeUnretainedValue()
            watcher.onChange(watcher.pid)
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        observer = created
        CFRunLoopAddSource(thread.runLoop, AXObserverGetRunLoopSource(created), .defaultMode)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.appNotifications {
            AXObserverAddNotification(created, element, name as CFString, context)
        }
    }

    /// Reports a change of the title of any window of the app, as it happens, and not at the next refresh. A browser changes its title
    /// all the time and every report reads all windows again, so it is on only for the apps that a dynamic rule needs.
    public func watchTitles(_ enabled: Bool) {
        thread.async { [self] in
            guard enabled != titleWatching else { return }
            titleWatching = enabled
            guard let observer else { return }
            let context = Unmanaged.passUnretained(self).toOpaque()
            for id in observed {
                guard let window = elements[id] else { continue }
                if enabled {
                    AXObserverAddNotification(observer, window, kAXTitleChangedNotification as CFString, context)
                } else {
                    AXObserverRemoveNotification(observer, window, kAXTitleChangedNotification as CFString)
                }
            }
        }
    }

    public func stop() {
        thread.async { [self] in
            if let observer {
                CFRunLoopRemoveSource(thread.runLoop, AXObserverGetRunLoopSource(observer), .defaultMode)
            }
            observer = nil
            app = nil
            elements = [:]
            thread.stop()
        }
    }

    /// All windows of the app with their current attributes. `nil` when the app cannot be read now (busy, just woken):
    /// that says nothing about its windows.
    public func snapshot() async -> [WindowInfo]? {
        await thread.run { [self] in readWindows() }
    }

    /// Only the frames of the windows: 2 AX reads per window instead of the 8 of `snapshot`. It leaves the watcher's
    /// window bookkeeping alone, so it cannot replace `snapshot` for the refresh.
    public func frames() async -> [WindowID: CGRect] {
        await thread.run { [self] in
            guard let app, let list: [AXUIElement] = attribute(app, kAXWindowsAttribute) else { return [:] }
            var result: [WindowID: CGRect] = [:]
            for window in list {
                guard let id = windowID(window) else { continue }
                result[id] = CGRect(
                    origin: point(window, kAXPositionAttribute) ?? .zero, size: size(window, kAXSizeAttribute) ?? .zero
                )
            }
            return result
        }
    }

    public func focusedWindow() async -> WindowID? {
        await thread.run { [self] in
            guard let app, let window: AXUIElement = attribute(app, kAXFocusedWindowAttribute) else { return nil }
            return windowID(window)
        }
    }

    /// Moves and resizes a window. `completion` runs on the watcher thread when the AX calls are done, with the
    /// time they took in seconds.
    public func setFrame(_ id: WindowID, _ frame: CGRect, completion: @escaping @Sendable (Double) -> Void) {
        thread.async { [self] in
            let start = DispatchTime.now().uptimeNanoseconds
            defer { completion(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9) }
            guard let app, let window = elements[id] else { return }
            // Apps with "enhanced user interface" animate AX moves themselves, which fights the animator.
            let enhanced: Bool? = attribute(app, "AXEnhancedUserInterface")
            if enhanced == true { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
            defer {
                if enhanced == true { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
            }
            // Size, position, size: some apps clamp a size change against the old position (AeroSpace #143).
            if lastSize[id] != frame.size {
                setValue(window, kAXSizeAttribute, frame.size)
                setValue(window, kAXPositionAttribute, frame.origin)
                setValue(window, kAXSizeAttribute, frame.size)
                lastSize[id] = frame.size
            } else {
                setValue(window, kAXPositionAttribute, frame.origin)
            }
        }
    }

    /// Forgets the size that `setFrame` set last, so the next call writes size, position and size again. For a window whose real
    /// size changed behind wm's back.
    public func forgetSize(_ id: WindowID) {
        thread.async { [self] in lastSize[id] = nil }
    }

    public func raise(_ id: WindowID) {
        thread.async { [self] in
            guard let app, let window = elements[id] else { return }
            AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
    }

    /// Enters or leaves macOS fullscreen (the window gets a Space of its own).
    public func setFullscreen(_ id: WindowID, _ on: Bool) {
        thread.async { [self] in
            guard let window = elements[id] else { return }
            AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, on ? kCFBooleanTrue : kCFBooleanFalse)
        }
    }

    public func close(_ id: WindowID) {
        thread.async { [self] in
            guard let window = elements[id],
                  let button: AXUIElement = attribute(window, kAXCloseButtonAttribute) else { return }
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }

    public func minimize(_ id: WindowID) {
        thread.async { [self] in
            guard let window = elements[id] else { return }
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        }
    }

    // MARK: - AX helpers (watcher thread only)

    private func readWindows() -> [WindowInfo]? {
        guard let app, let list: [AXUIElement] = attribute(app, kAXWindowsAttribute) else { return nil }
        var infos: [WindowInfo] = []
        var alive: Set<WindowID> = []
        for window in list {
            guard let id = windowID(window) else { continue }
            alive.insert(id)
            elements[id] = window
            subscribe(window, id)
            let position: CGPoint = point(window, kAXPositionAttribute) ?? .zero
            let size: CGSize = size(window, kAXSizeAttribute) ?? .zero
            infos.append(WindowInfo(
                id: id,
                pid: pid,
                bundleID: bundleID,
                appName: appName,
                title: attribute(window, kAXTitleAttribute) ?? "",
                role: attribute(window, kAXRoleAttribute) ?? "",
                subrole: attribute(window, kAXSubroleAttribute) ?? "",
                identifier: attribute(window, "AXIdentifier") ?? "",
                frame: CGRect(origin: position, size: size),
                isMinimized: attribute(window, kAXMinimizedAttribute) ?? false,
                isFullscreen: attribute(window, "AXFullScreen") ?? false
            ))
        }
        elements = elements.filter { alive.contains($0.key) }
        observed.formIntersection(alive)
        lastSize = lastSize.filter { alive.contains($0.key) }
        return infos
    }

    private func subscribe(_ window: AXUIElement, _ id: WindowID) {
        guard let observer, !observed.contains(id) else { return }
        observed.insert(id)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.windowNotifications {
            AXObserverAddNotification(observer, window, name as CFString, context)
        }
        if titleWatching { AXObserverAddNotification(observer, window, kAXTitleChangedNotification as CFString, context) }
    }

    private func windowID(_ window: AXUIElement) -> WindowID? {
        var id: UInt32 = 0
        return _AXUIElementGetWindow(window, &id) == .success && id != 0 ? id : nil
    }

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private func point(_ element: AXUIElement, _ name: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var result = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &result) ? result : nil
    }

    private func size(_ element: AXUIElement, _ name: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var result = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &result) ? result : nil
    }

    private func setValue(_ element: AXUIElement, _ name: String, _ point: CGPoint) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(element, name as CFString, value)
    }

    private func setValue(_ element: AXUIElement, _ name: String, _ size: CGSize) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(element, name as CFString, value)
    }
}
