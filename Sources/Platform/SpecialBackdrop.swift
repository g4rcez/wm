import AppKit
import Core

/// A click-through dim layer on a monitor, behind every normal window: it dims the desktop around a shown special workspace.
@MainActor
public final class SpecialBackdrop {
    private var windows: [NSWindow] = []

    public init() {}

    /// One layer for each frame (Accessibility coordinates), or none when the color is clear.
    public func show(on frames: [CGRect], _ color: Color) {
        let wanted = color.alpha > 0 ? frames : []
        while windows.count > wanted.count { windows.removeLast().orderOut(nil) }
        while windows.count < wanted.count { windows.append(Self.makeWindow()) }
        for (window, frame) in zip(windows, wanted) {
            window.backgroundColor = NSColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
            window.setFrame(Displays.cocoaRect(frame), display: false)
            window.orderFrontRegardless()
        }
    }

    private static func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        // Below the normal windows, above the desktop.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.normalWindow)) - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        return window
    }
}
