import AppKit

/// The floating panel of one picture. Drag it to move it, click it for its window, right-click it to close it.
@MainActor
public final class PipPanel {
    private let panel = Panel()
    private let view = PipView()

    /// `dragged` gets the middle of the panel, in Accessibility coordinates.
    public init(clicked: @escaping () -> Void, dragged: @escaping (CGPoint) -> Void, closed: @escaping () -> Void) {
        view.clicked = clicked
        view.closed = closed
        view.dragged = { [weak panel] in
            guard let frame = panel?.frame else { return }
            // The flip between the two coordinate spaces is its own inverse.
            let flipped = Displays.cocoaRect(frame)
            dragged(CGPoint(x: flipped.midX, y: flipped.midY))
        }
        panel.contentView = view
    }

    public var scale: CGFloat { panel.backingScaleFactor }

    public func show(at frame: CGRect) {
        if !view.isDragging { panel.setFrame(Displays.cocoaRect(frame), display: true) }
        panel.orderFrontRegardless()
    }

    public func hide() { panel.orderOut(nil) }

    public func draw(_ surface: IOSurface) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.layer?.contents = surface
        CATransaction.commit()
    }
}

/// Never key, never main: the app that the user works in keeps focus.
private final class Panel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class PipView: NSView {
    var clicked: () -> Void = {}
    var dragged: () -> Void = {}
    var closed: () -> Void = {}
    private(set) var isDragging = false
    private var start: (pointer: NSPoint, origin: NSPoint)?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = CGColor(gray: 0, alpha: 1)
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = CGColor(gray: 0.5, alpha: 0.5)
        layer?.contentsGravity = .resizeAspect
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        start = (NSEvent.mouseLocation, window.frame.origin)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let start else { return }
        let now = NSEvent.mouseLocation
        let delta = NSPoint(x: now.x - start.pointer.x, y: now.y - start.pointer.y)
        if !isDragging, hypot(delta.x, delta.y) < 4 { return }
        isDragging = true
        window.setFrameOrigin(NSPoint(x: start.origin.x + delta.x, y: start.origin.y + delta.y))
    }

    override func mouseUp(with event: NSEvent) {
        let moved = isDragging
        start = nil
        isDragging = false
        if moved { dragged() } else { clicked() }
    }

    override func rightMouseUp(with event: NSEvent) { closed() }
}
