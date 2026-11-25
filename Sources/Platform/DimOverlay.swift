import AppKit
import Core

/// A window to dim: where it is and the color to lay over it, whose alpha is how dark it gets.
public struct DimTarget {
    public var id: WindowID
    public var frame: CGRect
    public var color: Color
    public var radius: CGFloat

    public init(id: WindowID, frame: CGRect, color: Color, radius: CGFloat) {
        self.id = id
        self.frame = frame
        self.color = color
        self.radius = radius
    }
}

/// One click-through layer over each dimmed window. Each sits directly above its own window, so a window in front of that
/// one covers the layer too and stays bright.
@MainActor
public final class DimOverlay {
    private var windows: [WindowID: NSWindow] = [:]

    public init() {}

    /// Shows exactly these layers. `reorder` puts them above their windows again, after something may have raised one; a
    /// layer that is new is always ordered.
    public func show(_ targets: [DimTarget], reorder: Bool) {
        let wanted = Set(targets.map(\.id))
        for (id, window) in windows where !wanted.contains(id) {
            window.orderOut(nil)
            windows[id] = nil
        }
        for target in targets {
            let isNew = windows[target.id] == nil
            let window = windows[target.id] ?? Self.makeWindow()
            windows[target.id] = window
            if let layer = window.contentView?.layer {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.backgroundColor = CGColor(
                    srgbRed: target.color.red, green: target.color.green, blue: target.color.blue, alpha: target.color.alpha)
                layer.cornerRadius = target.radius
                CATransaction.commit()
            }
            window.setFrame(Displays.cocoaRect(target.frame), display: false)
            if reorder || isNew { window.order(.above, relativeTo: Int(target.id)) }
        }
    }

    private static func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView?.wantsLayer = true
        return window
    }
}
