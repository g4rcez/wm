import AppKit
import Core

/// A label on an element.
public struct HintBadge: Sendable, Equatable {
    /// The frame of the element.
    public var frame: CGRect
    public var label: String
    /// How many letters of the label are typed. All of the label is dimmed when `dimmed` is set: it does not start with them.
    public var typed: Int
    public var dimmed: Bool
    public var focused: Bool

    public init(frame: CGRect, label: String, typed: Int = 0, dimmed: Bool = false, focused: Bool = false) {
        self.frame = frame
        self.label = label
        self.typed = typed
        self.dimmed = dimmed
        self.focused = focused
    }
}

/// A scroll area, with its number.
public struct AreaBadge: Sendable, Equatable {
    public var frame: CGRect
    public var number: Int
    public var active: Bool

    public init(frame: CGRect, number: Int, active: Bool) {
        self.frame = frame
        self.number = number
        self.active = active
    }
}

/// A giant number in the middle of a window (`wm jump`).
public struct WindowLabel: Sendable, Equatable {
    public var frame: CGRect
    public var text: String
    public var focused: Bool
    /// The number does not start with the digits typed: it is faded.
    public var dimmed: Bool

    public init(frame: CGRect, text: String, focused: Bool = false, dimmed: Bool = false) {
        self.frame = frame
        self.text = text
        self.focused = focused
        self.dimmed = dimmed
    }
}

public struct HintContent: Sendable, Equatable {
    public var badges: [HintBadge] = []
    public var windowLabels: [WindowLabel] = []
    public var areas: [AreaBadge] = []
    /// The select mode: the places of the search text, and the lines of the selection.
    public var matches: [CGRect] = []
    public var selection: [CGRect] = []
    /// A line of text in a pill, on the display that holds `noteAnchor` (the center of the window).
    public var note: String?
    public var noteAnchor: CGPoint = .zero
    public var colors = HintSettings()

    public init(
        badges: [HintBadge] = [], areas: [AreaBadge] = [], windowLabels: [WindowLabel] = [], note: String? = nil, noteAnchor: CGPoint = .zero,
        colors: HintSettings = HintSettings()
    ) {
        self.colors = colors
        self.windowLabels = windowLabels
        self.badges = badges
        self.areas = areas
        self.note = note
        self.noteAnchor = noteAnchor
    }
}

/// Labels on top of everything, one click-through panel on each display. All coordinates are screen coordinates, origin at the top
/// left. The keys go to the event tap, never to these panels.
@MainActor
public final class HintOverlay {
    private var panels: [UInt32: (panel: HintPanel, view: HintView)] = [:]

    public init() {}

    public var isShown: Bool { !panels.isEmpty }

    public func show(_ content: HintContent) {
        let displays = Displays.all()
        for id in panels.keys where !displays.contains(where: { $0.id == id }) {
            panels.removeValue(forKey: id)?.panel.orderOut(nil)
        }
        for display in displays {
            let entry = panels[display.id] ?? makePanel()
            panels[display.id] = entry
            entry.panel.setFrame(Displays.cocoaRect(display.frame), display: false)
            entry.view.display = display.frame
            entry.view.content = content
            entry.view.needsDisplay = true
            entry.panel.orderFrontRegardless()
        }
    }

    public func hide() {
        for entry in panels.values { entry.panel.orderOut(nil) }
        panels = [:]
    }

    private func makePanel() -> (panel: HintPanel, view: HintView) {
        let panel = HintPanel()
        let view = HintView()
        panel.contentView = view
        return (panel, view)
    }
}

private final class HintPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        // Above the menu bar, so its items can have labels too.
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Draws in screen coordinates, shifted by the frame of its display.
private final class HintView: NSView {
    var content = HintContent()
    var display = CGRect.zero

    override var isFlipped: Bool { true }

    private static let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
    private static let noteFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private var amber: NSColor { Self.nsColor(content.colors.background) }
    private var green: NSColor { Self.nsColor(content.colors.focus) }
    private var blue: NSColor { Self.nsColor(content.colors.area) }
    private var ink: NSColor { Self.nsColor(content.colors.text) }

    private static func nsColor(_ color: Color) -> NSColor {
        NSColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    private func local(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: -display.minX, dy: -display.minY) }

    override func draw(_ dirtyRect: NSRect) {
        for area in content.areas where area.frame.intersects(display) { draw(area) }
        for label in content.windowLabels where label.frame.intersects(display) { draw(label) }
        fill(content.matches, amber.withAlphaComponent(0.35))
        fill(content.selection, green.withAlphaComponent(0.45))
        // The focused one goes last, so nothing covers it.
        for badge in content.badges.sorted(by: { !$0.focused && $1.focused }) where badge.frame.intersects(display) { draw(badge) }
        if let note = content.note { drawNote(note) }
    }

    private func fill(_ rects: [CGRect], _ color: NSColor) {
        color.setFill()
        for rect in rects where rect.intersects(display) { NSBezierPath(roundedRect: local(rect), xRadius: 2, yRadius: 2).fill() }
    }

    private func draw(_ area: AreaBadge) {
        let frame = local(area.frame).insetBy(dx: 2, dy: 2)
        let color = area.active ? blue : blue.withAlphaComponent(0.5)
        let path = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)
        path.lineWidth = area.active ? 3 : 1.5
        color.setStroke()
        path.stroke()
        if area.active {
            blue.withAlphaComponent(0.08).setFill()
            path.fill()
        }
        pill("\(area.number)", at: CGPoint(x: frame.minX + 6, y: frame.minY + 6), fill: color, text: .white, font: Self.font)
    }

    /// A big number in a rounded box at the center of the window. The size follows the window, between 48 and 220 points.
    private func draw(_ label: WindowLabel) {
        let frame = local(label.frame)
        let size = min(max(min(frame.width, frame.height) * 0.3, 48), 220)
        let font = NSFont.systemFont(ofSize: size, weight: .heavy).withRoundedDesign()
        let fill = label.focused ? green : amber
        let alpha = label.dimmed ? 0.25 : 1.0
        let text = NSAttributedString(string: label.text, attributes: [.font: font, .foregroundColor: ink.withAlphaComponent(alpha)])
        let extent = text.size()
        let box = CGRect(
            x: frame.midX - (extent.width + size * 0.5) / 2, y: frame.midY - (extent.height + size * 0.2) / 2,
            width: max(extent.width + size * 0.5, extent.height + size * 0.2), height: extent.height + size * 0.2)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.4 * alpha)
        shadow.shadowBlurRadius = size * 0.15
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.04)
        shadow.set()
        fill.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: box, xRadius: size * 0.25, yRadius: size * 0.25).fill()
        NSGraphicsContext.restoreGraphicsState()
        text.draw(at: CGPoint(x: box.midX - extent.width / 2, y: box.midY - extent.height / 2))
    }

    private func draw(_ badge: HintBadge) {
        let frame = local(badge.frame)
        if badge.focused {
            let ring = NSBezierPath(roundedRect: frame.insetBy(dx: -1, dy: -1), xRadius: 4, yRadius: 4)
            ring.lineWidth = 2
            green.setStroke()
            ring.stroke()
        }
        // An element with no label (the search left too few letters) can still be the focused one: only the ring is drawn.
        guard !badge.label.isEmpty else { return }
        let text = NSMutableAttributedString(string: badge.label, attributes: [.font: Self.font, .foregroundColor: ink])
        if badge.dimmed {
            text.addAttribute(.foregroundColor, value: ink.withAlphaComponent(0.35), range: NSRange(location: 0, length: text.length))
        } else if badge.typed > 0 {
            text.addAttribute(
                .foregroundColor, value: ink.withAlphaComponent(0.35), range: NSRange(location: 0, length: min(badge.typed, text.length)))
        }
        let size = text.size()
        // The badge sits on the left edge of the element, in the middle, and never leaves the display.
        var origin = CGPoint(x: frame.minX - 2, y: frame.midY - (size.height + 4) / 2)
        origin.x = min(max(origin.x, 0), bounds.width - size.width - 8)
        origin.y = min(max(origin.y, 0), bounds.height - size.height - 4)
        let box = CGRect(x: origin.x, y: origin.y, width: size.width + 8, height: size.height + 4)
        let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
        (badge.focused ? green : amber).setFill()
        path.fill()
        NSColor.black.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 0.5
        path.stroke()
        text.draw(at: CGPoint(x: box.minX + 4, y: box.minY + 2))
    }

    /// The pill is on the display that holds the anchor, near the bottom, above the Dock.
    private func drawNote(_ note: String) {
        guard display.contains(content.noteAnchor) else { return }
        let text = NSAttributedString(string: note, attributes: [.font: Self.noteFont, .foregroundColor: NSColor.white])
        let size = text.size()
        let width = size.width + 24
        let box = CGRect(
            x: min(max(content.noteAnchor.x - display.minX - width / 2, 8), bounds.width - width - 8),
            y: bounds.height - size.height - 12 - 90, width: width, height: size.height + 12)
        NSColor(white: 0.1, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        text.draw(at: CGPoint(x: box.minX + 12, y: box.minY + 6))
    }

    private func pill(_ string: String, at origin: CGPoint, fill: NSColor, text color: NSColor, font: NSFont) {
        let text = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
        let size = text.size()
        let box = CGRect(x: origin.x, y: origin.y, width: max(size.width + 10, size.height + 4), height: size.height + 4)
        fill.setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        text.draw(at: CGPoint(x: box.midX - size.width / 2, y: box.minY + 2))
    }
}

private extension NSFont {
    /// The rounded design of the system font, when macOS has it.
    func withRoundedDesign() -> NSFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded), let font = NSFont(descriptor: descriptor, size: pointSize) else { return self }
        return font
    }
}
