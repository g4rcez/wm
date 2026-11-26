import AppKit
import Core

/// The placeholder of a tiled window that is being dragged: a translucent rounded panel in the slot where the window lands,
/// just behind the window itself, so the other windows stay under it. It ignores the mouse.
@MainActor
public final class MovePreviewOverlay {
    private let window: NSWindow
    private var shown: (frame: CGRect, radius: CGFloat)?

    public init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView()
        view.wantsLayer = true
        window.contentView = view
    }

    /// `frame` is the slot in Accessibility coordinates. `below` is the dragged window: the placeholder goes right behind it.
    public func show(_ frame: CGRect, radius: CGFloat, below windowID: WindowID) {
        if shown?.frame != frame || shown?.radius != radius {
            shown = (frame, radius)
            window.setFrame(Displays.cocoaRect(frame), display: false)
            guard let layer = window.contentView?.layer else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.cornerRadius = radius
            layer.cornerCurve = .continuous
            layer.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
            layer.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
            layer.borderWidth = 1
            CATransaction.commit()
        }
        window.order(.below, relativeTo: Int(windowID))
    }

    public func hide() {
        guard shown != nil else { return }
        shown = nil
        window.orderOut(nil)
    }
}
