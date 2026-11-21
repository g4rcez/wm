import AppKit
import Core

/// The floating label for a key sequence that waits for its next key and for a binding mode: one rounded pill with a
/// name chip, then a chip for each key that can be pressed next with what it does, like Neovim's which-key and Rex's
/// panel. A plain message (`wm notify`) is a pill with text only. The window never becomes key or main and never
/// activates the app.
@MainActor
public final class PrefixLabel {
    private static let margin: CGFloat = 10

    private let panel = LabelPanel()
    private let pill = PillView()
    /// A blur behind the pill, so the label is readable over any window.
    private let effect = NSVisualEffectView()

    public var isShown: Bool { panel.isVisible }

    public init() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        effect.addSubview(pill)
        panel.contentView = effect
    }

    /// `workArea` is the focused monitor's usable area in Accessibility coordinates (origin top-left, y down).
    /// Calling `show` again only updates the content and the position.
    public func show(_ content: LabelContent, settings: PrefixLabelSettings, style: ResolvedStyle, on workArea: CGRect) {
        let theme = Theme(style)
        theme.configure(effect)
        panel.hasShadow = style.shadow
        // At a side of the screen the keys are a list, one per line; in the middle they are a grid in a row.
        let geometry = PillGeometry.make(
            content, settings: settings, theme: theme, vertical: settings.position.isSide,
            maxWidth: workArea.width * 0.8, maxHeight: workArea.height * 0.7)
        let rect = Self.rect(
            for: geometry.size, position: settings.position,
            offset: CGPoint(x: settings.offsetX, y: settings.offsetY), in: workArea
        )
        pill.geometry = geometry
        pill.frame = CGRect(origin: .zero, size: geometry.size)
        effect.maskImage = Theme.roundedMask(radius: geometry.radius)
        panel.setFrame(Displays.cocoaRect(rect), display: true)
        pill.needsDisplay = true
        panel.orderFrontRegardless()
        panel.invalidateShadow()
    }

    public func hide() {
        panel.orderOut(nil)
    }

    /// The label's rectangle inside `workArea`. Both use Accessibility coordinates (origin top-left, y down).
    /// A positive `offset.x` moves right, a positive `offset.y` moves down.
    static func rect(for size: CGSize, position: LabelPosition, offset: CGPoint, in workArea: CGRect) -> CGRect {
        let x: CGFloat
        switch position {
        case .topLeft, .left, .bottomLeft: x = workArea.minX + margin
        case .topCenter, .center, .bottomCenter: x = workArea.midX - size.width / 2
        case .topRight, .right, .bottomRight: x = workArea.maxX - margin - size.width
        }
        let y: CGFloat
        switch position {
        case .topLeft, .topCenter, .topRight: y = workArea.minY + margin
        case .left, .center, .right: y = workArea.midY - size.height / 2
        case .bottomLeft, .bottomCenter, .bottomRight: y = workArea.maxY - margin - size.height
        }
        return CGRect(x: x + offset.x, y: y + offset.y, width: size.width, height: size.height)
    }
}

/// Where everything of one pill goes, worked out before drawing. Sizes follow the font size of the settings.
private struct PillGeometry {
    enum Item {
        case chip(rect: CGRect, fill: NSColor, text: NSAttributedString, textOrigin: CGPoint)
        case text(NSAttributedString, origin: CGPoint)
    }

    var size: CGSize
    var items: [Item]
    var background: NSColor?
    var border: NSColor
    var radius: CGFloat

    static func make(_ content: LabelContent, settings: PrefixLabelSettings, theme: Theme, vertical: Bool, maxWidth: CGFloat, maxHeight: CGFloat) -> PillGeometry {
        let size = theme.size(11)
        let density = CGFloat(theme.style.scale)
        let foreground = theme.foreground
        let border = theme.border ?? theme.inkColor(0.12)
        // Small type, small chips and a lot of air around them, like Rex's panel.
        let chipHeight = ceil(size * 1.75 * density)
        let rowHeight = chipHeight
        let padX = ceil(size * 1.3 * density), padY = ceil(size * 0.85 * density)
        let blockGap = ceil(size * 1.45 * density), keyGap = ceil(size * 0.55 * density), rowGap = ceil(size * 0.5 * density)

        func font(_ scale: CGFloat, _ weight: NSFont.Weight) -> NSFont {
            if let name = theme.style.font, let custom = NSFont(name: name, size: size * scale) { return custom }
            return NSFont.systemFont(ofSize: size * scale, weight: weight)
        }
        func attributed(_ text: String, scale: CGFloat = 1, weight: NSFont.Weight, color: NSColor) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [.font: font(scale, weight), .foregroundColor: color, .kern: 0.15])
        }
        func centered(_ text: NSAttributedString, in rect: CGRect) -> CGPoint {
            let measured = text.size()
            return CGPoint(x: rect.minX + (rect.width - measured.width) / 2, y: rect.minY + (rect.height - measured.height) / 2)
        }

        // A message: text on a pill, no chips.
        if content.badge == nil, content.entries.isEmpty {
            let text = attributed(content.text ?? "", weight: .medium, color: foreground)
            let measured = text.size()
            let pillSize = CGSize(width: ceil(measured.width) + 2 * padX * 1.3, height: rowHeight + 2 * padY)
            let rect = CGRect(origin: .zero, size: pillSize)
            return PillGeometry(
                size: pillSize, items: [.text(text, origin: centered(text, in: rect))],
                background: theme.tint, border: border, radius: min(theme.cornerRadius, pillSize.height / 2))
        }

        // The name chip is a column of its own on the left, centered in the height of the grid.
        var badge: (text: NSAttributedString, width: CGFloat)?
        if let name = content.badge {
            let text = attributed(name, scale: 0.95, weight: .semibold, color: foreground)
            badge = (text, ceil(text.size().width) + 2 * size * 1.05)
        }
        let keys = content.entries.map { attributed($0.key, scale: 0.92, weight: .medium, color: foreground) }
        // `esc` (the way out) is quieter than the keys that do something.
        let labels = content.entries.map {
            attributed($0.text, weight: .medium, color: foreground.withAlphaComponent($0.key == "esc" ? 0.38 : 0.55))
        }
        let keyWidths = keys.map { max(ceil(chipHeight * 1.25), ceil($0.size().width) + 2 * size * 0.8) }
        let labelWidths = labels.map { ceil($0.size().width) }

        // Horizontal: the name chip is a column on the left, centered in the height of the grid. Vertical: it is the
        // header of the list.
        let badgeSpace = vertical ? 0 : (badge.map { $0.width + blockGap } ?? 0)
        let headerHeight = vertical && badge != nil ? chipHeight + ceil(size * 0.9) : 0
        let ellipsisSpace = ceil(size * 1.6)
        let available = maxWidth - 2 * padX - badgeSpace
        var grid: PillLayout.Grid
        if vertical {
            let capacity = Int((maxHeight - 2 * padY - headerHeight + rowGap) / (rowHeight + rowGap))
            grid = PillLayout.list(count: keys.count, maxRows: capacity)
        } else {
            grid = PillLayout.grid(keyWidths: keyWidths, labelWidths: labelWidths, keyGap: keyGap, columnGap: blockGap, maxWidth: available)
            if grid.truncated {
                // Leave room for the "…" that tells that keys are missing.
                grid = PillLayout.grid(keyWidths: keyWidths, labelWidths: labelWidths, keyGap: keyGap, columnGap: blockGap, maxWidth: available - ellipsisSpace)
            }
        }

        // Every column is as wide as its widest key chip and label, so all rows line up.
        var columnKeyWidth: [CGFloat] = [], columnLabelWidth: [CGFloat] = []
        for column in 0..<grid.columns {
            let members = (0..<grid.visible).filter { grid.position(of: $0).column == column }
            columnKeyWidth.append(members.map { keyWidths[$0] }.max() ?? 0)
            columnLabelWidth.append(members.map { labelWidths[$0] }.max() ?? 0)
        }
        let columnX: [CGFloat] = {
            var x = padX + badgeSpace
            return (0..<grid.columns).map { column in
                defer { x += columnKeyWidth[column] + keyGap + columnLabelWidth[column] + blockGap }
                return x
            }
        }()
        let rows = max(grid.rows, 1)
        let gridHeight = CGFloat(rows) * rowHeight + CGFloat(rows - 1) * rowGap
        let gridTop = padY + headerHeight
        var items: [Item] = []
        if let badge {
            let y = vertical ? padY : padY + (gridHeight - chipHeight) / 2
            let rect = CGRect(x: padX, y: y, width: badge.width, height: chipHeight)
            items.append(.chip(rect: rect, fill: theme.accent.withAlphaComponent(0.4), text: badge.text, textOrigin: centered(badge.text, in: rect)))
        }
        for index in 0..<grid.visible {
            let (row, column) = grid.position(of: index)
            let top = gridTop + CGFloat(row) * (rowHeight + rowGap)
            let keyRect = CGRect(x: columnX[column], y: top, width: columnKeyWidth[column], height: chipHeight)
            let labelRect = CGRect(x: columnX[column] + columnKeyWidth[column] + keyGap, y: top, width: labelWidths[index], height: rowHeight)
            items.append(.chip(rect: keyRect, fill: theme.inkColor(0.09), text: keys[index], textOrigin: centered(keys[index], in: keyRect)))
            items.append(.text(labels[index], origin: CGPoint(x: labelRect.minX, y: centered(labels[index], in: labelRect).y)))
        }

        var right = padX + badgeSpace
        if grid.columns > 0 {
            right = (columnX.last ?? right) + columnKeyWidth[grid.columns - 1] + keyGap + columnLabelWidth[grid.columns - 1]
        }
        if let badge { right = max(right, padX + badge.width) }
        if grid.truncated {
            let more = attributed("…", weight: .medium, color: foreground.withAlphaComponent(0.55))
            let rect = CGRect(x: right + blockGap, y: gridTop, width: more.size().width, height: rowHeight)
            items.append(.text(more, origin: centered(more, in: rect)))
            right = rect.maxX
        }
        let pillSize = CGSize(width: right + padX, height: gridTop + gridHeight + padY)
        // A list at a side is a rounded panel; a row in the middle is a capsule.
        // The corner is the one of every overlay, and a capsule when that is bigger than the pill.
        let corner = min(theme.cornerRadius, pillSize.height / 2)
        return PillGeometry(size: pillSize, items: items, background: theme.tint, border: border, radius: corner)
    }
}

/// Draws a `PillGeometry`: a dark capsule with a thin light border, then its chips and texts.
private final class PillView: NSView {
    var geometry: PillGeometry?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let geometry else { return }
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: geometry.radius, yRadius: geometry.radius)
        if let background = geometry.background {
            background.setFill()
            outline.fill()
        }
        geometry.border.setStroke()
        outline.lineWidth = 1
        outline.stroke()
        for item in geometry.items {
            switch item {
            case let .chip(rect, fill, text, origin):
                fill.setFill()
                NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
                text.draw(at: origin)
            case let .text(text, origin):
                text.draw(at: origin)
            }
        }
    }
}

private final class LabelPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
