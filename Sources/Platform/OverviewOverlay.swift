import AppKit
import Core

/// The overview of all workspaces, as in Niri: the screen goes dark (a short fade), and every workspace is a small copy of its screen in one
/// column. The workspace that you are on sits in the middle, the ones before and after it show above and below, and the
/// column scrolls. Every window is a card with its picture, its app icon and its title. It only draws what it is given, and
/// never takes the keyboard: the keys come from the event tap.
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
        /// The empty slot at the end: a window dropped on it goes to a new workspace.
        public var isNew: Bool
        /// The workspace has no window: its slot shows the shape of the screen.
        public var isEmpty: Bool

        public init(name: String, subtitle: String, isCurrent: Bool = false, isNew: Bool = false, isEmpty: Bool = false) {
            self.name = name
            self.subtitle = subtitle
            self.isCurrent = isCurrent
            self.isNew = isNew
            self.isEmpty = isEmpty
        }
    }

    /// A click on a card gives its id. A click on the backdrop gives `nil`.
    public var onClick: ((WindowID?) -> Void)?
    /// The close button of a card.
    public var onClose: ((WindowID) -> Void)?
    /// The pointer moved onto a card.
    public var onHover: ((WindowID) -> Void)?
    /// A card was dragged and dropped on the slot with this index.
    public var onDrop: ((WindowID, Int) -> Void)?
    public var isShown: Bool { panel.isVisible && !isHiding }

    private static let dragThreshold: CGFloat = 5

    private let panel = OverviewPanel()
    private let root = OverviewRoot()
    private let backdrop = CALayer()
    /// The column of workspaces: as tall as the geometry says, and moved up and down to scroll.
    private let world = CALayer()
    private let search = SearchLayer()
    private var theme = Theme.placeholder

    private var slots: [SlotLayer] = []
    private var cards: [WindowID: WindowCardLayer] = [:]
    private var geometry: OverviewGeometry?
    private var screenSize: CGSize = .zero
    private var scroll: CGFloat = 0
    private var hovered: WindowID?
    private var pressed: (id: WindowID, start: CGPoint, home: CGPoint)?
    private var dragging = false
    private var revealsSelection = true
    /// A new `show` or `hide` makes the end of the animation before it do nothing.
    private var generation = 0
    private var isHiding = false

    public init() {
        panel.contentView = root
        root.wantsLayer = true
        root.layer?.addSublayer(backdrop)
        root.layer?.addSublayer(world)
        root.layer?.addSublayer(search)

        root.onDown = { [weak self] point in self?.mouseDown(at: point) }
        root.onDrag = { [weak self] point in self?.mouseDragged(to: point) }
        root.onUp = { [weak self] point in self?.mouseUp(at: point) }
        root.onMove = { [weak self] point in self?.mouseMoved(to: point) }
        root.onExit = { [weak self] in self?.setHovered(nil) }
        root.onScroll = { [weak self] delta in self?.scroll(by: delta) }
    }

    // MARK: - Showing

    /// `monitor` is the screen frame in Accessibility coordinates; the overview covers it. `row` is the slot that starts in the
    /// middle. With `animated` the overview fades in; else it is just there.
    public func show(
        geometry: OverviewGeometry, rows: [RowInfo], cards newCards: [Card], row: Int, selected: WindowID?, query: String,
        style: ResolvedStyle, on monitor: CGRect, animated: Bool
    ) {
        theme = Theme(style)
        generation += 1
        isHiding = false
        root.layer?.removeAllAnimations()
        clear()
        self.geometry = geometry
        let cocoa = Displays.cocoaRect(monitor)
        panel.setFrame(cocoa, display: false)
        panel.ignoresMouseEvents = false
        root.frame = CGRect(origin: .zero, size: cocoa.size)
        screenSize = cocoa.size
        let scale = NSScreen.screens.first { $0.frame.intersects(cocoa) }?.backingScaleFactor ?? 2
        let accentColor = theme.cg(theme.accent)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = root.bounds
        backdrop.backgroundColor = theme.style.overviewBackdrop.map(Theme.cgColor) ?? theme.scrimCG(0.6)
        world.frame = CGRect(x: 0, y: 0, width: geometry.screen.width, height: geometry.worldHeight)
        for (index, slot) in geometry.slots.enumerated() where rows.indices.contains(index) {
            let layer = SlotLayer(info: rows[index], theme: theme, accent: accentColor, scale: scale)
            layer.frame = worldRect(slot.frame)
            layer.relayout(viewports: slot.viewports.map { $0.offsetBy(dx: -slot.frame.minX, dy: -slot.frame.minY) })
            world.addSublayer(layer)
            slots.append(layer)
        }
        for card in newCards {
            guard let rect = geometry.cards[card.id] else { continue }
            let layer = WindowCardLayer(
                id: card.id, title: card.title, appName: card.appName, icon: card.icon, image: card.image, isFloating: card.isFloating,
                theme: theme, accent: accentColor, scale: scale)
            layer.frame = worldRect(rect)
            layer.relayout()
            world.addSublayer(layer)
            cards[card.id] = layer
        }
        search.configure(theme: theme, accent: accentColor, scale: scale)
        let searchWidth = min(520, screenSize.width * 0.5)
        search.frame = CGRect(x: (screenSize.width - searchWidth) / 2, y: screenSize.height - 28 - SearchLayer.height, width: searchWidth, height: SearchLayer.height)
        search.update(query: query, count: newCards.count)
        setScroll(geometry.centers.indices.contains(row) ? geometry.centers[row] : 0, animated: false)
        CATransaction.commit()
        select(selected, reveal: false)
        if let selected { center(on: selected, animated: false, vertical: false) }

        root.layer?.opacity = 1
        let wasShown = panel.isVisible
        panel.orderFrontRegardless()
        if animated, !wasShown, theme.duration > 0 { animateOpen() }
    }

    public func hide() {
        guard panel.isVisible, !isHiding else { return }
        isHiding = true
        generation += 1
        let current = generation
        pressed = nil
        dragging = false
        panel.ignoresMouseEvents = true
        let duration = theme.duration
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeIn))
        root.layer?.opacity = 0
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                self.panel.orderOut(nil)
                self.clear()
                self.isHiding = false
            }
        }
    }

    /// The overview fades in (0.12 s). Nothing moves, so the first frame is already the final picture.
    private func animateOpen() {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = theme.duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        root.layer?.add(fade, forKey: "open-fade")
    }

    private func clear() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in slots { layer.removeFromSuperlayer() }
        for layer in cards.values { layer.removeFromSuperlayer() }
        CATransaction.commit()
        slots = []
        cards = [:]
        hovered = nil
        pressed = nil
        dragging = false
        geometry = nil
    }

    // MARK: - Coordinates

    /// A rectangle of the world (origin at the top left of the world) as a layer frame inside `world`.
    private func worldRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: (geometry?.worldHeight ?? 0) - rect.maxY, width: rect.width, height: rect.height)
    }

    /// A point of the layers of the overlay (the origin at the bottom left) as a point of the screen with the origin at the top left.
    private func screenPoint(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: screenSize.height - point.y) }

    private func worldPoint(_ screenPoint: CGPoint) -> CGPoint { CGPoint(x: screenPoint.x, y: screenPoint.y + scroll) }

    /// `true` when a point of the screen (origin at its top left) is on a workspace, a card or the search field. The controller
    /// closes the overview for a click anywhere else.
    public func isOnContent(_ point: CGPoint) -> Bool {
        guard let geometry else { return false }
        let inWorld = worldPoint(point)
        if search.frame.contains(CGPoint(x: point.x, y: screenSize.height - point.y)) { return true }
        if geometry.card(at: inWorld) != nil { return true }
        return geometry.slots.contains { $0.frame.insetBy(dx: -6, dy: -6).contains(inWorld) }
    }

    // MARK: - Updates

    /// Moves the highlight. `nil` clears it. Unless `reveal` is false, the column scrolls to put the workspace of the card in the
    /// middle of the screen, and a wide strip moves sideways to put the card there too.
    public func select(_ id: WindowID?, reveal: Bool = true) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (cardID, layer) in cards { layer.isSelected = cardID == id }
        CATransaction.commit()
        if let id, reveal, revealsSelection { center(on: id, animated: true) }
    }

    /// The card goes to the middle: its workspace vertically (when `vertical`), and the layout of the workspace sideways when it
    /// is wider than the screen.
    private func center(on id: WindowID, animated: Bool, vertical: Bool = true) {
        guard let geometry, let index = geometry.slotIndex(ofCard: id) else { return }
        if vertical, geometry.centers.indices.contains(index) { setScroll(geometry.centers[index], animated: animated) }
        let dx = geometry.panToCenter(id)
        guard dx != 0 else { return }
        self.geometry?.pan(slot: index, by: dx)
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.22)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        for cardID in geometry.cardIDs(inSlot: index) { cards[cardID]?.frame.origin.x += dx }
        if slots.indices.contains(index) { slots[index].pan(by: dx) }
        CATransaction.commit()
    }

    public func setImage(_ image: CGImage, for id: WindowID) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cards[id]?.setImage(image)
        CATransaction.commit()
    }

    /// The text of the search field. With `matches`, the cards that are not in it are dimmed.
    public func setSearch(_ query: String, matches: Set<WindowID>?, total: Int) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        search.update(query: query, count: matches?.count ?? total)
        for (id, layer) in cards { layer.isDimmed = matches.map { !$0.contains(id) } ?? false }
        CATransaction.commit()
    }

    // MARK: - Scrolling

    private func scroll(by delta: CGFloat) {
        guard let geometry else { return }
        setScroll(geometry.clampedScroll(scroll - delta), animated: false)
    }

    private func setScroll(_ value: CGFloat, animated: Bool) {
        guard let geometry else { return }
        scroll = geometry.clampedScroll(value)
        // The world is as tall as `worldHeight`; its top edge sits `scroll` points above the top of the screen.
        let frame = CGRect(x: 0, y: screenSize.height - geometry.worldHeight + scroll, width: geometry.screen.width, height: geometry.worldHeight)
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.22)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        world.frame = frame
        CATransaction.commit()
    }

    // MARK: - Mouse

    private func setHovered(_ id: WindowID?) {
        guard id != hovered else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let old = hovered { cards[old]?.isHovered = false }
        hovered = id
        if let id { cards[id]?.isHovered = true }
        CATransaction.commit()
    }

    private func closeRect(of id: WindowID) -> CGRect {
        guard let rect = geometry?.cards[id] else { return .null }
        return CGRect(
            x: rect.maxX - WindowCardLayer.closeSize - WindowCardLayer.closeInset, y: rect.minY + WindowCardLayer.closeInset,
            width: WindowCardLayer.closeSize, height: WindowCardLayer.closeSize)
    }

    private func mouseDown(at raw: CGPoint) {
        dragging = false
        let point = screenPoint(raw)
        guard isOnContent(point) else {
            pressed = nil
            onClick?(nil)
            return
        }
        guard let geometry, let id = geometry.card(at: worldPoint(point)), let layer = cards[id] else {
            pressed = nil
            return
        }
        if layer.isHovered, closeRect(of: id).contains(worldPoint(point)) {
            pressed = nil
            onClose?(id)
            return
        }
        pressed = (id, point, layer.frame.origin)
    }

    private func mouseDragged(to raw: CGPoint) {
        guard let pressed, let layer = cards[pressed.id], let geometry else { return }
        let point = screenPoint(raw)
        if !dragging {
            guard hypot(point.x - pressed.start.x, point.y - pressed.start.y) >= Self.dragThreshold else { return }
            dragging = true
            layer.zPosition = 1000
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame.origin = CGPoint(x: pressed.home.x + point.x - pressed.start.x, y: pressed.home.y - (point.y - pressed.start.y))
        let target = geometry.slotIndex(at: worldPoint(point))
        for (index, slot) in slots.enumerated() { slot.isDropTarget = index == target }
        CATransaction.commit()
    }

    private func mouseUp(at raw: CGPoint) {
        defer {
            pressed = nil
            dragging = false
        }
        guard let pressed else { return }
        if dragging {
            let target = geometry?.slotIndex(at: worldPoint(screenPoint(raw)))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for slot in slots { slot.isDropTarget = false }
            // The card goes back first; a drop that moves the window builds the overview again.
            cards[pressed.id]?.frame.origin = pressed.home
            cards[pressed.id]?.zPosition = 0
            CATransaction.commit()
            if let target { onDrop?(pressed.id, target) }
        } else {
            onClick?(pressed.id)
        }
    }

    private func mouseMoved(to raw: CGPoint) {
        guard let geometry else { return }
        let id = geometry.card(at: worldPoint(screenPoint(raw)))
        setHovered(id)
        if let id {
            // The pointer does not scroll the column: a card that is half on screen stays where it is.
            revealsSelection = false
            onHover?(id)
            revealsSelection = true
        }
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

/// Covers the monitor, so that a click on the backdrop is seen. It turns the mouse into plain callbacks.
private final class OverviewRoot: NSView {
    var onDown: ((CGPoint) -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onUp: ((CGPoint) -> Void)?
    var onMove: ((CGPoint) -> Void)?
    var onExit: (() -> Void)?
    var onScroll: ((CGFloat) -> Void)?

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

/// The pill at the top: what was typed (or a hint) and the number of windows.
private final class SearchLayer: CALayer {
    static let height: CGFloat = 38

    private let text = CATextLayer()
    private let countText = CATextLayer()
    private let glass = CAShapeLayer()
    private var accent = CGColor(gray: 1, alpha: 1)
    private var theme = Theme.placeholder

    override init() {
        super.init()
        cornerRadius = Self.height / 2
        borderWidth = 1
        text.truncationMode = .start
        countText.alignmentMode = .right
        glass.fillColor = nil
        glass.lineWidth = 1.6
        glass.lineCap = .round
        for layer in [glass, text, countText] { addSublayer(layer) }
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(theme: Theme, accent: CGColor, scale: CGFloat) {
        self.accent = accent
        self.theme = theme
        backgroundColor = theme.ink(0.09)
        glass.strokeColor = theme.ink(0.55)
        text.fontSize = theme.size(14)
        text.font = theme.font(14)
        countText.fontSize = theme.size(12)
        countText.font = theme.font(12)
        countText.foregroundColor = theme.ink(0.45)
        for layer in [self, glass, text, countText] { layer.contentsScale = scale }
        let middle = Self.height / 2
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: 16, y: middle - 3, width: 10, height: 10))
        path.move(to: CGPoint(x: 25, y: middle - 2))
        path.addLine(to: CGPoint(x: 30, y: middle - 7))
        glass.path = path
    }

    func update(query: String, count: Int) {
        let width = bounds.width
        let counted = "\(count) window\(count == 1 ? "" : "s")"
        countText.string = counted
        countText.frame = CGRect(x: width - 18 - 110, y: (Self.height - 15) / 2, width: 110, height: 15)
        text.string = query.isEmpty ? "Type to search…" : query
        text.foregroundColor = theme.ink(query.isEmpty ? 0.42 : 0.95)
        text.frame = CGRect(x: 40, y: (Self.height - 17) / 2, width: max(0, width - 40 - 140), height: 17)
        borderColor = query.isEmpty ? theme.ink(0.12) : accent.copy(alpha: 0.7)
    }
}

/// One workspace: a small copy of its screen with a name above it. Its windows are cards on top of it.
private final class SlotLayer: CALayer {
    let info: OverviewOverlay.RowInfo
    private let accent: CGColor
    private let theme: Theme
    private let label = CATextLayer()
    private let note = CATextLayer()
    private let edge = CAShapeLayer()
    private var outlines: [CAShapeLayer] = []
    private let scale: CGFloat

    /// A card is dragged over this slot.
    var isDropTarget = false { didSet { if oldValue != isDropTarget { applyState() } } }

    init(info: OverviewOverlay.RowInfo, theme: Theme, accent: CGColor, scale: CGFloat) {
        self.info = info
        self.theme = theme
        self.accent = accent
        self.scale = scale
        super.init()
        contentsScale = scale
        cornerRadius = theme.cornerRadius
        for layer in [label, note, edge] { layer.contentsScale = scale }
        label.truncationMode = .end
        label.alignmentMode = .left
        note.alignmentMode = .center
        note.fontSize = theme.size(12)
        note.font = theme.font(12, .medium)
        note.foregroundColor = theme.ink(0.4)
        edge.fillColor = nil
        edge.strokeColor = theme.ink(0.25)
        edge.lineWidth = 1.2
        edge.lineDashPattern = [6, 5]
        addSublayer(label)
        addSublayer(note)
        addSublayer(edge)
        applyState()
    }

    override init(layer: Any) {
        let other = layer as! SlotLayer
        info = other.info
        accent = other.accent
        theme = other.theme
        scale = other.scale
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// `viewports` are the on-screen parts of the layout, relative to the top left corner of the slot.
    func relayout(viewports: [CGRect]) {
        let size = bounds.size
        let name: String = info.isNew ? "New workspace" : info.name
        let text = NSMutableAttributedString()
        if info.isCurrent {
            text.append(NSAttributedString(string: "● ", attributes: [.font: theme.font(10), .foregroundColor: NSColor(cgColor: accent) ?? .systemBlue]))
        }
        text.append(NSAttributedString(string: name, attributes: [.font: theme.font(15, .semibold), .foregroundColor: theme.inkColor(info.isNew ? 0.45 : 0.92)]))
        if !info.isNew {
            text.append(NSAttributedString(string: "   " + info.subtitle, attributes: [.font: theme.font(11, .medium), .foregroundColor: theme.inkColor(0.45)]))
        }
        label.string = text
        label.frame = CGRect(x: 4, y: size.height + 8, width: max(0, size.width - 8), height: 20)

        let showsNote = info.isNew || info.isEmpty
        note.isHidden = !showsNote
        note.string = info.isNew ? "Drop a window here" : "Empty"
        note.frame = CGRect(x: 0, y: (size.height - 15) / 2, width: size.width, height: 15)
        edge.isHidden = !showsNote
        edge.frame = bounds
        edge.path = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: theme.cornerRadius, cornerHeight: theme.cornerRadius, transform: nil)

        for outline in outlines { outline.removeFromSuperlayer() }
        outlines = viewports.map { viewport in
            let outline = CAShapeLayer()
            outline.contentsScale = scale
            outline.fillColor = nil
            outline.strokeColor = accent.copy(alpha: 0.55)
            outline.lineWidth = 1.2
            outline.lineDashPattern = [5, 4]
            // The viewport is measured from the top of the slot; the layer from the bottom.
            let rect = CGRect(x: viewport.minX, y: size.height - viewport.maxY, width: viewport.width, height: viewport.height)
            outline.frame = bounds
            outline.path = CGPath(roundedRect: rect.insetBy(dx: -3, dy: -3), cornerWidth: 11, cornerHeight: 11, transform: nil)
            addSublayer(outline)
            return outline
        }
        applyState()
    }

    /// The outlines of the on-screen parts move with the cards of a strip that was panned.
    func pan(by dx: CGFloat) {
        for outline in outlines { outline.frame.origin.x += dx }
    }

    private func applyState() {
        let isNew = info.isNew
        backgroundColor = theme.ink(isDropTarget ? 0.13 : info.isCurrent ? 0.075 : isNew ? 0.02 : 0.05)
        if isDropTarget {
            borderColor = accent.copy(alpha: 0.95)
            borderWidth = 2
        } else {
            borderColor = info.isCurrent ? accent.copy(alpha: 0.4) : theme.ink(0.08)
            borderWidth = info.isCurrent ? 1.5 : 1
        }
    }
}
