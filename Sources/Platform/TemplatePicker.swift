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
        let inset: CGFloat = max(1.2, rect.width * 0.022)
        // The first cell is the one that the focused window takes: it is drawn bright, the others are dim.
        for (index, cell) in cells.enumerated() {
            let frame = CGRect(
                x: rect.minX + cell.minX * rect.width, y: rect.minY + cell.minY * rect.height,
                width: cell.width * rect.width, height: cell.height * rect.height
            ).insetBy(dx: inset, dy: inset)
            (index == 0 || cells.count == 1 ? color : color.withAlphaComponent(color.alphaComponent * 0.4)).setFill()
            let radius = min(5, min(frame.width, frame.height) * 0.2)
            NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
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

/// A small picker with the pictures of the templates of a layout and the chain. In the tiling layout it has one more picture,
/// `g`: a grid where you drag a rectangle with the mouse. The rectangle becomes a frame template (the windows share that part
/// of the screen). Keys come from the event tap, so the panel never becomes key or active:
/// the arrow keys move, the key printed on a picture (a number or a letter; `c` is the chain) or Return chooses, Escape cancels. A click on a picture chooses it.
@MainActor
public final class TemplatePicker {
    private static let columns = 6
    private static let tile = CGSize(width: 116, height: 104)
    private static let gap: CGFloat = 10
    private static let padding: CGFloat = 18

    private let panel = PickerPanel()
    private let view = PickerView()
    private let blur = NSVisualEffectView()
    /// The look of the picker, asked at each show so that a reloaded config applies.
    public var style: @MainActor () -> ResolvedStyle = { AppearanceSettings().resolved() }
    private var selected = 0
    private var entries: [SplitTemplate?] = []
    private var allowsGrid = false
    private var isGridMode = false {
        didSet { view.isGridMode = isGridMode }
    }
    /// The pictures, and the grid tile after them when the layout has it.
    private var itemCount: Int { entries.count + (allowsGrid ? 1 : 0) }

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
        // A blur behind the pictures: the windows under the panel stay out of the way of the text.
        blur.wantsLayer = true
        blur.layer?.masksToBounds = true
        view.autoresizingMask = [.width, .height]
        blur.addSubview(view)
        panel.contentView = blur
        view.onClick = { [unowned self] index in
            selected = index
            commit()
        }
        view.onGrid = { [unowned self] column, row, columns, rows in
            guard let frame = CustomTemplates.gridFrame(
                columns: PickerView.gridColumns, rows: PickerView.gridRows, column: column, row: row, spanColumns: columns, spanRows: rows)
            else { return }
            hide()
            onChoose?(frame)
        }
    }

    /// `workArea` is the focused monitor's usable area in Accessibility coordinates. `templates` are the pictures
    /// (the chain comes last). `current` starts the selection.
    public func show(on workArea: CGRect, templates: [SplitTemplate], current: SplitTemplate?, allowsGrid: Bool = false) {
        let theme = Theme(style())
        theme.configure(blur)
        blur.layer?.cornerRadius = theme.cornerRadius
        panel.hasShadow = theme.style.shadow
        view.theme = theme
        let k = CGFloat(theme.style.scale)
        let tile = CGSize(width: Self.tile.width * k, height: Self.tile.height * k)
        let gap = Self.gap * k, padding = Self.padding * k
        entries = TemplateGlyph.entries(templates)
        self.allowsGrid = allowsGrid
        isGridMode = false
        selected = entries.firstIndex { $0 == current } ?? 0
        let rows = (itemCount + Self.columns - 1) / Self.columns
        let size = CGSize(
            width: 2 * padding + CGFloat(Self.columns) * tile.width + CGFloat(Self.columns - 1) * gap,
            height: 2 * padding + CGFloat(rows) * tile.height + CGFloat(rows - 1) * gap
        )
        let rect = CGRect(
            x: workArea.midX - size.width / 2, y: workArea.midY - size.height / 2, width: size.width, height: size.height)
        view.configure(entries: entries, showsGridTile: allowsGrid, columns: Self.columns, tile: tile, gap: gap, padding: padding)
        view.selected = selected
        panel.setFrame(Displays.cocoaRect(rect), display: true)
        view.frame = CGRect(origin: .zero, size: size)
        panel.orderFrontRegardless()
    }

    public func hide() {
        isGridMode = false
        panel.orderOut(nil)
    }

    /// Returns `true` when the key is used up. Any other key closes the picker and is typed as usual.
    public func handleKey(_ key: String) -> Bool {
        guard isOpen else { return false }
        // In the grid only the mouse draws. Escape goes back to the pictures.
        if isGridMode {
            if key == "esc" { isGridMode = false }
            return true
        }
        let count = itemCount
        switch key {
        case "left": move(by: -1)
        case "right": move(by: 1)
        case "up": move(by: -Self.columns)
        case "down": move(by: Self.columns)
        case "tab": selected = (selected + 1) % count; view.selected = selected
        case "enter", "space": commit()
        case "esc": hide()
        case "backslash": choose(entries.count - 1)
        default:
            if allowsGrid, key == "g" {
                isGridMode = true
            } else if let index = entries.firstIndex(where: { TemplateGlyph.key($0) == key && !key.isEmpty }) {
                choose(index)
            } else {
                hide()
                return false
            }
        }
        return true
    }

    private func move(by delta: Int) {
        let count = itemCount
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
        if allowsGrid, selected == entries.count {
            isGridMode = true
            return
        }
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
    static let gridColumns = 8
    static let gridRows = 6
    private static let titleHeight: CGFloat = 30

    var selected = 0 { didSet { needsDisplay = true } }
    var theme = Theme.placeholder
    var isGridMode = false { didSet { dragStart = nil; dragEnd = nil; needsDisplay = true } }
    var onClick: ((Int) -> Void)?
    /// The cell of the top left corner and the size in cells of the rectangle that the user drew.
    var onGrid: ((Int, Int, Int, Int) -> Void)?
    private var dragStart: (column: Int, row: Int)?
    private var dragEnd: (column: Int, row: Int)?
    private var showsGridTile = false
    private var entries: [SplitTemplate?] = []
    private var columns = 5
    private var tile = CGSize.zero
    private var gap: CGFloat = 0
    private var padding: CGFloat = 0

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func configure(entries: [SplitTemplate?], showsGridTile: Bool, columns: Int, tile: CGSize, gap: CGFloat, padding: CGFloat) {
        self.entries = entries
        self.showsGridTile = showsGridTile
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

    private var gridRect: CGRect {
        CGRect(x: padding, y: padding + Self.titleHeight, width: bounds.width - 2 * padding, height: bounds.height - 2 * padding - Self.titleHeight)
    }

    private func gridCell(at point: CGPoint) -> (column: Int, row: Int) {
        let rect = gridRect
        let column = Int((point.x - rect.minX) / rect.width * CGFloat(Self.gridColumns))
        let row = Int((point.y - rect.minY) / rect.height * CGFloat(Self.gridRows))
        return (min(max(column, 0), Self.gridColumns - 1), min(max(row, 0), Self.gridRows - 1))
    }

    /// The rectangle of the drag as the top left cell and the size in cells.
    private var dragSelection: (column: Int, row: Int, columns: Int, rows: Int)? {
        guard let start = dragStart, let end = dragEnd else { return nil }
        return (min(start.column, end.column), min(start.row, end.row), abs(start.column - end.column) + 1, abs(start.row - end.row) + 1)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isGridMode {
            dragStart = gridCell(at: point)
            dragEnd = dragStart
            needsDisplay = true
            return
        }
        let count = entries.count + (showsGridTile ? 1 : 0)
        if let index = (0..<count).first(where: { frame(of: $0).contains(point) }) { onClick?(index) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isGridMode, dragStart != nil else { return }
        dragEnd = gridCell(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isGridMode, let selection = dragSelection else { return }
        dragStart = nil
        dragEnd = nil
        needsDisplay = true
        onGrid?(selection.column, selection.row, selection.columns, selection.rows)
    }

    private func drawGrid() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: theme.inkColor(0.7),
        ]
        ("Drag to draw a frame. Esc goes back." as NSString).draw(at: CGPoint(x: padding, y: padding), withAttributes: attributes)
        let rect = gridRect
        let screen = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        theme.inkColor(0.06).setFill()
        screen.fill()
        let cellWidth = rect.width / CGFloat(Self.gridColumns), cellHeight = rect.height / CGFloat(Self.gridRows)
        theme.inkColor(0.16).setStroke()
        for column in 1..<Self.gridColumns {
            let line = NSBezierPath()
            line.move(to: CGPoint(x: rect.minX + CGFloat(column) * cellWidth, y: rect.minY))
            line.line(to: CGPoint(x: rect.minX + CGFloat(column) * cellWidth, y: rect.maxY))
            line.stroke()
        }
        for row in 1..<Self.gridRows {
            let line = NSBezierPath()
            line.move(to: CGPoint(x: rect.minX, y: rect.minY + CGFloat(row) * cellHeight))
            line.line(to: CGPoint(x: rect.maxX, y: rect.minY + CGFloat(row) * cellHeight))
            line.stroke()
        }
        if let selection = dragSelection {
            let area = CGRect(
                x: rect.minX + CGFloat(selection.column) * cellWidth, y: rect.minY + CGFloat(selection.row) * cellHeight,
                width: CGFloat(selection.columns) * cellWidth, height: CGFloat(selection.rows) * cellHeight)
            let box = NSBezierPath(roundedRect: area.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6)
            theme.accent.withAlphaComponent(0.5).setFill()
            box.fill()
        }
    }

    /// One card: the key as a keycap in the corner, a monitor with the picture in the middle, the name under it. `picture`
    /// draws inside the monitor, a rectangle in the 16:10 shape of a screen.
    private func drawCard(_ cell: CGRect, key: String, label: String, isSelected: Bool, picture: (CGRect) -> Void) {
        let cardRadius = max(6, theme.cornerRadius - 6)
        let card = NSBezierPath(roundedRect: cell, xRadius: cardRadius, yRadius: cardRadius)
        theme.inkColor(isSelected ? 0.16 : 0.07).setFill()
        card.fill()
        if isSelected {
            theme.accent.setStroke()
            card.lineWidth = 2
            card.stroke()
        }
        let width = cell.width - 30
        let monitor = CGRect(x: cell.midX - width / 2, y: cell.minY + 20, width: width, height: (width * 0.625).rounded())
        theme.inkColor(isSelected ? 0.1 : 0.06).setFill()
        NSBezierPath(roundedRect: monitor, xRadius: 6, yRadius: 6).fill()
        picture(monitor.insetBy(dx: 3, dy: 3))
        if !key.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold), .foregroundColor: theme.inkColor(isSelected ? 0.9 : 0.65),
            ]
            let text = key as NSString
            let size = text.size(withAttributes: attributes)
            let cap = CGRect(x: cell.minX + 7, y: cell.minY + 7, width: max(size.height, size.width + 8), height: size.height + 2)
            theme.inkColor(0.1).setFill()
            NSBezierPath(roundedRect: cap, xRadius: 4, yRadius: 4).fill()
            text.draw(at: CGPoint(x: cap.midX - size.width / 2, y: cap.minY + 1), withAttributes: attributes)
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5, weight: isSelected ? .semibold : .regular),
            .foregroundColor: theme.inkColor(isSelected ? 1 : 0.65),
        ]
        let text = label as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: cell.midX - size.width / 2, y: cell.maxY - size.height - 9), withAttributes: attributes)
    }

    private func drawGridTile(_ cell: CGRect, isSelected: Bool) {
        drawCard(cell, key: "g", label: "draw", isSelected: isSelected) { glyph in
            theme.inkColor(isSelected ? 0.9 : 0.6).setStroke()
            for column in 0..<3 {
                for row in 0..<3 {
                    let box = CGRect(x: glyph.minX + CGFloat(column) * glyph.width / 3, y: glyph.minY + CGFloat(row) * glyph.height / 3, width: glyph.width / 3, height: glyph.height / 3)
                    let path = NSBezierPath(rect: box.insetBy(dx: 1, dy: 1))
                    path.lineWidth = 1
                    path.stroke()
                }
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // The blur of the panel is behind: only a tint goes here, so that the text under the panel cannot be read through it.
        if let tint = theme.tint {
            tint.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: theme.cornerRadius, yRadius: theme.cornerRadius).fill()
        }
        if isGridMode {
            drawGrid()
            return
        }
        if showsGridTile { drawGridTile(frame(of: entries.count), isSelected: selected == entries.count) }
        for (index, template) in entries.enumerated() {
            let isSelected = index == selected
            drawCard(frame(of: index), key: TemplateGlyph.key(template), label: TemplateGlyph.label(template), isSelected: isSelected) { glyph in
                TemplateGlyph.draw(template, in: glyph, color: theme.inkColor(isSelected ? 0.95 : 0.75))
            }
        }
    }
}
