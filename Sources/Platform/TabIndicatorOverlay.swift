import AppKit
import Core

/// One click-through window with a bar of segments at the edge of a column, one segment per tab. Like the border, it
/// is a separate window above the others, so it covers a few points of the window under it.
@MainActor
public final class TabIndicatorOverlay {
    /// Space between the bar and the corners of the column.
    private static let margin: CGFloat = 12
    /// Space between the bar and the edge of the column.
    private static let inset: CGFloat = 4

    private let window: NSWindow
    private var segments: [CALayer] = []

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
        window.contentView = view
    }

    /// `frame` is the column in Accessibility coordinates; `selected` is the segment of the focused window.
    public func show(on frame: CGRect, count: Int, selected: Int, _ settings: TabIndicatorSettings) {
        guard count > 1, let rect = Self.rect(of: frame, settings) else { return hide() }
        let vertical = settings.position == .left || settings.position == .right
        let length = vertical ? rect.height : rect.width
        let gaps = settings.spacing * CGFloat(count - 1)
        let segment = (length - gaps) / CGFloat(count)
        guard segment >= 1 else { return hide() }

        window.setFrame(Displays.cocoaRect(rect), display: false)
        guard let root = window.contentView?.layer else { return }
        while segments.count < count {
            let layer = CALayer()
            root.addSublayer(layer)
            segments.append(layer)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, layer) in segments.enumerated() {
            layer.isHidden = index >= count
            guard index < count else { continue }
            let offset = CGFloat(index) * (segment + settings.spacing)
            // The first tab is at the top of a vertical bar and at the left of a horizontal one. Layer
            // coordinates start at the bottom left.
            layer.frame = vertical
                ? CGRect(x: 0, y: rect.height - offset - segment, width: rect.width, height: segment)
                : CGRect(x: offset, y: 0, width: segment, height: rect.height)
            layer.cornerRadius = min(settings.radius, min(layer.frame.width, layer.frame.height) / 2)
            layer.backgroundColor = Self.cgColor(index == selected ? settings.active : settings.inactive)
        }
        CATransaction.commit()
        window.orderFrontRegardless()
    }

    public func hide() {
        window.orderOut(nil)
    }

    /// Where the bar goes for a column frame, or `nil` when the column is too small for it.
    static func rect(of frame: CGRect, _ settings: TabIndicatorSettings) -> CGRect? {
        let size = settings.size
        let rect: CGRect
        switch settings.position {
        case .left:
            rect = CGRect(x: frame.minX + inset, y: frame.minY + margin, width: size, height: frame.height - 2 * margin)
        case .right:
            rect = CGRect(x: frame.maxX - inset - size, y: frame.minY + margin, width: size, height: frame.height - 2 * margin)
        case .top:
            rect = CGRect(x: frame.minX + margin, y: frame.minY + inset, width: frame.width - 2 * margin, height: size)
        case .bottom:
            rect = CGRect(x: frame.minX + margin, y: frame.maxY - inset - size, width: frame.width - 2 * margin, height: size)
        }
        return rect.width >= 1 && rect.height >= 1 ? rect : nil
    }

    private static func cgColor(_ color: Color) -> CGColor {
        CGColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}
