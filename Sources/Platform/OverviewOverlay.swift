import AppKit
import Core

/// The overview of all workspaces: a rounded panel in the middle of the screen with a search field on top and one row for
/// each workspace. A row shows its workspace in its own layout (a scrolling strip, or the tiles of the screen), every
/// window as a card with its picture, its app icon and its title. It only draws what it is given, and never takes the
/// keyboard: the keys come from the event tap.
@MainActor
public final class OverviewOverlay {
    public struct Card {
        public var id: WindowID
        public var title: String
        public var appName: String
        public var icon: NSImage?
        public var image: CGImage?
        public var isFloating: Bool

        public init(id: WindowID, title: String, appName: String, icon: NSImage? = nil, image: CGImage? = nil, isFloating: Bool = false) {
            self.id = id
            self.title = title
            self.appName = appName
            self.icon = icon
            self.image = image
            self.isFloating = isFloating
        }
    }

    public struct RowInfo {
        public var name: String
        /// For example `scrolling · 3 windows`.
        public var subtitle: String
        /// The workspace that the focused monitor shows.
        public var isCurrent: Bool
        /// The empty row at the end: a window dropped on it goes to a new workspace.
        public var isNew: Bool
        /// The workspace has no window: its row shows the shape of the screen.
        public var isEmpty: Bool

        public init(name: String, subtitle: String, isCurrent: Bool = false, isNew: Bool = false, isEmpty: Bool = false) {
            self.name = name
            self.subtitle = subtitle
            self.isCurrent = isCurrent
            self.isNew = isNew
            self.isEmpty = isEmpty
        }
    }

    /// A click on a card gives its id. A click outside the panel gives `nil`.
    public var onClick: ((WindowID?) -> Void)?
    /// The close button of a card.
    public var onClose: ((WindowID) -> Void)?
    /// The pointer moved onto a card.
    public var onHover: ((WindowID) -> Void)?
    /// A card was dragged and dropped on the row with this index.
    public var onDrop: ((WindowID, Int) -> Void)?
    public var isShown: Bool { panel.isVisible }
    /// Where the panel is on the screen, with the origin at the top left of the screen.
    public var panelFrame: CGRect { panelRect }

    private static let cornerRadius: CGFloat = 26
    private static let dragThreshold: CGFloat = 5

    private let panel = OverviewPanel()
    private let root = OverviewRoot()
    private let effect = FlippedEffectView()
    private let tint = FlippedView()
    private let searchView = SearchView()
    private let clip = FlippedView()
    private let content = FlippedView()

    private var rowViews: [RowView] = []
    private var cardViews: [WindowID: CardView] = [:]
    private var geometry: OverviewGeometry?
    private var panelRect: CGRect = .zero
    private var scrollOffset: CGFloat = 0
    private var hovered: WindowID?
    private var pressed: (id: WindowID, start: CGPoint, home: CGPoint)?
    private var dragging = false

    public init() {
        panel.contentView = root
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)
        effect.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        root.addSubview(effect)
        // `maskImage` only rounds the blur: the tint needs the same corners, and a thin edge.
        tint.wantsLayer = true
        tint.layer?.cornerRadius = Self.cornerRadius
        tint.layer?.masksToBounds = true
        tint.layer?.borderWidth = 1
        tint.layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        effect.addSubview(tint)
        effect.addSubview(searchView)
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        effect.addSubview(clip)
        clip.addSubview(content)

        root.onDown = { [weak self] point in self?.mouseDown(at: point) }
        root.onDrag = { [weak self] point in self?.mouseDragged(to: point) }
        root.onUp = { [weak self] point in self?.mouseUp(at: point) }
        root.onMove = { [weak self] point in self?.mouseMoved(to: point) }
        root.onExit = { [weak self] in self?.setHovered(nil) }
        root.onScroll = { [weak self] delta in self?.scroll(by: delta) }
    }

    // MARK: - Showing

    /// `monitor` is the screen frame in Accessibility coordinates. The geometry, the rows and the cards describe the
    /// panel; the panel is put in the middle of the screen.
    public func show(
        geometry: OverviewGeometry, rows: [RowInfo], cards: [Card], selected: WindowID?, query: String, accent: NSColor,
        background: NSColor, on monitor: CGRect
    ) {
        clear()
        self.geometry = geometry
        let cocoa = Displays.cocoaRect(monitor)
        panel.setFrame(cocoa, display: false)
        root.frame = CGRect(origin: .zero, size: cocoa.size)
        // The root is flipped, so the panel is placed with the origin at the top left like everything inside.
        panelRect = CGRect(
            x: ((cocoa.width - geometry.panel.width) / 2).rounded(), y: ((cocoa.height - geometry.panel.height) / 2).rounded(),
            width: geometry.panel.width, height: geometry.panel.height)
        root.panelRect = panelRect
        effect.frame = panelRect
        tint.frame = effect.bounds
        tint.layer?.backgroundColor = background.cgColor

        searchView.accent = accent
        let searchWidth = min(560, geometry.panel.width * 0.62)
        searchView.frame = CGRect(x: (geometry.panel.width - searchWidth) / 2, y: 20, width: searchWidth, height: 38)
        searchView.update(query: query, count: cards.count)

        clip.frame = CGRect(x: 0, y: geometry.rowsTop, width: geometry.panel.width, height: geometry.rowsViewportHeight)
        content.frame = CGRect(x: 0, y: 0, width: geometry.panel.width, height: geometry.contentHeight)
        scrollOffset = 0

        for (index, info) in rows.enumerated() where geometry.rows.indices.contains(index) {
            let row = RowView(info: info, geometry: geometry.rows[index], accent: accent)
            row.frame = CGRect(x: 0, y: geometry.rows[index].stage.minY - geometry.rowsTop, width: geometry.panel.width, height: geometry.rows[index].stage.height)
            content.addSubview(row)
            rowViews.append(row)
        }
        for card in cards {
            guard let rect = geometry.cards[card.id] else { continue }
            let view = CardView(card: card, accent: accent)
            view.frame = rect.offsetBy(dx: 0, dy: -geometry.rowsTop).insetBy(dx: -CardView.bleed, dy: -CardView.bleed)
            content.addSubview(view)
            cardViews[card.id] = view
        }
        select(selected)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    public func hide() {
        panel.orderOut(nil)
        clear()
    }

    private func clear() {
        for view in rowViews { view.removeFromSuperview() }
        for view in cardViews.values { view.removeFromSuperview() }
        rowViews = []
        cardViews = [:]
        hovered = nil
        pressed = nil
        dragging = false
        geometry = nil
    }

    // MARK: - Updates

    /// Moves the highlight. `nil` clears it.
    public func select(_ id: WindowID?) {
        for (cardID, view) in cardViews { view.isSelected = cardID == id }
        if let id { ensureVisible(id) }
    }

    public func setImage(_ image: CGImage, for id: WindowID) {
        cardViews[id]?.setImage(image)
    }

    /// The text of the search field. With `matches`, the cards that are not in it are dimmed.
    public func setSearch(_ query: String, matches: Set<WindowID>?, total: Int) {
        searchView.update(query: query, count: matches?.count ?? total)
        for (id, view) in cardViews { view.isDimmed = matches.map { !$0.contains(id) } ?? false }
    }

    // MARK: - Scrolling

    private var maxScroll: CGFloat {
        guard let geometry else { return 0 }
        return max(0, geometry.contentHeight - geometry.rowsViewportHeight)
    }

    private func scroll(by delta: CGFloat) {
        setScroll(scrollOffset - delta)
    }

    private func setScroll(_ value: CGFloat) {
        scrollOffset = min(max(value, 0), maxScroll)
        content.setFrameOrigin(CGPoint(x: 0, y: -scrollOffset))
    }

    /// Scrolls the rows so that the card is inside the part that shows them.
    private func ensureVisible(_ id: WindowID) {
        guard let geometry, let view = cardViews[id] else { return }
        let rect = view.frame.insetBy(dx: CardView.bleed, dy: CardView.bleed)
        let margin: CGFloat = 12
        if rect.minY - margin < scrollOffset {
            setScroll(rect.minY - margin)
        } else if rect.maxY + margin > scrollOffset + geometry.rowsViewportHeight {
            setScroll(rect.maxY + margin - geometry.rowsViewportHeight)
        }
    }

    // MARK: - Mouse

    private func cardID(at point: CGPoint) -> WindowID? {
        guard clip.bounds.contains(clip.convert(point, from: root)) else { return nil }
        let local = content.convert(point, from: root)
        let hits = cardViews.filter { $0.value.frame.insetBy(dx: CardView.bleed, dy: CardView.bleed).contains(local) }
        // The smallest card wins: a floating window lies on top of the tiles.
        return hits.min { $0.value.frame.width * $0.value.frame.height < $1.value.frame.width * $1.value.frame.height }?.key
    }

    private func rowIndex(at point: CGPoint) -> Int? {
        guard clip.bounds.contains(clip.convert(point, from: root)) else { return nil }
        let local = content.convert(point, from: root)
        return rowViews.firstIndex { $0.frame.contains(local) }
    }

    private func setHovered(_ id: WindowID?) {
        guard id != hovered else { return }
        if let old = hovered { cardViews[old]?.isHovered = false }
        hovered = id
        if let id { cardViews[id]?.isHovered = true }
    }

    private func mouseDown(at point: CGPoint) {
        dragging = false
        guard panelRect.contains(point) else {
            pressed = nil
            onClick?(nil)
            return
        }
        guard let id = cardID(at: point), let view = cardViews[id] else {
            pressed = nil
            return
        }
        if view.closeRect.contains(view.convert(point, from: root)) {
            pressed = nil
            onClose?(id)
            return
        }
        pressed = (id, point, view.frame.origin)
    }

    private func mouseDragged(to point: CGPoint) {
        guard let pressed, let view = cardViews[pressed.id] else { return }
        if !dragging {
            guard hypot(point.x - pressed.start.x, point.y - pressed.start.y) >= Self.dragThreshold else { return }
            dragging = true
            content.addSubview(view, positioned: .above, relativeTo: nil)
        }
        view.setFrameOrigin(CGPoint(x: pressed.home.x + point.x - pressed.start.x, y: pressed.home.y + point.y - pressed.start.y))
        let target = rowIndex(at: point)
        for (index, row) in rowViews.enumerated() { row.isDropTarget = index == target }
    }

    private func mouseUp(at point: CGPoint) {
        defer {
            pressed = nil
            dragging = false
        }
        guard let pressed else { return }
        if dragging {
            let row = rowIndex(at: point)
            for view in rowViews { view.isDropTarget = false }
            // The card goes back first; a drop that moves the window builds the overview again.
            cardViews[pressed.id]?.setFrameOrigin(pressed.home)
            if let row { onDrop?(pressed.id, row) }
        } else {
            onClick?(pressed.id)
        }
    }

    private func mouseMoved(to point: CGPoint) {
        let id = cardID(at: point)
        setHovered(id)
        if let id { onHover?(id) }
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

// MARK: - Window and views

/// Never key, never main: the app that the user works in keeps the focus.
private final class OverviewPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class FlippedEffectView: NSVisualEffectView {
    override var isFlipped: Bool { true }
}

/// Covers the monitor, so that a click outside the panel is seen. It turns the mouse into plain callbacks.
private final class OverviewRoot: NSView {
    var panelRect: CGRect = .zero
    var onDown: ((CGPoint) -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onUp: ((CGPoint) -> Void)?
    var onMove: ((CGPoint) -> Void)?
    var onExit: (() -> Void)?
    var onScroll: ((CGFloat) -> Void)?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseDown(with event: NSEvent) { onDown?(point(event)) }
    override func mouseDragged(with event: NSEvent) { onDrag?(point(event)) }
    override func mouseUp(with event: NSEvent) { onUp?(point(event)) }
    override func mouseMoved(with event: NSEvent) { onMove?(point(event)) }
    override func mouseExited(with event: NSEvent) { onExit?() }

    override func scrollWheel(with event: NSEvent) {
        // A mouse wheel gives lines, a trackpad gives points.
        onScroll?(event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12)
    }
}

/// The pill at the top: a magnifier, what was typed (or a hint) and the number of windows.
private final class SearchView: FlippedView {
    var accent = NSColor.systemBlue
    private var query = ""
    private var count = 0

    func update(query: String, count: Int) {
        self.query = query
        self.count = count
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor(white: 1, alpha: 0.09).setFill()
        pill.fill()
        (query.isEmpty ? NSColor(white: 1, alpha: 0.12) : accent.withAlphaComponent(0.7)).setStroke()
        pill.lineWidth = 1
        pill.stroke()

        // The magnifier.
        let glass = NSBezierPath(ovalIn: CGRect(x: 16, y: bounds.midY - 7, width: 10, height: 10))
        glass.move(to: CGPoint(x: 25, y: bounds.midY + 2))
        glass.line(to: CGPoint(x: 30, y: bounds.midY + 7))
        glass.lineWidth = 1.6
        glass.lineCapStyle = .round
        NSColor(white: 1, alpha: 0.55).setStroke()
        glass.stroke()

        let font = NSFont.systemFont(ofSize: 14)
        let count = "\(self.count) window\(self.count == 1 ? "" : "s")"
        let countAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor(white: 1, alpha: 0.45)]
        let countSize = (count as NSString).size(withAttributes: countAttributes)
        (count as NSString).draw(at: CGPoint(x: bounds.maxX - 18 - countSize.width, y: bounds.midY - countSize.height / 2), withAttributes: countAttributes)

        let text = query.isEmpty ? "Type to search…" : query
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor(white: 1, alpha: query.isEmpty ? 0.42 : 0.95),
            .paragraphStyle: Self.truncating,
        ]
        let room = bounds.width - 44 - countSize.width - 36
        let height = (text as NSString).size(withAttributes: attributes).height
        (text as NSString).draw(in: CGRect(x: 40, y: bounds.midY - height / 2, width: room, height: height), withAttributes: attributes)
    }

    private static let truncating: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingHead
        return style
    }()
}

/// One workspace: its name and layout at the left, and the rounded stage behind its windows.
private final class RowView: FlippedView {
    let info: OverviewOverlay.RowInfo
    private let geometry: OverviewRowGeometry
    private let accent: NSColor
    /// A card is dragged over this row.
    var isDropTarget = false { didSet { needsDisplay = true } }

    init(info: OverviewOverlay.RowInfo, geometry: OverviewRowGeometry, accent: NSColor) {
        self.info = info
        self.geometry = geometry
        self.accent = accent
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// The geometry is in the panel; this view starts at the top of its stage.
    private var stage: CGRect { CGRect(x: geometry.stage.minX, y: 0, width: geometry.stage.width, height: geometry.stage.height) }
    private func local(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: 0, dy: -geometry.stage.minY) }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: stage.insetBy(dx: 0.5, dy: 0.5), xRadius: 16, yRadius: 16)
        NSColor(white: 1, alpha: isDropTarget ? 0.13 : info.isCurrent ? 0.075 : 0.05).setFill()
        path.fill()
        if isDropTarget {
            accent.withAlphaComponent(0.95).setStroke()
            path.lineWidth = 2
        } else {
            (info.isCurrent ? accent.withAlphaComponent(0.4) : NSColor(white: 1, alpha: 0.08)).setStroke()
            path.lineWidth = 1
        }
        path.stroke()

        // The part of the layout that is on screen now.
        for viewport in geometry.viewports {
            let outline = NSBezierPath(roundedRect: local(viewport).insetBy(dx: -3, dy: -3), xRadius: 11, yRadius: 11)
            outline.lineWidth = 1.2
            outline.setLineDash([5, 4], count: 2, phase: 0)
            accent.withAlphaComponent(0.55).setStroke()
            outline.stroke()
        }

        // An empty workspace shows the shape of its screen.
        if info.isNew || info.isEmpty {
            let screen = NSBezierPath(roundedRect: local(geometry.content), xRadius: 10, yRadius: 10)
            screen.lineWidth = 1.2
            screen.setLineDash([6, 5], count: 2, phase: 0)
            NSColor(white: 1, alpha: 0.2).setStroke()
            screen.stroke()
            let text = info.isNew ? "Drop a window here" : "Empty"
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.4)]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: CGPoint(x: local(geometry.content).midX - size.width / 2, y: local(geometry.content).midY - size.height / 2), withAttributes: attributes)
        }

        drawLabel()
    }

    private func drawLabel() {
        let label = CGRect(x: geometry.label.minX, y: 0, width: geometry.label.width - 8, height: geometry.label.height)
        let long = info.name.count > 3
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: long ? 15 : 30, weight: .semibold),
            .foregroundColor: NSColor(white: 1, alpha: info.isNew ? 0.35 : 0.92),
            .paragraphStyle: Self.truncating,
        ]
        let name = info.isNew ? "+" : info.name
        let nameHeight = (name as NSString).size(withAttributes: nameAttributes).height
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.42),
            .paragraphStyle: Self.truncating,
        ]
        let subtitleHeight = (info.subtitle as NSString).size(withAttributes: subtitleAttributes).height
        let total = nameHeight + 2 + subtitleHeight
        let top = label.midY - total / 2
        (name as NSString).draw(in: CGRect(x: label.minX, y: top, width: label.width, height: nameHeight), withAttributes: nameAttributes)
        (info.subtitle as NSString).draw(in: CGRect(x: label.minX, y: top + nameHeight + 2, width: label.width, height: subtitleHeight), withAttributes: subtitleAttributes)
        if info.isCurrent {
            accent.setFill()
            NSBezierPath(ovalIn: CGRect(x: label.minX - 14, y: label.midY - 3, width: 6, height: 6)).fill()
        }
    }

    private static let truncating: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }()
}

/// One window: its picture (or its icon), a bar with the icon and the title, and a ring when it is selected. The view is
/// larger than the card by `bleed` on every side, for the glow of the ring.
private final class CardView: NSView {
    static let bleed: CGFloat = 14

    private(set) var card: OverviewOverlay.Card
    private var picture: NSImage?
    private let accent: NSColor
    var isSelected = false { didSet { if oldValue != isSelected { needsDisplay = true } } }
    var isHovered = false { didSet { if oldValue != isHovered { needsDisplay = true } } }
    var isDimmed = false { didSet { if oldValue != isDimmed { needsDisplay = true } } }

    override var isFlipped: Bool { true }

    init(card: OverviewOverlay.Card, accent: NSColor) {
        self.card = card
        self.accent = accent
        super.init(frame: .zero)
        if let image = card.image { picture = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)) }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setImage(_ image: CGImage) {
        card.image = image
        picture = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        needsDisplay = true
    }

    private var body: CGRect { bounds.insetBy(dx: Self.bleed, dy: Self.bleed) }

    /// The close button, in the coordinates of this view. It only exists while the pointer is on the card.
    var closeRect: CGRect {
        guard isHovered else { return .null }
        return CGRect(x: body.maxX - 28, y: body.minY + 6, width: 22, height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        let body = self.body
        let radius = min(max(min(body.width, body.height) * 0.07, 5), 12)
        let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

        // The shadow, or the glow of the selection.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = isSelected ? accent.withAlphaComponent(0.85) : NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = isSelected ? 14 : 7
        shadow.shadowOffset = .zero
        shadow.set()
        NSColor(white: 0.12, alpha: 1).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        NSColor(white: 0.13, alpha: 1).setFill()
        body.fill()
        if let picture {
            // The picture fills the card and is cut at the edges, like a window that is a little larger than its tile.
            let scale = max(body.width / picture.size.width, body.height / picture.size.height)
            let size = CGSize(width: picture.size.width * scale, height: picture.size.height * scale)
            picture.draw(
                in: CGRect(x: body.midX - size.width / 2, y: body.minY, width: size.width, height: size.height),
                from: .zero, operation: .sourceOver, fraction: isDimmed ? 0.35 : 1, respectFlipped: true, hints: nil)
        } else if let icon = card.icon {
            let side = min(64, min(body.width, body.height) * 0.45)
            icon.draw(
                in: CGRect(x: body.midX - side / 2, y: body.midY - side / 2 - 8, width: side, height: side),
                from: .zero, operation: .sourceOver, fraction: isDimmed ? 0.35 : 1, respectFlipped: true, hints: nil)
        }
        drawFooter(in: body)
        if isDimmed {
            NSColor.black.withAlphaComponent(0.45).setFill()
            body.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        shape.lineWidth = isSelected ? 2.5 : 1
        (isSelected ? accent : NSColor(white: 1, alpha: isHovered ? 0.4 : 0.16)).setStroke()
        shape.stroke()
        if card.isFloating {
            let dash = NSBezierPath(roundedRect: body.insetBy(dx: 3, dy: 3), xRadius: radius, yRadius: radius)
            dash.lineWidth = 1.2
            dash.setLineDash([5, 3], count: 2, phase: 0)
            NSColor(white: 1, alpha: 0.55).setStroke()
            dash.stroke()
        }
        if isHovered { drawCloseButton() }
    }

    private func drawFooter(in body: CGRect) {
        guard body.width >= 80, body.height >= 56 else { return }
        let height: CGFloat = 28
        let bar = CGRect(x: body.minX, y: body.maxY - height, width: body.width, height: height)
        NSColor.black.withAlphaComponent(0.58).setFill()
        bar.fill()
        var x = bar.minX + 9
        if let icon = card.icon {
            icon.draw(in: CGRect(x: x, y: bar.midY - 8, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            x += 23
        }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.95), .paragraphStyle: style,
        ]
        let text = card.title.isEmpty ? card.appName : card.title
        let textHeight = (text as NSString).size(withAttributes: attributes).height
        (text as NSString).draw(in: CGRect(x: x, y: bar.midY - textHeight / 2, width: bar.maxX - x - 8, height: textHeight), withAttributes: attributes)
    }

    private func drawCloseButton() {
        let rect = closeRect
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: rect).fill()
        let cross = NSBezierPath()
        let inset: CGFloat = 7
        cross.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
        cross.line(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        cross.move(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
        cross.line(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        cross.lineWidth = 1.8
        cross.lineCapStyle = .round
        NSColor.white.setStroke()
        cross.stroke()
    }
}
