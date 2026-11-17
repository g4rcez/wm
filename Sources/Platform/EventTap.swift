@preconcurrency import CoreGraphics
import Foundation

public enum ScrollPhase: Sendable { case began, changed, ended, none }

public enum MouseButton: Sendable { case left, right }
public enum MouseEventKind: Sendable { case down, dragged, up }

/// A mouse button press, drag step or release.
public struct MouseEvent: Sendable {
    public var kind: MouseEventKind
    public var button: MouseButton
    public var location: CGPoint
    public var flags: CGEventFlags
}

/// Session event taps for hotkeys, trackpad scrolling and (when asked for) pointer movement. All handlers run on the main thread.
/// A handler returns `true` to swallow the event.
public final class EventTap: @unchecked Sendable {
    public typealias KeyHandler = @MainActor (_ keyCode: Int, _ flags: CGEventFlags, _ isRepeat: Bool) -> Bool
    public typealias KeyUpHandler = @MainActor (_ keyCode: Int, _ flags: CGEventFlags) -> Bool
    public typealias ScrollHandler = @MainActor (_ dx: CGFloat, _ dy: CGFloat, _ flags: CGEventFlags, _ phase: ScrollPhase) -> Bool
    public typealias PointerHandler = @MainActor (_ location: CGPoint) -> Void
    public typealias ButtonHandler = @MainActor (_ isDown: Bool) -> Void
    /// Return `true` to swallow the event. The left button also goes to `onButton`, unless this swallows it.
    public typealias MouseHandler = @MainActor (_ event: MouseEvent) -> Bool
    public typealias FlagsHandler = @MainActor (_ flags: CGEventFlags) -> Void

    /// Events that this process posts carry this tag, so the tap lets them through.
    public static let ownEventTag: Int64 = 0x574D

    public var onKey: KeyHandler?
    /// A key came up. Return `true` when its key down was used, so apps do not see a lone key up.
    public var onKeyUp: KeyUpHandler?
    public var onScroll: ScrollHandler?
    public var onPointer: PointerHandler?
    /// Left mouse button pressed or released. The event is never swallowed.
    public var onButton: ButtonHandler?
    public var onMouse: MouseHandler?
    /// A modifier key changed. The event is never swallowed: apps would be left with stuck modifiers.
    public var onFlags: FlagsHandler?

    private var port: CFMachPort?
    /// A separate tap for pointer movement. It stays disabled unless something needs the pointer, so mouse moves do not
    /// wait for this process. It is a normal tap, not listen-only: that kind could need Input Monitoring permission.
    private var pointerPort: CFMachPort?
    private var pointerWanted = false

    /// Types a key. The event carries `ownEventTag`, so this tap does not treat it as a hotkey.
    public static func post(keyCode: Int, flags: CGEventFlags) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: down) else { return }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: ownEventTag)
            event.post(tap: .cghidEventTap)
        }
    }

    /// Types a key into one app, without moving the focus: `wm key send`. The app gets it even when it is in the background.
    public static func post(keyCode: Int, flags: CGEventFlags, toPID pid: pid_t) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: down) else { return }
            event.flags = flags
            event.postToPid(pid)
        }
    }

    /// The modifier keys that are down now.
    public static func currentFlags() -> CGEventFlags { CGEventSource.flagsState(.combinedSessionState) }

    public init() {}

    /// Returns `false` when macOS refuses the tap (Accessibility permission is missing).
    @MainActor public func start() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.scrollWheel.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.rightMouseUp.rawValue)
            | (1 << CGEventType.rightMouseDragged.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<EventTap>.fromOpaque(context).takeUnretainedValue()
            return MainActor.assumeIsolated { tap.handle(type, event) }
        }
        func create(_ events: CGEventMask) -> CFMachPort? {
            guard let created = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: events,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else { return nil }
            let source = CFMachPortCreateRunLoopSource(nil, created, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            return created
        }
        guard let created = create(mask) else { return false }
        port = created
        CGEvent.tapEnable(tap: created, enable: true)
        pointerPort = create(1 << CGEventType.mouseMoved.rawValue)
        setPointerTracking(pointerWanted)
        return true
    }

    /// Turns the delivery of pointer movement on or off. Safe to call before `start()`.
    @MainActor public func setPointerTracking(_ enabled: Bool) {
        pointerWanted = enabled
        if let pointerPort { CGEvent.tapEnable(tap: pointerPort, enable: enabled) }
    }

    @MainActor private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Keys that arrive while the tap is off go to macOS, not to the binds.
            if ProcessInfo.processInfo.environment["WM_DEBUG"] != nil {
                let reason = type == .tapDisabledByTimeout ? "timeout" : "user input"
                FileHandle.standardError.write(Data("wm: the event tap was disabled by macOS (\(reason))\n".utf8))
            }
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            if let pointerPort, pointerWanted { CGEvent.tapEnable(tap: pointerPort, enable: true) }
            return pass
        case .keyDown:
            guard event.getIntegerValueField(.eventSourceUserData) != Self.ownEventTag else { return pass }
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            return onKey?(code, event.flags, isRepeat) == true ? nil : pass
        case .keyUp:
            guard event.getIntegerValueField(.eventSourceUserData) != Self.ownEventTag else { return pass }
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            return onKeyUp?(code, event.flags) == true ? nil : pass
        case .scrollWheel:
            let phase: ScrollPhase = switch event.getIntegerValueField(.scrollWheelEventScrollPhase) {
            case 1: .began
            case 2: .changed
            case 4, 8: .ended
            default: .none
            }
            let dx = CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2))
            let dy = CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
            return onScroll?(dx, dy, event.flags, phase) == true ? nil : pass
        case .mouseMoved:
            onPointer?(event.location)
            return pass
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            let button: MouseButton = [.leftMouseDown, .leftMouseUp, .leftMouseDragged].contains(type) ? .left : .right
            let kind: MouseEventKind = [.leftMouseDown, .rightMouseDown].contains(type) ? .down
                : [.leftMouseUp, .rightMouseUp].contains(type) ? .up : .dragged
            if onMouse?(MouseEvent(kind: kind, button: button, location: event.location, flags: event.flags)) == true { return nil }
            if type == .leftMouseDown || type == .leftMouseUp { onButton?(type == .leftMouseDown) }
            return pass
        case .flagsChanged:
            onFlags?(event.flags)
            return pass
        default:
            return pass
        }
    }
}
