import AppKit
import Core

/// The Alt+Tab miniature: a blurred panel that shows a picture of each window. It only draws what it is given.
/// The window never becomes key or main and never activates the app.
@MainActor
public final class SwitcherOverlay {
    public struct Tile {
        public var id: WindowID
        /// In miniature space, already transformed to panel points (origin top-left of the layout).
        public var frame: CGRect
        public var title: String
        public var appName: String
        public var icon: NSImage?
        public var image: CGImage?
        public var isFloating: Bool
        /// The keys that focus this window (the overview of all workspaces).
        public var hint: String?
        /// The workspace of the window. The header shows it for the selected tile.
        public var workspace: String

        public init(
            id: WindowID, frame: CGRect, title: String, appName: String,
            icon: NSImage? = nil, image: CGImage? = nil, isFloating: Bool = false, hint: String? = nil, workspace: String = ""
        ) {
            self.workspace = workspace
            self.id = id
            self.frame = frame
            self.title = title
            self.appName = appName
            self.icon = icon
            self.image = image
            self.isFloating = isFloating
            self.hint = hint
        }
    }

    /// A name above a row of the miniature (the overview of all workspaces has one row per workspace).
    public struct Label {
        public var text: String
        /// The row, in panel points like `Tile.frame`.
        public var frame: CGRect

        public init(text: String, frame: CGRect) {
            self.text = text
            self.frame = frame
        }
    }

    /// Clicking a tile gives its id. Clicking outside the panel gives `nil`.
    public var onClick: ((WindowID?) -> Void)?
    /// A tile was dragged and dropped on the row at this index of the labels (the overview of all workspaces).
    public var onDrop: ((WindowID, Int) -> Void)?
    public var isShown: Bool { panel.isVisible }

    private static let basePadding: CGFloat = 20
    private static let baseTitleHeight: CGFloat = 52
    /// What the panel adds around the miniature, so the caller can leave room: padding at both sides, and the header.
    public static func chromeSize(scale: Double) -> CGSize {
        let k = CGFloat(scale)
        return CGSize(width: 2 * basePadding * k, height: 2 * basePadding * k + baseTitleHeight * k)
    }

    private let panel = SwitcherPanel()
    private let clickView = ClickView()
    private let effect = NSVisualEffectView()
    private let host = NSView()
    private let tint = CALayer()
    private let titleLayer = CATextLayer()
    /// The workspace of the selected window: a rounded chip at the left of the header.
    private let workspaceChip = CALayer()
    private let workspaceText = CATextLayer()
    private var headerWidth: CGFloat = 0
    private var tileLayers: [WindowID: TileLayer] = [:]
    private var labelLayers: [CATextLayer] = []
    private let dropHighlight = CAShapeLayer()
    private var selectedColor = CGColor(gray: 1, alpha: 1)
    private var theme = Theme.placeholder
    private var padding = SwitcherOverlay.basePadding
    private var titleHeight = SwitcherOverlay.baseTitleHeight
    /// Where the panel starts in the view that covers the monitor: tile and row rectangles are given in the panel.
    private var panelOrigin: CGPoint = .zero
    private var rowFrames: [CGRect] = []
    /// Where a tile was before it was dragged, so a drop that changes nothing puts it back.
    private var dragHome: [WindowID: CGPoint] = [:]

    public init() {
        panel.contentView = clickView
        clickView.onClick = { [weak self] id in self?.onClick?(id) }
        clickView.onDragMove = { [weak self] id, point in self?.dragMoved(id, to: point) }
        clickView.onDragEnd = { [weak self] id, point in self?.dragEnded(id, at: point) }
        dropHighlight.lineWidth = 2
        dropHighlight.isHidden = true
        clickView.addSubview(effect)

        host.wantsLayer = true
        host.layer?.addSublayer(tint)
        host.layer?.addSublayer(dropHighlight)
        tint.masksToBounds = true
        titleLayer.alignmentMode = .center
        titleLayer.truncationMode = .end
        titleLayer.allowsFontSubpixelQuantization = true
        host.layer?.addSublayer(titleLayer)
        workspaceChip.cornerRadius = 9
        workspaceText.alignmentMode = .center
        workspaceChip.addSublayer(workspaceText)
        host.layer?.addSublayer(workspaceChip)
        effect.addSubview(host)
    }

    /// `monitor` is the screen frame in Accessibility coordinates. `tiles` and `viewports` are in panel points.
    public func show(
        tiles: [Tile], viewports: [CGRect], labels: [Label] = [], panelSize: CGSize, selected: WindowID?,
        style: ResolvedStyle, on monitor: CGRect
    ) {
        theme = Theme(style)
        let cocoa = Displays.cocoaRect(monitor)
        panel.setFrame(cocoa, display: false)
        theme.configure(effect)
        effect.maskImage = Theme.roundedMask(radius: theme.cornerRadius)
        titleLayer.font = theme.font(20, .semibold)
        titleLayer.fontSize = theme.size(20)
        titleLayer.foregroundColor = theme.ink(0.95)
        workspaceText.font = theme.font(16, .medium)
        workspaceText.fontSize = theme.size(16)
        workspaceText.foregroundColor = theme.ink(1)
        dropHighlight.fillColor = theme.ink(0.10)
        let scale = NSScreen.screens.first { $0.frame.intersects(cocoa) }?.backingScaleFactor ?? 2

        let pad = Self.basePadding * CGFloat(style.scale)
        padding = pad
        titleHeight = Self.baseTitleHeight * CGFloat(style.scale)
        let size = CGSize(width: panelSize.width + 2 * pad, height: panelSize.height + 2 * pad + titleHeight)
        let origin = CGPoint(x: ((cocoa.width - size.width) / 2).rounded(), y: ((cocoa.height - size.height) / 2).rounded())
        let panelRect = CGRect(origin: origin, size: size)
        clickView.frame = CGRect(origin: .zero, size: cocoa.size)
        effect.frame = panelRect
        host.frame = CGRect(origin: .zero, size: size)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for layer in tileLayers.values { layer.removeFromSuperlayer() }
        tileLayers = [:]
        dragHome = [:]
        for layer in labelLayers { layer.removeFromSuperlayer() }
        labelLayers = []
        host.layer?.sublayers?.removeAll { $0 is CAShapeLayer && $0 !== dropHighlight }
        dropHighlight.isHidden = true

        tint.frame = host.bounds
        tint.cornerRadius = theme.cornerRadius
        tint.backgroundColor = theme.tint?.cgColor
        tint.borderColor = theme.border?.cgColor
        tint.borderWidth = theme.border == nil ? 0 : CGFloat(style.borderWidth)
        titleLayer.contentsScale = scale
        workspaceText.contentsScale = scale
        headerWidth = size.width
        selectedColor = theme.cg(theme.accent)

        /// Miniature space has its origin top-left; the layers use Cocoa's bottom-left.
        func place(_ rect: CGRect) -> CGRect {
            CGRect(x: pad + rect.minX, y: size.height - pad - rect.maxY, width: rect.width, height: rect.height)
        }

        for viewport in viewports {
            let outline = CAShapeLayer()
            let rect = place(viewport)
            outline.frame = rect
            outline.path = CGPath(
                roundedRect: CGRect(origin: .zero, size: rect.size).insetBy(dx: 0.5, dy: 0.5),
                cornerWidth: 6, cornerHeight: 6, transform: nil
            )
            outline.fillColor = nil
            outline.strokeColor = theme.ink(0.5)
            outline.lineWidth = 1
            outline.lineDashPattern = [6, 4]
            host.layer?.addSublayer(outline)
        }

        // A row is the drop target of its workspace: the band from its name down to the bottom of its picture.
        rowFrames = labels.map { label in
            let row = place(label.frame)
            return CGRect(x: 0, y: row.minY - 2, width: size.width, height: row.height + 26)
        }
        for label in labels {
            let text = CATextLayer()
            let row = place(label.frame)
            text.string = label.text
            text.fontSize = theme.size(14)
            text.font = theme.font(14)
            text.foregroundColor = theme.ink(0.8)
            text.truncationMode = .end
            text.contentsScale = scale
            text.frame = CGRect(x: row.minX, y: row.maxY + 3, width: row.width, height: 18)
            host.layer?.addSublayer(text)
            labelLayers.append(text)
        }

        var hitRects: [(WindowID, CGRect)] = []
        for tile in tiles {
            let layer = TileLayer(tile: tile, scale: scale, theme: theme)
            layer.frame = place(tile.frame)
            layer.relayout()
            host.layer?.addSublayer(layer)
            tileLayers[tile.id] = layer
            hitRects.append((tile.id, layer.frame.offsetBy(dx: origin.x, dy: origin.y)))
        }
        clickView.tiles = hitRects
        clickView.panelRect = panelRect
        clickView.rows = rowFrames.map { $0.offsetBy(dx: origin.x, dy: origin.y) }
        panelOrigin = origin

        applySelection(selected, animated: false)
        panel.orderFrontRegardless()
    }

    /// Shows only the hints that start with the keys typed so far.
    public func setHintPrefix(_ typed: String) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in tileLayers.values { layer.setHintPrefix(typed) }
        CATransaction.commit()
    }

    /// Moves the highlight. `nil` clears it.
    public func select(_ id: WindowID?) {
        applySelection(id, animated: true)
    }

    public func setImage(_ image: CGImage, for id: WindowID) {
        guard let layer = tileLayers[id] else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.tile.image = image
        layer.relayout()
        CATransaction.commit()
    }

    public func hide() {
        panel.orderOut(nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in tileLayers.values { layer.removeFromSuperlayer() }
        for layer in labelLayers { layer.removeFromSuperlayer() }
        host.layer?.sublayers?.removeAll { $0 is CAShapeLayer && $0 !== dropHighlight }
        dropHighlight.isHidden = true
        CATransaction.commit()
        tileLayers = [:]
        labelLayers = []
        rowFrames = []
        dragHome = [:]
        clickView.tiles = []
        clickView.rows = []
    }

    // MARK: Dragging

    /// The tile follows the pointer, and the row under it is highlighted. `point` is in the view of the monitor.
    private func dragMoved(_ id: WindowID, to point: CGPoint) {
        guard let layer = tileLayers[id] else { return }
        if dragHome[id] == nil { dragHome[id] = layer.position }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.zPosition = 10
        layer.position = CGPoint(x: point.x - panelOrigin.x, y: point.y - panelOrigin.y)
        if let row = rowIndex(at: point) {
            dropHighlight.frame = rowFrames[row]
            dropHighlight.path = CGPath(
                roundedRect: CGRect(origin: .zero, size: rowFrames[row].size).insetBy(dx: 1, dy: 1),
                cornerWidth: 10, cornerHeight: 10, transform: nil
            )
            dropHighlight.strokeColor = selectedColor
            dropHighlight.isHidden = false
        } else {
            dropHighlight.isHidden = true
        }
        CATransaction.commit()
    }

    private func dragEnded(_ id: WindowID, at point: CGPoint) {
        dropHighlight.isHidden = true
        if let layer = tileLayers[id] { layer.zPosition = 0 }
        let row = rowIndex(at: point)
        // The tile goes back first; a drop that moves the window rebuilds the overview anyway.
        putBack(id)
        if let row { onDrop?(id, row) }
    }

    private func putBack(_ id: WindowID) {
        guard let layer = tileLayers[id], let home = dragHome.removeValue(forKey: id) else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(theme.duration)
        layer.position = home
        CATransaction.commit()
    }

    private func rowIndex(at point: CGPoint) -> Int? {
        let local = CGPoint(x: point.x - panelOrigin.x, y: point.y - panelOrigin.y)
        return rowFrames.firstIndex { $0.contains(local) }
    }

    private func applySelection(_ id: WindowID?, animated: Bool) {
        CATransaction.begin()
        if animated && theme.duration > 0 {
            CATransaction.setAnimationDuration(theme.duration)
        } else {
            CATransaction.setDisableActions(true)
        }
        for (tileID, layer) in tileLayers {
            layer.setSelected(tileID == id, color: selectedColor)
            if tileID == id { layer.zPosition = 1 } else { layer.zPosition = 0 }
        }
        let tile = id.flatMap { tileLayers[$0]?.tile }
        layoutHeader(title: tile.map { [$0.appName, $0.title].filter { !$0.isEmpty }.joined(separator: " - ") } ?? "", workspace: tile?.workspace ?? "")
        CATransaction.commit()
    }

    /// The text of the header: the chip with the workspace, and the app and title of the selected window in the middle. The
    /// title keeps the same room at both sides, so it stays centered.
    private func layoutHeader(title: String, workspace: String) {
        let height = titleHeight
        let pad = padding
        var side = pad
        if workspace.isEmpty {
            workspaceChip.isHidden = true
        } else {
            let text = workspace.allSatisfy(\.isNumber) ? "Workspace " + workspace : workspace
            let font = theme.font(16, .medium)
            let width = ceil((text as NSString).size(withAttributes: [.font: font]).width) + 24
            workspaceChip.isHidden = false
            workspaceChip.backgroundColor = selectedColor.copy(alpha: 0.3)
            workspaceChip.frame = CGRect(x: pad, y: (height - 30) / 2, width: width, height: 30)
            workspaceText.string = text
            workspaceText.frame = CGRect(x: 0, y: 5, width: width, height: 20)
            side = pad + width + 14
        }
        titleLayer.string = title
        titleLayer.frame = CGRect(x: side, y: (height - 26) / 2, width: max(0, headerWidth - 2 * side), height: 26)
    }

}

/// Never key, never main: the app that the user works in keeps focus.
private final class SwitcherPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Covers the whole monitor so that a click outside the panel is seen.
private final class ClickView: NSView {
    /// Pointer travel, in points, that turns a click on a tile into a drag.
    private static let dragThreshold: CGFloat = 5

    var tiles: [(id: WindowID, rect: CGRect)] = []
    /// The rows that a tile can be dropped on. Without rows (the Alt+Tab switcher) a tile cannot be dragged.
    var rows: [CGRect] = []
    var panelRect: CGRect = .zero
    var onClick: ((WindowID?) -> Void)?
    var onDragMove: ((WindowID, CGPoint) -> Void)?
    var onDragEnd: ((WindowID, CGPoint) -> Void)?

    private var pressed: (id: WindowID, start: CGPoint)?
    private var dragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragging = false
        if let hit = tiles.first(where: { $0.rect.contains(point) }) {
            pressed = (hit.id, point)
            // A drag is only possible with rows to drop on; otherwise the press is a click at once.
            if rows.isEmpty { pressed = nil; onClick?(hit.id) }
        } else {
            pressed = nil
            if !panelRect.contains(point) { onClick?(nil) }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pressed else { return }
        let point = convert(event.locationInWindow, from: nil)
        if !dragging, hypot(point.x - pressed.start.x, point.y - pressed.start.y) < Self.dragThreshold { return }
        dragging = true
        onDragMove?(pressed.id, point)
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil; dragging = false }
        guard let pressed else { return }
        if dragging {
            onDragEnd?(pressed.id, convert(event.locationInWindow, from: nil))
        } else {
            onClick?(pressed.id)
        }
    }
}

/// One window in the miniature: thumbnail or icon plus title, a thin border, a dashed outline when floating.
private final class TileLayer: CALayer {
    var tile: SwitcherOverlay.Tile
    private let thumb = CALayer()
    private let badge = CALayer()
    private let icon = CALayer()
    private let label = CATextLayer()
    private let dash = CAShapeLayer()
    private let hint = CATextLayer()
    private let scale: CGFloat
    private let theme: Theme
    private var isSelected = false

    init(tile: SwitcherOverlay.Tile, scale: CGFloat, theme: Theme) {
        self.tile = tile
        self.scale = scale
        self.theme = theme
        super.init()
        contentsScale = scale
        cornerRadius = 8
        borderWidth = 1
        masksToBounds = false
        for layer in [thumb, badge, icon] {
            layer.contentsScale = scale
            addSublayer(layer)
        }
        // The picture fills the whole tile; what does not fit is cropped, so no empty bands show.
        thumb.contentsGravity = .resizeAspectFill
        thumb.cornerRadius = 5
        thumb.masksToBounds = true
        badge.contentsGravity = .resizeAspect
        icon.contentsGravity = .resizeAspect
        label.contentsScale = scale
        label.fontSize = theme.size(14)
        label.font = theme.font(14, .medium)
        label.alignmentMode = .center
        label.truncationMode = .end
        label.foregroundColor = theme.ink(1)
        addSublayer(label)
        dash.fillColor = nil
        dash.strokeColor = theme.ink(0.8)
        dash.lineWidth = 1.5
        dash.lineDashPattern = [5, 3]
        addSublayer(dash)
        hint.contentsScale = scale
        hint.fontSize = theme.size(15)
        hint.font = theme.monoFont(15, .bold)
        hint.alignmentMode = .center
        hint.foregroundColor = theme.ink(1)
        hint.backgroundColor = theme.scrimCG(0.75)
        hint.cornerRadius = 4
        addSublayer(hint)
        applyStyle(color: theme.ink(1))
    }

    override init(layer: Any) {
        let other = layer as! TileLayer
        tile = other.tile
        scale = other.scale
        theme = other.theme
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Lays out the sublayers for the current `tile` data. The caller disables implicit animations.
    func relayout() {
        let size = bounds.size
        let inset: CGFloat = 3
        let iconImage = tile.icon?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        if let image = tile.image {
            thumb.isHidden = false
            thumb.contents = image
            thumb.frame = bounds.insetBy(dx: inset, dy: inset)
            icon.isHidden = true
            label.isHidden = true
            let side = min(36, min(size.width, size.height) * 0.3)
            badge.isHidden = iconImage == nil
            badge.contents = iconImage
            badge.frame = CGRect(x: inset + 6, y: inset + 6, width: side, height: side)
        } else {
            thumb.isHidden = true
            thumb.contents = nil
            badge.isHidden = true
            let labelHeight: CGFloat = 20
            let side = max(0, min(72, min(size.width - 2 * inset, size.height - labelHeight - 3 * inset)))
            icon.isHidden = iconImage == nil
            icon.contents = iconImage
            icon.frame = CGRect(
                x: (size.width - side) / 2, y: (size.height + labelHeight) / 2 - side / 2 + inset / 2,
                width: side, height: side
            )
            label.isHidden = false
            label.string = tile.title.isEmpty ? tile.appName : tile.title
            label.frame = CGRect(x: inset, y: icon.frame.minY - labelHeight - 2, width: size.width - 2 * inset, height: labelHeight)
        }
        hint.isHidden = tile.hint == nil
        hint.string = tile.hint
        let hintWidth = CGFloat(tile.hint?.count ?? 0) * 10 + 12
        hint.frame = CGRect(x: size.width - hintWidth - inset, y: size.height - 22 - inset, width: hintWidth, height: 20)
        dash.isHidden = !tile.isFloating
        dash.frame = bounds
        dash.path = CGPath(
            roundedRect: bounds.insetBy(dx: 2, dy: 2), cornerWidth: 7, cornerHeight: 7, transform: nil
        )
    }

    func setHintPrefix(_ typed: String) {
        hint.opacity = tile.hint.map { $0.hasPrefix(typed) } ?? true ? 1 : 0.15
    }

    func setSelected(_ on: Bool, color: CGColor) {
        isSelected = on
        applyStyle(color: color)
        transform = on ? CATransform3DMakeScale(1.04, 1.04, 1) : CATransform3DIdentity
    }

    private func applyStyle(color: CGColor) {
        borderColor = isSelected ? color : theme.ink(0.25)
        borderWidth = isSelected ? 2 : 1
        backgroundColor = theme.ink(isSelected ? 0.22 : 0.08)
    }
}
