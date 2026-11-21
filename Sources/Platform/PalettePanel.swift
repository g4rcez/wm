import AppKit
import Core

/// The window of the command palette: a text field above a list, with a footer for the action of the selected row. It can
/// take the keyboard without making wm the active app, so the app that you came from stays frontmost (the menu items of
/// the `/` list belong to it).
@MainActor
public final class PalettePanel: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    public struct Row {
        public var title: String
        /// Dimmer text after the title.
        public var subtitle: String
        /// Text at the right edge, for example `Application`.
        public var accessory: String
        public var icon: NSImage?
        /// A window under its app: the row moves to the right.
        public var indent: Bool
        /// What Return does on this row, for the footer, for example `Focus Window`.
        public var action: String
        /// The key of that action in the footer.
        public var key: String

        public init(title: String, subtitle: String = "", accessory: String = "", icon: NSImage? = nil, indent: Bool = false, action: String = "", key: String = "↵") {
            self.title = title
            self.subtitle = subtitle
            self.accessory = accessory
            self.icon = icon
            self.indent = indent
            self.action = action
            self.key = key
        }
    }

    /// The list takes the clicks of its rows; the panel is dragged by the rest of its background.
    private final class ListTable: NSTableView {
        override var mouseDownCanMoveWindow: Bool { false }
    }

    private final class ListScroll: NSScrollView {
        override var mouseDownCanMoveWindow: Bool { false }
    }

    private final class KeyPanel: NSPanel {
        var onReset: (() -> Void)?

        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }

        /// Cmd-0 puts the panel back at its first place. No bind runs while the panel is open, so the panel takes this key.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "0" {
                onReset?()
                return true
            }
            return super.performKeyEquivalent(with: event)
        }
    }

    /// The highlight of the selected row: a rounded, translucent rectangle, not the blue of the system.
    private final class RowView: NSTableRowView {
        var theme = Theme.placeholder

        override func drawSelection(in dirtyRect: NSRect) {
            guard isSelected else { return }
            let radius = min(10, max(4, theme.cornerRadius / 2))
            theme.selection.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: radius > 6 ? 7 : 6, dy: 0), xRadius: radius, yRadius: radius).fill()
        }
    }

    /// The texts of a row, so that the selection can recolor them.
    private final class RowCell: NSView {
        var texts: [(field: NSTextField, normal: NSColor)] = []

        func setSelected(_ selected: Bool, theme: Theme) {
            for (field, normal) in texts { field.textColor = theme.text(normal, selected: selected) }
        }
    }

    /// A key name in a small outlined box, like `↵`.
    private final class KeyCap: NSView {
        private let label: NSTextField

        init(_ text: String, theme: Theme) {
            label = NSTextField(labelWithString: text)
            label.font = theme.font(12, .medium)
            label.textColor = theme.secondary
            label.sizeToFit()
            let width = max(22, label.frame.width + 12)
            super.init(frame: NSRect(x: 0, y: 0, width: width, height: 22))
            wantsLayer = true
            layer?.cornerRadius = min(6, max(3, theme.cornerRadius / 3))
            layer?.borderWidth = 1
            layer?.borderColor = theme.cg(theme.separator)
            label.frame = NSRect(x: (width - label.frame.width) / 2, y: (22 - label.frame.height) / 2, width: label.frame.width, height: label.frame.height)
            addSubview(label)
        }

        required init?(coder: NSCoder) { fatalError("not from a nib") }
    }

    private static let plainWidth: CGFloat = 750
    /// With the preview the panel is wider: a list at the left and the picture of the window at the right.
    private static let previewWidth: CGFloat = 900
    private static let previewListWidth: CGFloat = 400
    private static let headerHeight: CGFloat = 60
    private static let sectionHeight: CGFloat = 30
    /// With a list the panel has one height, however many rows there are, so it does not jump while you type.
    private static let listHeight: CGFloat = 385
    /// The action of the selected row floats over the bottom right corner of the list, in a capsule.
    private static let actionHeight: CGFloat = 36
    private static let actionMargin: CGFloat = 8
    private static let hintsWidth: CGFloat = 200

    /// The text changed.
    public var onChange: ((String) -> Void)?
    /// Return was pressed. The row is `nil` when the list is empty.
    public var onActivate: ((Int?) -> Void)?
    /// Tab was pressed on a row, and `cyclesWithTab` is off.
    public var onTab: ((Int) -> Void)?
    /// The selected row changed (arrow keys, Tab, or a new list).
    public var onSelect: ((Int) -> Void)?
    /// Tab goes to the next row and Shift-Tab to the previous one. Off: Tab goes to `onTab`.
    public var cyclesWithTab = true
    /// The panel has room for the picture of the selected window. Set it before `show`.
    public var previewsEnabled = false
    public var onCancel: (() -> Void)?

    private var panel: KeyPanel?
    private let field = NSTextField()
    private let table = ListTable()
    private let scroll = ListScroll()
    private let section = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let hints = NSView()
    private let footer = NSVisualEffectView()
    private let divider = NSBox()
    private let previewArea = NSView()
    private let previewPicture = NSImageView()
    private let previewIcon = NSImageView()
    private var rows: [Row] = []
    private var showsPreview = false
    /// True while the panel puts itself in place, so `windowDidMove` knows that the user did not move it.
    private var placing = false
    private var listWidth = PalettePanel.plainWidth

    /// The look of the palette, asked at each show so that a reloaded config applies.
    public var style: @MainActor () -> ResolvedStyle = { AppearanceSettings().resolved() }
    private var theme = Theme.placeholder
    private let tintView = NSView()

    private var rowHeight: CGFloat { CGFloat(theme.style.paletteRowHeight) }
    private var plainWidth: CGFloat { CGFloat(theme.style.paletteWidth) }
    private var panelWidth: CGFloat { previewsEnabled ? plainWidth + (Self.previewWidth - Self.plainWidth) : plainWidth }

    public override init() { super.init() }

    public var isOpen: Bool { panel?.isVisible == true }

    public func show(text: String, placeholder: String) {
        theme = Theme(style())
        let panel = self.panel ?? makePanel()
        self.panel = panel
        applyTheme(to: panel)
        field.stringValue = text
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [.font: theme.font(20), .foregroundColor: theme.tertiary])
        setRows([], section: "", preview: false)
        // Where the user left it, as a fraction of the screen that has the mouse.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? .zero
        let top = paletteTopCenter(Self.savedPosition, in: area, width: panelWidth)
        placing = true
        panel.setFrame(NSRect(x: top.x - panelWidth / 2, y: top.y - Self.headerHeight, width: panelWidth, height: Self.headerHeight), display: true)
        placing = false
        layout(rowCount: 0)
        panel.onReset = { [unowned self] in resetPosition() }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        if let editor = field.currentEditor() { editor.selectedRange = NSRange(location: editor.string.count, length: 0) }
    }

    public func hide() {
        panel?.orderOut(nil)
    }

    /// Forgets where the user left the panel. An open panel goes back to its first place on its screen at once.
    public func resetPosition() {
        Self.savedPosition = nil
        guard let panel, panel.isVisible else { return }
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let area = (NSScreen.screens.first { $0.frame.contains(center) } ?? panel.screen)?.visibleFrame ?? .zero
        let top = paletteTopCenter(nil, in: area, width: panel.frame.width)
        placing = true
        panel.setFrameOrigin(NSPoint(x: top.x - panel.frame.width / 2, y: top.y - panel.frame.height))
        placing = false
    }

    public func setText(_ text: String) {
        field.stringValue = text
        if let editor = field.currentEditor() { editor.selectedRange = NSRange(location: text.count, length: 0) }
    }

    /// `preview`: the list has windows, so the right side shows the picture of the selected one (when `previewsEnabled`).
    public func setRows(_ rows: [Row], section title: String, preview: Bool) {
        self.rows = rows
        showsPreview = preview && previewsEnabled && !rows.isEmpty
        section.stringValue = title
        layout(rowCount: rows.count)
        table.reloadData()
        if !rows.isEmpty { select(0) }
        updateFooter()
    }

    /// The picture of the selected window. Without one, `placeholder` (the icon of the app) shows in the middle.
    public func setPreview(_ image: CGImage?, placeholder: NSImage?) {
        previewPicture.image = image.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        previewIcon.image = placeholder
        layoutPreview()
    }

    // MARK: - Building

    /// What a style can change in a panel that already exists: the blur, the corners, the colors and the type.
    private func applyTheme(to panel: KeyPanel) {
        guard let background = panel.contentView as? NSVisualEffectView else { return }
        theme.configure(background)
        panel.hasShadow = theme.style.shadow
        background.layer?.cornerRadius = theme.cornerRadius
        background.layer?.borderWidth = CGFloat(theme.style.borderWidth)
        background.layer?.borderColor = theme.cg(theme.separator)
        tintView.layer?.backgroundColor = theme.tint?.cgColor
        tintView.isHidden = theme.tint == nil
        icon.contentTintColor = theme.secondary
        field.font = theme.font(20)
        field.textColor = theme.foreground
        section.font = theme.font(12, .semibold)
        section.textColor = theme.secondary
        table.rowHeight = rowHeight
        footer.layer?.borderColor = theme.cg(theme.separator)
        previewPicture.layer?.borderColor = theme.cg(theme.separator)
        previewPicture.layer?.cornerRadius = min(8, max(3, theme.cornerRadius / 3))
        rebuildHints()
    }

    /// The `>` and `/` keys in the header.
    private func rebuildHints() {
        hints.subviews.forEach { $0.removeFromSuperview() }
        var x: CGFloat = 0
        for (key, name) in [(">", "Commands"), ("/", "Menu")] {
            let cap = KeyCap(key, theme: theme)
            cap.frame.origin = NSPoint(x: x, y: 0)
            let label = NSTextField(labelWithString: name)
            label.font = theme.font(13)
            label.textColor = theme.tertiary
            label.sizeToFit()
            label.frame.origin = NSPoint(x: cap.frame.maxX + 6, y: (22 - label.frame.height) / 2)
            hints.addSubview(cap)
            hints.addSubview(label)
            x = label.frame.maxX + 14
        }
        hints.frame.size = NSSize(width: x - 14, height: 22)
    }

    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.delegate = self

        let background = NSVisualEffectView()
        background.wantsLayer = true
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        panel.contentView = background
        // A tint over the blur, under everything else.
        tintView.wantsLayer = true
        tintView.autoresizingMask = [.width, .height]
        background.addSubview(tintView)

        icon.image = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 18, weight: .regular)
        background.addSubview(icon)

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        background.addSubview(field)

        background.addSubview(hints)

        background.addSubview(section)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        // The default style adds its own padding at both sides; the rows draw their own insets.
        table.style = .plain
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.allowsEmptySelection = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        // The last rows can scroll up, out from under the capsule of the action.
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: Self.actionHeight + 2 * Self.actionMargin, right: 0)
        background.addSubview(scroll)

        divider.boxType = .separator
        background.addSubview(divider)
        previewPicture.wantsLayer = true
        previewPicture.imageScaling = .scaleProportionallyUpOrDown
        previewPicture.layer?.masksToBounds = true
        previewPicture.layer?.borderWidth = 1
        previewIcon.imageScaling = .scaleProportionallyUpOrDown
        previewArea.addSubview(previewPicture)
        previewArea.addSubview(previewIcon)
        background.addSubview(previewArea)

        footer.material = .menu
        footer.blendingMode = .withinWindow
        footer.state = .active
        footer.wantsLayer = true
        footer.layer?.cornerRadius = Self.actionHeight / 2
        footer.layer?.masksToBounds = true
        footer.layer?.borderWidth = 1
        background.addSubview(footer)
        return panel
    }

    /// Without rows the panel is the header alone. From the bottom: list (the action floats over its corner), section label,
    /// header.
    private func layout(rowCount: Int) {
        guard let panel, let content = panel.contentView else { return }
        let hasList = rowCount > 0
        let height = Self.headerHeight + (hasList ? Self.sectionHeight + Self.listHeight : 0)
        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        placing = true
        panel.setFrame(frame, display: true)
        placing = false
        let bounds = content.bounds
        tintView.frame = bounds
        listWidth = showsPreview ? Self.previewListWidth : bounds.width
        let top = bounds.height - Self.headerHeight
        icon.frame = NSRect(x: 15, y: top + (Self.headerHeight - 22) / 2, width: 22, height: 22)
        hints.frame.origin = NSPoint(x: bounds.width - 16 - hints.frame.width, y: top + (Self.headerHeight - 22) / 2)
        // An editable field draws its text from the top of the frame, so the frame is one line high, and then it is centered.
        let font = field.font ?? .systemFont(ofSize: 20)
        let line = ceil(font.ascender - font.descender + font.leading)
        field.frame = NSRect(x: 49, y: top + ((Self.headerHeight - line) / 2).rounded(), width: hints.frame.minX - 49 - 12, height: line)
        section.frame = NSRect(x: 15, y: top - Self.sectionHeight + 8, width: listWidth - 30, height: 16)
        section.isHidden = !hasList
        scroll.frame = NSRect(x: 0, y: 0, width: listWidth, height: Self.listHeight)
        scroll.isHidden = !hasList
        if !hasList { footer.isHidden = true }
        // The picture stays above the capsule of the action.
        let clear = Self.actionHeight + 2 * Self.actionMargin
        divider.frame = NSRect(x: listWidth, y: 0, width: 1, height: top)
        previewArea.frame = NSRect(x: listWidth + 1, y: clear, width: bounds.width - listWidth - 1, height: top - clear)
        divider.isHidden = !showsPreview
        previewArea.isHidden = !showsPreview
        layoutPreview()
    }

    /// The picture fits the area with a margin and keeps its shape.
    private func layoutPreview() {
        let area = previewArea.bounds.insetBy(dx: 20, dy: 20)
        guard area.width > 0, area.height > 0 else { return }
        if let image = previewPicture.image, image.size.width > 0, image.size.height > 0 {
            let scale = min(area.width / image.size.width, area.height / image.size.height)
            let size = NSSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
            previewPicture.frame = NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height).integral
            previewPicture.isHidden = false
            previewIcon.isHidden = true
        } else {
            previewPicture.isHidden = true
            previewIcon.frame = NSRect(x: area.midX - 36, y: area.midY - 36, width: 72, height: 72)
            previewIcon.isHidden = previewIcon.image == nil
        }
    }

    /// The capsule at the bottom right: the action of the selected row and its key.
    private func updateFooter() {
        footer.subviews.forEach { $0.removeFromSuperview() }
        guard rows.indices.contains(table.selectedRow), !rows[table.selectedRow].action.isEmpty else {
            footer.isHidden = true
            return
        }
        let row = rows[table.selectedRow]
        let label = NSTextField(labelWithString: row.action)
        label.font = theme.font(13, .medium)
        label.textColor = theme.foreground
        label.sizeToFit()
        label.frame.origin = NSPoint(x: 14, y: (Self.actionHeight - label.frame.height) / 2)
        let key = KeyCap(row.key, theme: theme)
        key.frame.origin = NSPoint(x: label.frame.maxX + 8, y: (Self.actionHeight - 22) / 2)
        footer.addSubview(label)
        footer.addSubview(key)
        let width = key.frame.maxX + 8
        footer.frame = NSRect(x: panelWidth - Self.actionMargin - width, y: Self.actionMargin, width: width, height: Self.actionHeight)
        footer.isHidden = false
    }

    /// The selected row, `nil` when the list is empty.
    public var selectedRow: Int? { table.selectedRow >= 0 ? table.selectedRow : nil }

    public func select(row: Int) { select(row) }

    private func select(_ row: Int) {
        guard rows.indices.contains(row) else { return }
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
        onSelect?(row)
    }

    /// Moves the selection by `delta` rows, around at the ends.
    public func move(_ delta: Int) {
        guard !rows.isEmpty else { return }
        let current = table.selectedRow < 0 ? 0 : table.selectedRow
        select(((current + delta) % rows.count + rows.count) % rows.count)
    }

    @objc private func clicked() {
        if table.clickedRow >= 0 { onActivate?(table.clickedRow) }
    }

    // MARK: - Delegates

    public func controlTextDidChange(_ notification: Notification) {
        onChange?(field.stringValue)
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): move(-1)
        case #selector(NSResponder.moveDown(_:)): move(1)
        case #selector(NSResponder.insertNewline(_:)): onActivate?(table.selectedRow >= 0 ? table.selectedRow : nil)
        case #selector(NSResponder.insertTab(_:)):
            if cyclesWithTab { move(1) } else if table.selectedRow >= 0 { onTab?(table.selectedRow) }
        case #selector(NSResponder.insertBacktab(_:)): move(-1)
        case #selector(NSResponder.cancelOperation(_:)): onCancel?()
        default: return false
        }
        return true
    }

    /// The user dragged the panel: the new spot is kept, as a fraction of the screen that holds the panel.
    public func windowDidMove(_ notification: Notification) {
        guard !placing, let panel, panel.isVisible else { return }
        let frame = panel.frame
        let center = NSPoint(x: frame.midX, y: frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? panel.screen else { return }
        Self.savedPosition = palettePosition(topCenter: NSPoint(x: frame.midX, y: frame.maxY), in: screen.visibleFrame)
    }

    private static let positionKey = "wm.palettePosition"

    private static var savedPosition: PalettePosition? {
        get { UserDefaults.standard.data(forKey: positionKey).flatMap { try? JSONDecoder().decode(PalettePosition.self, from: $0) } }
        set { UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: positionKey) }
    }

    public func windowDidResignKey(_ notification: Notification) {
        if isOpen { onCancel?() }
    }

    public func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        updateFooter()
        for row in 0..<rows.count {
            (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? RowCell)?.setSelected(row == table.selectedRow, theme: theme)
        }
    }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = RowView()
        view.theme = theme
        return view
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let data = rows[row]
        let cell = RowCell(frame: NSRect(x: 0, y: 0, width: listWidth, height: rowHeight))
        let left: CGFloat = data.indent ? 37 : 15
        // The list is narrow beside the preview: the type of the row is its icon and indent.
        let accessory = NSTextField(labelWithString: showsPreview ? "" : data.accessory)
        accessory.font = theme.font(14)
        accessory.textColor = theme.secondary
        accessory.sizeToFit()
        accessory.frame.origin = NSPoint(x: listWidth - 16 - accessory.frame.width, y: (rowHeight - accessory.frame.height) / 2)
        let picture = NSImageView(frame: NSRect(x: left, y: (rowHeight - 22) / 2, width: 22, height: 22))
        picture.image = data.icon
        picture.imageScaling = .scaleProportionallyUpOrDown
        let textX = left + 22 + 12
        let room = accessory.frame.minX - 12 - textX
        let title = NSTextField(labelWithString: data.title)
        title.font = theme.font(14, .medium)
        title.textColor = theme.foreground
        title.lineBreakMode = .byTruncatingTail
        title.sizeToFit()
        title.frame = NSRect(x: textX, y: (rowHeight - title.frame.height) / 2, width: min(title.frame.width, room), height: title.frame.height)
        cell.addSubview(picture)
        cell.addSubview(title)
        if !data.subtitle.isEmpty, room - title.frame.width > 40 {
            let subtitle = NSTextField(labelWithString: data.subtitle)
            subtitle.font = theme.font(14)
            subtitle.textColor = theme.secondary
            subtitle.lineBreakMode = .byTruncatingMiddle
            subtitle.sizeToFit()
            let x = title.frame.maxX + 12
            subtitle.frame = NSRect(x: x, y: (rowHeight - subtitle.frame.height) / 2, width: min(subtitle.frame.width, accessory.frame.minX - 12 - x), height: subtitle.frame.height)
            cell.addSubview(subtitle)
            cell.texts.append((subtitle, theme.secondary))
        }
        cell.addSubview(accessory)
        cell.texts += [(title, theme.foreground), (accessory, theme.secondary)]
        cell.setSelected(row == table.selectedRow, theme: theme)
        return cell
    }
}
