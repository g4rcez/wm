import AppKit
import Core

/// One window as a card: its picture (or its app icon), a bar with the icon and the title, a ring for the selection, a dashed
/// line when the window floats and a close button under the pointer. The overlays draw with it, so the cards look the same.
/// Its coordinates are the plain ones of Core Animation (the origin at the bottom left); the owner sets `frame` and calls
/// `relayout()`, with implicit animations off.
final class WindowCardLayer: CALayer {
    let windowID: WindowID
    private(set) var title: String
    private(set) var appName: String
    private(set) var icon: NSImage?
    private(set) var isFloating: Bool
    private let accent: CGColor
    private let theme: Theme
    private let scale: CGFloat
    private let clip = CALayer()
    private let picture = CALayer()
    private let iconLayer = CALayer()
    private let footer = CALayer()
    private let footerIcon = CALayer()
    private let footerText = CATextLayer()
    private let dim = CALayer()
    private let ring = CALayer()
    private let dash = CAShapeLayer()
    private let closeButton = CAShapeLayer()
    private var hasPicture = false

    var isSelected = false { didSet { if oldValue != isSelected { applyState() } } }
    var isHovered = false { didSet { if oldValue != isHovered { applyState() } } }
    var isDimmed = false { didSet { if oldValue != isDimmed { applyState() } } }

    init(id: WindowID, title: String, appName: String, icon: NSImage?, image: CGImage?, isFloating: Bool, theme: Theme, accent: CGColor, scale: CGFloat) {
        windowID = id
        self.title = title
        self.appName = appName
        self.icon = icon
        self.isFloating = isFloating
        self.theme = theme
        self.accent = accent
        self.scale = scale
        super.init()
        contentsScale = scale
        shadowColor = CGColor(gray: 0, alpha: 1)
        shadowOpacity = 0.45
        shadowRadius = 7
        shadowOffset = .zero

        clip.masksToBounds = true
        clip.backgroundColor = theme.isDark ? CGColor(gray: 0.13, alpha: 1) : CGColor(gray: 0.9, alpha: 1)
        addSublayer(clip)
        // The picture fills the whole card; what does not fit is cut off, so no empty bands show.
        picture.contentsGravity = .resizeAspectFill
        iconLayer.contentsGravity = .resizeAspect
        footer.backgroundColor = CGColor(gray: 0, alpha: 0.58)
        footerIcon.contentsGravity = .resizeAspect
        footerText.fontSize = theme.size(11)
        footerText.font = theme.font(11, .medium)
        footerText.foregroundColor = CGColor(gray: 1, alpha: 0.95)
        footerText.truncationMode = .end
        footerText.alignmentMode = .left
        dim.backgroundColor = CGColor(gray: 0, alpha: 0.45)
        dim.isHidden = true
        for layer in [picture, iconLayer, footer, footerIcon, footerText, dim, ring, dash, closeButton] { layer.contentsScale = scale }
        clip.addSublayer(picture)
        clip.addSublayer(iconLayer)
        clip.addSublayer(footer)
        footer.addSublayer(footerIcon)
        footer.addSublayer(footerText)
        clip.addSublayer(dim)
        addSublayer(ring)
        dash.fillColor = nil
        dash.strokeColor = theme.ink(0.55)
        dash.lineWidth = 1.2
        dash.lineDashPattern = [5, 3]
        dash.isHidden = !isFloating
        addSublayer(dash)
        closeButton.fillColor = CGColor(red: 1, green: 0.27, blue: 0.23, alpha: 1)
        closeButton.strokeColor = nil
        closeButton.isHidden = true
        addSublayer(closeButton)
        setImage(image)
        applyState()
    }

    override init(layer: Any) {
        let other = layer as! WindowCardLayer
        windowID = other.windowID
        title = other.title
        appName = other.appName
        icon = other.icon
        isFloating = other.isFloating
        accent = other.accent
        theme = other.theme
        scale = other.scale
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var radius: CGFloat { min(max(min(bounds.width, bounds.height) * 0.07, 5), max(5, theme.cornerRadius - 2)) }

    /// The close button, in the coordinates of this layer.
    static let closeSize: CGFloat = 22
    static let closeInset: CGFloat = 6

    func setImage(_ image: CGImage?) {
        hasPicture = image != nil
        picture.contents = image
        relayout()
    }

    /// Places the sublayers for the current `bounds`.
    func relayout() {
        let size = bounds.size
        let radius = self.radius
        clip.frame = bounds
        clip.cornerRadius = radius
        picture.frame = bounds
        picture.isHidden = !hasPicture
        let iconImage = icon?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let side = min(64, min(size.width, size.height) * 0.45)
        iconLayer.isHidden = hasPicture || iconImage == nil
        iconLayer.contents = iconImage
        iconLayer.frame = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2 + 8, width: side, height: side)

        let showsFooter = size.width >= 80 && size.height >= 56
        let barHeight: CGFloat = 28
        footer.isHidden = !showsFooter
        footer.frame = CGRect(x: 0, y: 0, width: size.width, height: barHeight)
        footerIcon.contents = iconImage
        footerIcon.isHidden = iconImage == nil
        footerIcon.frame = CGRect(x: 9, y: (barHeight - 16) / 2, width: 16, height: 16)
        let textX: CGFloat = iconImage == nil ? 9 : 32
        footerText.string = title.isEmpty ? appName : title
        footerText.frame = CGRect(x: textX, y: (barHeight - 14) / 2, width: max(0, size.width - textX - 8), height: 14)
        dim.frame = bounds

        ring.frame = bounds
        ring.cornerRadius = radius
        shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        dash.frame = bounds
        dash.path = CGPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), cornerWidth: radius, cornerHeight: radius, transform: nil)
        let button = Self.closeSize
        closeButton.frame = CGRect(x: size.width - button - Self.closeInset, y: size.height - button - Self.closeInset, width: button, height: button)
        let inset: CGFloat = 7
        closeButton.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: button, height: button), transform: nil)
        let mark = CGMutablePath()
        mark.move(to: CGPoint(x: inset, y: inset))
        mark.addLine(to: CGPoint(x: button - inset, y: button - inset))
        mark.move(to: CGPoint(x: button - inset, y: inset))
        mark.addLine(to: CGPoint(x: inset, y: button - inset))
        crossLayer.frame = CGRect(origin: .zero, size: CGSize(width: button, height: button))
        crossLayer.path = mark
    }

    private lazy var crossLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = nil
        layer.strokeColor = CGColor(gray: 1, alpha: 1)
        layer.lineWidth = 1.8
        layer.lineCap = .round
        closeButton.addSublayer(layer)
        return layer
    }()

    private func applyState() {
        dim.isHidden = !isDimmed
        picture.opacity = isDimmed ? 0.35 : 1
        closeButton.isHidden = !isHovered
        if isSelected {
            ring.borderWidth = 3
            ring.borderColor = accent
            ring.shadowColor = accent
            ring.shadowOpacity = 0.85
            ring.shadowRadius = 10
            ring.shadowOffset = .zero
        } else {
            ring.borderWidth = isHovered ? 1.5 : 1
            ring.borderColor = theme.ink(isHovered ? 0.4 : 0.16)
            ring.shadowOpacity = 0
        }
    }
}
