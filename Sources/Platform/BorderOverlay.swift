import AppKit
import Core

/// One click-through window that draws a rounded outline around a frame.
@MainActor
public final class BorderOverlay {
    private let window: NSWindow
    private let shape = CAShapeLayer()
    /// A gradient border is a gradient that only shows through the outline: the mask is the same stroke as `shape`.
    private let gradient = CAGradientLayer()
    private let gradientMask = CAShapeLayer()
    private var shown: (size: CGSize, settings: BorderSettings)?

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
        view.layer?.addSublayer(gradient)
        window.contentView = view
        shape.fillColor = nil
        gradient.mask = gradientMask
        gradientMask.fillColor = nil
        gradientMask.strokeColor = CGColor(gray: 0, alpha: 1)
    }

    /// `frame` is the window to outline, in Accessibility coordinates. The line is drawn just outside it.
    public func show(around frame: CGRect, _ settings: BorderSettings) {
        let outer = Displays.cocoaRect(frame.insetBy(dx: -settings.width, dy: -settings.width))
        if let shown, shown.size == outer.size, shown.settings == settings, window.isVisible {
            window.setFrameOrigin(outer.origin)
            return
        }
        shown = (outer.size, settings)
        window.setFrame(outer, display: false)
        let bounds = CGRect(origin: .zero, size: outer.size)
        let path = CGPath(
            roundedRect: bounds.insetBy(dx: settings.width / 2, dy: settings.width / 2),
            cornerWidth: settings.radius, cornerHeight: settings.radius, transform: nil
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if settings.gradient.count >= 2 {
            shape.isHidden = true
            gradient.isHidden = false
            gradient.frame = bounds
            gradient.colors = settings.gradient.map(Self.cgColor)
            let points = BorderGradient.points(angle: settings.angle)
            gradient.startPoint = points.start
            gradient.endPoint = points.end
            gradientMask.frame = bounds
            gradientMask.lineWidth = settings.width
            gradientMask.path = path
        } else {
            gradient.isHidden = true
            shape.isHidden = false
            shape.frame = bounds
            shape.lineWidth = settings.width
            shape.strokeColor = Self.cgColor(settings.active)
            shape.path = path
        }
        CATransaction.commit()
        window.orderFrontRegardless()
    }

    public func hide() {
        shown = nil
        window.orderOut(nil)
    }

    private static func cgColor(_ color: Color) -> CGColor {
        CGColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}
