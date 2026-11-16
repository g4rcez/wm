import AppKit

/// The menu bar icons: the workspace name cut out of a filled rounded square, and the name of an active binding mode
/// inside an outlined one.
public enum WorkspaceIcon {
    /// A template image, so macOS tints it for light and dark menu bars. Names are cut to three characters.
    @MainActor
    public static func image(for name: String) -> NSImage { make(name, outlined: false) }

    /// Same size as the workspace icon, but outlined with the name drawn inside, so a mode is seen at a glance.
    @MainActor
    public static func modeImage(for name: String) -> NSImage { make(name, outlined: true) }

    @MainActor
    private static func make(_ name: String, outlined: Bool) -> NSImage {
        let label = String(name.prefix(3))
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4.5, yRadius: 4.5)
            NSColor.black.setFill()
            NSColor.black.setStroke()
            if outlined {
                shape.lineWidth = 1.5
                shape.stroke()
            } else {
                shape.fill()
            }
            // Start large for short names and shrink until the text fits inside the square.
            var fontSize: CGFloat = label.count == 1 ? 12.5 : 10.5
            func attributed(_ size: CGFloat) -> NSAttributedString {
                NSAttributedString(string: label, attributes: [
                    .font: NSFont.systemFont(ofSize: size, weight: .heavy),
                    .foregroundColor: NSColor.black,
                ])
            }
            while attributed(fontSize).size().width > rect.width - 6, fontSize > 5 { fontSize -= 0.5 }
            let text = attributed(fontSize)
            let size = text.size()
            if !outlined { NSGraphicsContext.current?.compositingOperation = .destinationOut }
            text.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2))
            return true
        }
        image.isTemplate = true
        return image
    }
}
