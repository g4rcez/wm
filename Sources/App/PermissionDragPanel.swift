import AppKit

/// A small floating panel with the wm icon. The user drags it into the list of System Settings > Privacy & Security, which
/// grants the permission without the `+` button and the file picker. It closes by itself once the permission is granted.
@MainActor
final class PermissionDragPanel {
    private var panel: NSPanel?
    private var timer: Timer?

    /// Shows the panel for `permission` ("Accessibility", "Screen Recording") until `granted` says yes.
    func show(permission: String, granted: @escaping @MainActor () -> Bool) {
        close()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 92),
            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Add wm to \(permission)"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let icon = DraggableAppIcon(bundleURL: Bundle.main.bundleURL)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 56).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 56).isActive = true
        let text = NSTextField(wrappingLabelWithString: "Drag this icon into the \(permission) list in System Settings, then switch wm on.")
        text.preferredMaxLayoutWidth = 250
        let row = NSStackView(views: [icon, text])
        row.spacing = 14
        row.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        panel.contentView = row
        panel.setContentSize(row.fittingSize)

        // The bottom centre of the main screen: System Settings opens above it.
        if let frame = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 24))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if granted() { self?.close() } }
        }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        panel?.close()
        panel = nil
    }
}

/// The icon of an app that can be dragged out as a file: System Settings takes the dropped app into its list.
private final class DraggableAppIcon: NSImageView, NSDraggingSource {
    private let bundleURL: URL

    init(bundleURL: URL) {
        self.bundleURL = bundleURL
        super.init(frame: .zero)
        image = NSWorkspace.shared.icon(forFile: bundleURL.path)
        imageScaling = .scaleProportionallyUpOrDown
        toolTip = "Drag me into the list"
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: bundleURL as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}
