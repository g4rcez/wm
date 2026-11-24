import AppKit
import Core

/// The menu bar icons that are pictures: a name cut out of a filled rounded square (`...` while a key sequence waits), and the
/// name of an active binding mode inside an outlined one. The workspaces (`T:1 2 5`) are one picture too (`strip`); see `StatusLabel`.
public enum WorkspaceIcon {
    /// A template image, so macOS tints it for light and dark menu bars. Names are cut to three characters.
    @MainActor
    public static func image(for name: String) -> NSImage { make(name, outlined: false) }

    /// Same size as the workspace icon, but outlined with the name drawn inside, so a mode is seen at a glance.
    @MainActor
    public static func modeImage(for name: String) -> NSImage { make(name, outlined: true) }

    /// The state of the workspaces as one picture: plain text, and the piece of the workspace in focus on a filled rounded
    /// background with the text cut out of it. A template image, so macOS tints it for light and dark menu bars.
    @MainActor
    public static func strip(_ segments: [StatusSegment]) -> NSImage {
        let padding: CGFloat = 5
        func attributed(_ text: String) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.black,
            ])
        }
        let widths = segments.map { ceil(attributed($0.text).size().width) + ($0.isCurrent ? padding * 2 : 0) }
        let image = NSImage(size: NSSize(width: max(widths.reduce(0, +), 1), height: 18), flipped: false) { rect in
            var x: CGFloat = 0
            for (segment, width) in zip(segments, widths) {
                let text = attributed(segment.text)
                let size = text.size()
                let origin = NSPoint(x: x + (segment.isCurrent ? padding : 0), y: (rect.height - size.height) / 2)
                if segment.isCurrent {
                    NSColor.black.setFill()
                    NSBezierPath(roundedRect: NSRect(x: x, y: 1, width: width, height: rect.height - 2), xRadius: 4.5, yRadius: 4.5).fill()
                    NSGraphicsContext.current?.compositingOperation = .destinationOut
                    text.draw(at: origin)
                    NSGraphicsContext.current?.compositingOperation = .sourceOver
                } else {
                    text.draw(at: origin)
                }
                x += width
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// `image` with a small lock to its right (Secure Input is on). A template image, as `image` is.
    @MainActor
    public static func withLock(_ image: NSImage?) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let lock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Secure Input")?.withSymbolConfiguration(configuration)
        let lockSize = lock?.size ?? NSSize(width: 10, height: 12)
        let gap: CGFloat = image == nil ? 0 : 4
        let base = image?.size ?? .zero
        let result = NSImage(size: NSSize(width: base.width + gap + lockSize.width, height: max(base.height, 18)), flipped: false) { rect in
            image?.draw(in: NSRect(x: 0, y: (rect.height - base.height) / 2, width: base.width, height: base.height))
            if let lock {
                // Drawn in black: as a template image only its shape counts, and macOS tints it.
                lock.lockFocus()
                NSColor.black.set()
                NSRect(origin: .zero, size: lockSize).fill(using: .sourceAtop)
                lock.unlockFocus()
                lock.draw(in: NSRect(x: base.width + gap, y: (rect.height - lockSize.height) / 2, width: lockSize.width, height: lockSize.height))
            }
            return true
        }
        result.isTemplate = true
        return result
    }

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
