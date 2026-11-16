import AppKit
import Core

/// One click-through window that draws a rounded outline around a frame.
@MainActor
public final class BorderOverlay {
    private let window: NSWindow
    private let shape = CAShapeLayer()

    public init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView()
        view.wantsLayer = true
        view.layer?.addSublayer(shape)
        window.contentView = view
        shape.fillColor = nil
    }

    /// `frame` is the window to outline, in Accessibility coordinates. The line is drawn just outside it.
    public func show(around frame: CGRect, _ settings: BorderSettings) {
        let outer = Displays.cocoaRect(frame.insetBy(dx: -settings.width, dy: -settings.width))
        window.setFrame(outer, display: false)
        let bounds = CGRect(origin: .zero, size: outer.size)
        shape.frame = bounds
        shape.lineWidth = settings.width
        shape.strokeColor = Self.cgColor(settings.active)
        let path = CGPath(
            roundedRect: bounds.insetBy(dx: settings.width / 2, dy: settings.width / 2),
            cornerWidth: settings.radius, cornerHeight: settings.radius, transform: nil
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.path = path
        CATransaction.commit()
        window.orderFrontRegardless()
    }

    public func hide() {
        window.orderOut(nil)
    }

    private static func cgColor(_ color: Color) -> CGColor {
        CGColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}
