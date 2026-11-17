import AppKit
import Core

/// The pictures of the split templates (the built-in ones are Ribbon's eight, with two wide ones) and the chain.
/// `nil` stands for the chain (no template).
public enum TemplateGlyph {
    /// The templates of a layout, then the chain.
    public static func entries(_ templates: [SplitTemplate]) -> [SplitTemplate?] { templates.map { $0 } + [nil] }

    /// The key that picks the entry in the picker: empty for a template without a key. The chain is `c`.
    public static func key(_ template: SplitTemplate?) -> String {
        guard let template else { return "c" }
        return template.key ?? ""
    }

    public static func label(_ template: SplitTemplate?) -> String { template?.name ?? "chain" }

    /// Draws the picture in `rect` of a flipped (top-left origin) view.
    static func draw(_ template: SplitTemplate?, in rect: CGRect, color: NSColor) {
        var cells: [CGRect]
        if let template {
            // The cells sit inside the area of the template (the middle two thirds, for `center`).
            cells = template.cells.map {
                CGRect(
                    x: template.area.minX + $0.minX * template.area.width, y: template.area.minY + $0.minY * template.area.height,
                    width: $0.width * template.area.width, height: $0.height * template.area.height)
            }
        } else {
            // The chain: a row of tall columns, the way the strip looks.
            cells = (0..<4).map { CGRect(x: Double($0) / 4, y: 0, width: 0.25, height: 1) }
        }
        let inset: CGFloat = max(1.5, rect.width * 0.03)
        for cell in cells {
            let frame = CGRect(
                x: rect.minX + cell.minX * rect.width, y: rect.minY + cell.minY * rect.height,
                width: cell.width * rect.width, height: cell.height * rect.height
            ).insetBy(dx: inset, dy: inset)
            color.setFill()
            NSBezierPath(roundedRect: frame, xRadius: frame.width * 0.18, yRadius: frame.width * 0.18).fill()
        }
    }

    /// A template image for a menu item.
    public static func image(for template: SplitTemplate?, size: CGSize = CGSize(width: 22, height: 16)) -> NSImage {
        let image = NSImage(size: size, flipped: true) { rect in
            draw(template, in: rect, color: .black)
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// A small picker with the pictures of the templates of a layout and the chain. Keys come from the event tap, so the panel never becomes key or active:
/// the arrow keys move, the key printed on a picture (a number or a letter; `c` is the chain) or Return chooses, Escape cancels. A click on a picture chooses it.
@MainActor
public final class TemplatePicker {
    private static let columns = 6
    private static let tile = CGSize(width: 104, height: 88)
    private static let gap: CGFloat = 10
    private static let padding: CGFloat = 16

    private let panel = PickerPanel()
    private let view = PickerView()
    private var selected = 0
    private var entries: [SplitTemplate?] = []

    /// Called with the chosen template (`nil` is the chain) after the picker closes.
    public var onChoose: ((SplitTemplate?) -> Void)?

    public var isOpen: Bool { panel.isVisible }

    public init() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        panel.contentView = view
        view.onClick = { [unowned self] index in
            selected = index
            commit()
        }
    }

    /// `workArea` is the focused monitor's usable area in Accessibility coordinates. `templates` are the pictures
    /// (the chain comes last). `current` starts the selection.
    public func show(on workArea: CGRect, templates: [SplitTemplate], current: SplitTemplate?) {
        entries = TemplateGlyph.entries(templates)
        selected = entries.firstIndex { $0 == current } ?? 0
        let rows = (entries.count + Self.columns - 1) / Self.columns
        let size = CGSize(
            width: 2 * Self.padding + CGFloat(Self.columns) * Self.tile.width + CGFloat(Self.columns - 1) * Self.gap,
            height: 2 * Self.padding + CGFloat(rows) * Self.tile.height + CGFloat(rows - 1) * Self.gap
        )
        let rect = CGRect(
            x: workArea.midX - size.width / 2, y: workArea.midY - size.height / 2, width: size.width, height: size.height)
        view.configure(entries: entries, columns: Self.columns, tile: Self.tile, gap: Self.gap, padding: Self.padding)
        view.selected = selected
        panel.setFrame(Displays.cocoaRect(rect), display: true)
        panel.orderFrontRegardless()
    }

    public func hide() { panel.orderOut(nil) }

    /// Returns `true` when the key is used up. Any other key closes the picker and is typed as usual.
    public func handleKey(_ key: String) -> Bool {
        guard isOpen else { return false }
        let count = entries.count
        switch key {
        case "left": move(by: -1)
        case "right": move(by: 1)
        case "up": move(by: -Self.columns)
        case "down": move(by: Self.columns)
        case "tab": selected = (selected + 1) % count; view.selected = selected
        case "enter", "space": commit()
        case "esc": hide()
        case "backslash": choose(count - 1)
        default:
            if let index = entries.firstIndex(where: { TemplateGlyph.key($0) == key && !key.isEmpty }) {
                choose(index)
            } else {
                hide()
                return false
            }
        }
        return true
    }

    private func move(by delta: Int) {
        let count = entries.count
        let next = selected + delta
        guard next >= 0, next < count else { return }
        selected = next
        view.selected = selected
    }

    private func choose(_ index: Int) {
        selected = index
        commit()
    }

    private func commit() {
        let template = entries[selected]
        hide()
        onChoose?(template)
    }
}

private final class PickerPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class PickerView: NSView {
    var selected = 0 { didSet { needsDisplay = true } }
    var onClick: ((Int) -> Void)?
    private var entries: [SplitTemplate?] = []
    private var columns = 5
    private var tile = CGSize.zero
    private var gap: CGFloat = 0
    private var padding: CGFloat = 0

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func configure(entries: [SplitTemplate?], columns: Int, tile: CGSize, gap: CGFloat, padding: CGFloat) {
        self.entries = entries
        self.columns = columns
        self.tile = tile
        self.gap = gap
        self.padding = padding
        needsDisplay = true
    }

    private func frame(of index: Int) -> CGRect {
        CGRect(
            x: padding + CGFloat(index % columns) * (tile.width + gap),
            y: padding + CGFloat(index / columns) * (tile.height + gap),
            width: tile.width, height: tile.height)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = entries.indices.first(where: { frame(of: $0).contains(point) }) { onClick?(index) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18)
        NSColor(white: 0.08, alpha: 0.92).setFill()
        background.fill()
        for (index, template) in entries.enumerated() {
            let cell = frame(of: index)
            let isSelected = index == selected
            let card = NSBezierPath(roundedRect: cell, xRadius: 12, yRadius: 12)
            NSColor(white: 1, alpha: isSelected ? 0.14 : 0.06).setFill()
            card.fill()
            if isSelected {
                NSColor(srgbRed: 0.537, green: 0.706, blue: 0.980, alpha: 1).setStroke()
                card.lineWidth = 2
                card.stroke()
            }
            let glyph = CGRect(x: cell.minX + 14, y: cell.minY + 10, width: cell.width - 28, height: cell.height - 38)
            let badge = TemplateGlyph.key(template) as NSString
            let badgeAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor(white: 1, alpha: 0.55),
            ]
            badge.draw(at: CGPoint(x: cell.minX + 8, y: cell.minY + 6), withAttributes: badgeAttributes)
            TemplateGlyph.draw(template, in: glyph, color: NSColor(white: 1, alpha: isSelected ? 0.95 : 0.7))
            let text = TemplateGlyph.label(template) as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.85),
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: cell.midX - size.width / 2, y: cell.maxY - size.height - 8), withAttributes: attributes)
        }
    }
}
