import AppKit
import Core

/// The small picture of a window that is dragged with the move modifier: the window itself waits out of sight, so the other
/// windows can make room for it, and the picture follows the pointer. It shows the window live (Screen Recording), else the icon of
/// its app on a rounded box. It ignores the mouse.
@MainActor
public final class DragPicture {
    /// How much of the window's size the picture has, and the largest width it takes.
    public static let scale: CGFloat = 0.35
    public static let maxWidth: CGFloat = 480
    public static let minWidth: CGFloat = 160

    private let panel: NSPanel
    private let view = NSView()
    private let iconLayer = CALayer()
    private var capture: LiveCapture?
    private var size: CGSize = .zero

    public init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        view.layer?.contentsGravity = .resizeAspect
        view.layer?.addSublayer(iconLayer)
        panel.contentView = view
    }

    /// The size of the picture of a window of `size`: smaller, with the same shape.
    public static func pictureSize(of size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: minWidth, height: minWidth * 0.66) }
        let width = min(max(size.width * scale, minWidth), maxWidth)
        return CGSize(width: width, height: width * size.height / size.width)
    }

    /// Where the picture is now, in Accessibility coordinates.
    public private(set) var frame: CGRect = .zero

    /// Shows the picture of `window` (of `windowSize`, owned by `pid`) centred on `pointer`.
    public func start(window: WindowID, windowSize: CGSize, pid: pid_t, at pointer: CGPoint, live: Bool) {
        stop()
        size = Self.pictureSize(of: windowSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.layer?.contents = nil
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        let side = min(size.width, size.height) * 0.45
        iconLayer.frame = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
        iconLayer.contents = icon
        iconLayer.contentsGravity = .resizeAspect
        iconLayer.isHidden = false
        CATransaction.commit()
        move(to: pointer)
        panel.orderFrontRegardless()
        guard live else { return }
        let capture = LiveCapture(window: window, onFrame: { [weak self] surface in self?.draw(surface) }, onStop: {})
        self.capture = capture
        let pixels = CGSize(width: size.width * panel.backingScaleFactor, height: size.height * panel.backingScaleFactor)
        Task { @MainActor in _ = await capture.start(pixels: pixels, fps: 30) }
    }

    public func move(to pointer: CGPoint) {
        frame = CGRect(x: pointer.x - size.width / 2, y: pointer.y - size.height / 2, width: size.width, height: size.height)
        panel.setFrame(Displays.cocoaRect(frame), display: true)
    }

    public func stop() {
        capture?.stop()
        capture = nil
        panel.orderOut(nil)
    }

    private func draw(_ surface: IOSurface) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        iconLayer.isHidden = true
        view.layer?.contents = surface
        CATransaction.commit()
    }
}
