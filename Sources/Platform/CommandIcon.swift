import AppKit
import Core

/// The pictures of the palette commands: a small window with the action drawn inside it. Drawn once, then cached.
@MainActor
public enum CommandIcon {
    private static var cache: [String: NSImage] = [:]
    private static let size = NSSize(width: 22, height: 22)

    public static func image(_ glyph: CommandGlyph) -> NSImage {
        let key = "\(glyph)"
        if let hit = cache[key] { return hit }
        let image = NSImage(size: size, flipped: false) { _ in
            draw(glyph)
            return true
        }
        image.isTemplate = false
        cache[key] = image
        return image
    }

    // MARK: - Drawing

    private static let accent = NSColor(srgbRed: 0.35, green: 0.62, blue: 1.0, alpha: 1)
    private static let frame = NSColor(white: 0.62, alpha: 1)
    private static let body = NSColor(white: 0.22, alpha: 1)
    private static let bar = NSColor(white: 0.34, alpha: 1)
    private static let danger = NSColor(srgbRed: 1.0, green: 0.38, blue: 0.35, alpha: 1)

    /// The window. `inner` is the area under the title bar, where the action is drawn.
    private static let window = NSRect(x: 1.5, y: 3, width: 19, height: 16)
    private static let inner = NSRect(x: 3, y: 4.5, width: 16, height: 10)

    private static func draw(_ glyph: CommandGlyph) {
        switch glyph {
        case .daemon:
            chrome(NSRect(x: 1.5, y: 3, width: 19, height: 16))
            fill(NSRect(x: 5, y: 6, width: 4, height: 4), accent, radius: 2)
            fill(NSRect(x: 11, y: 7, width: 6, height: 2), frame, radius: 1)
        case .overview:
            chrome(window)
            for (column, row) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                fill(NSRect(x: 4 + CGFloat(column) * 7.5, y: 5 + CGFloat(row) * 5, width: 6.5, height: 4), accent.withAlphaComponent(row == 0 && column == 0 ? 1 : 0.55), radius: 1)
            }
        case .switcher:
            chrome(window)
            fill(NSRect(x: 4, y: 6, width: 5, height: 6), frame.withAlphaComponent(0.5), radius: 1)
            fill(NSRect(x: 9, y: 6, width: 5, height: 6), accent, radius: 1)
            fill(NSRect(x: 14, y: 6, width: 3, height: 6), frame.withAlphaComponent(0.5), radius: 1)
        default:
            chrome(window)
            action(glyph)
        }
    }

    /// The window outline: rounded body, title bar and three dots.
    private static func chrome(_ rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        body.setFill()
        path.fill()
        frame.setStroke()
        path.lineWidth = 1
        path.stroke()
        let titleBar = NSRect(x: rect.minX + 0.5, y: rect.maxY - 4, width: rect.width - 1, height: 3.5)
        bar.setFill()
        NSBezierPath(roundedRect: titleBar, xRadius: 2, yRadius: 2).fill()
        for index in 0..<3 {
            let color = index == 0 ? danger : frame
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 2.2 + CGFloat(index) * 2.6, y: rect.maxY - 3.0, width: 1.6, height: 1.6)).fill()
        }
    }

    private static func fill(_ rect: NSRect, _ color: NSColor, radius: CGFloat = 1) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    private static func stroke(_ path: NSBezierPath, _ color: NSColor, width: CGFloat = 1.4) {
        color.setStroke()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    /// A line with an arrow head, from `from` to `to`.
    private static func arrow(from: NSPoint, to: NSPoint, _ color: NSColor) {
        let path = NSBezierPath()
        path.move(to: from)
        path.line(to: to)
        let angle = atan2(to.y - from.y, to.x - from.x)
        for turn in [CGFloat.pi * 0.8, -CGFloat.pi * 0.8] {
            path.move(to: to)
            path.line(to: NSPoint(x: to.x + 3.2 * cos(angle + turn), y: to.y + 3.2 * sin(angle + turn)))
        }
        stroke(path, color)
    }

    private static func vector(_ direction: Direction) -> (dx: CGFloat, dy: CGFloat) {
        switch direction {
        case .left: (-1, 0)
        case .right: (1, 0)
        case .up: (0, 1)
        case .down: (0, -1)
        }
    }

    /// Two panes side by side or stacked; the one that `direction` points to is the accent.
    private static func panes(_ direction: Direction, accentPane: Bool = true) {
        let v = vector(direction)
        let horizontal = v.dx != 0
        let first = horizontal ? NSRect(x: inner.minX, y: inner.minY, width: 7.5, height: inner.height) : NSRect(x: inner.minX, y: inner.minY + 5.5, width: inner.width, height: 4.5)
        let second = horizontal ? NSRect(x: inner.maxX - 7.5, y: inner.minY, width: 7.5, height: inner.height) : NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: 4.5)
        let target = (v.dx > 0 || v.dy < 0) ? second : first
        let other = target == first ? second : first
        fill(other, frame.withAlphaComponent(0.45), radius: 1.5)
        fill(target, accentPane ? accent : frame, radius: 1.5)
    }

    private static func action(_ glyph: CommandGlyph) {
        let mid = NSPoint(x: inner.midX, y: inner.midY)
        switch glyph {
        case let .focus(direction):
            panes(direction)
        case .focusBack:
            fill(NSRect(x: 4, y: 5.5, width: 6.5, height: 8), frame.withAlphaComponent(0.45), radius: 1.5)
            fill(NSRect(x: 11.5, y: 5.5, width: 6.5, height: 8), accent, radius: 1.5)
            arrow(from: NSPoint(x: 16, y: 9.5), to: NSPoint(x: 7, y: 9.5), .white)
        case let .move(direction):
            panes(direction, accentPane: false)
            let v = vector(direction)
            arrow(from: NSPoint(x: mid.x - v.dx * 4, y: mid.y - v.dy * 3), to: NSPoint(x: mid.x + v.dx * 5, y: mid.y + v.dy * 4), accent)
        case .swap:
            fill(NSRect(x: 4, y: 5.5, width: 6.5, height: 8), accent, radius: 1.5)
            fill(NSRect(x: 11.5, y: 5.5, width: 6.5, height: 8), frame.withAlphaComponent(0.6), radius: 1.5)
            arrow(from: NSPoint(x: 6.5, y: 15.5), to: NSPoint(x: 15.5, y: 15.5), .white)
        case .resize:
            fill(NSRect(x: 4, y: 5.5, width: 9, height: 7), accent.withAlphaComponent(0.55), radius: 1.5)
            arrow(from: NSPoint(x: 9, y: 8), to: NSPoint(x: 17, y: 14.5), .white)
        case .close:
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 7, y: 6.5)); path.line(to: NSPoint(x: 15, y: 13))
            path.move(to: NSPoint(x: 15, y: 6.5)); path.line(to: NSPoint(x: 7, y: 13))
            stroke(path, danger, width: 1.8)
        case .float:
            fill(NSRect(x: 4, y: 5, width: 14, height: 9), frame.withAlphaComponent(0.35), radius: 1.5)
            let lifted = NSRect(x: 8, y: 6.5, width: 9, height: 7)
            fill(lifted, accent, radius: 1.5)
            NSColor.white.withAlphaComponent(0.8).setStroke()
            let outline = NSBezierPath(roundedRect: lifted, xRadius: 1.5, yRadius: 1.5)
            outline.lineWidth = 0.8
            outline.stroke()
        case .fullscreen, .nativeFullscreen:
            fill(NSRect(x: 2, y: 3.5, width: 18, height: 12.5), accent, radius: 2)
            if glyph == .nativeFullscreen { fill(NSRect(x: 8, y: 8, width: 6, height: 4), body, radius: 1) }
        case .maximize:
            fill(inner.insetBy(dx: 0.5, dy: 0), accent, radius: 1.5)
            NSColor.white.withAlphaComponent(0.85).setStroke()
            let ring = NSBezierPath(roundedRect: inner.insetBy(dx: 2.5, dy: 2), xRadius: 1, yRadius: 1)
            ring.lineWidth = 0.8
            ring.stroke()
        case .mark:
            fill(NSRect(x: 4, y: 5.5, width: 14, height: 8), frame.withAlphaComponent(0.35), radius: 1.5)
            let flag = NSBezierPath()
            flag.move(to: NSPoint(x: 8, y: 6)); flag.line(to: NSPoint(x: 8, y: 14))
            flag.line(to: NSPoint(x: 15, y: 12)); flag.line(to: NSPoint(x: 8, y: 10))
            stroke(flag, accent, width: 1.5)
        case .sendWorkspace:
            fill(NSRect(x: 4, y: 5.5, width: 6, height: 8), frame.withAlphaComponent(0.45), radius: 1.5)
            fill(NSRect(x: 12, y: 5.5, width: 6, height: 8), accent.withAlphaComponent(0.4), radius: 1.5)
            arrow(from: NSPoint(x: 6, y: 9.5), to: NSPoint(x: 16, y: 9.5), .white)
        case .sendMonitor:
            fill(NSRect(x: 3.5, y: 6, width: 6, height: 7), frame.withAlphaComponent(0.6), radius: 1)
            fill(NSRect(x: 12.5, y: 6, width: 6, height: 7), accent, radius: 1)
            arrow(from: NSPoint(x: 7, y: 9.5), to: NSPoint(x: 14.5, y: 9.5), .white)
        case .workspace:
            for index in 0..<3 {
                fill(NSRect(x: 4 + CGFloat(index) * 5.2, y: 6.5, width: 4, height: 6), index == 1 ? accent : frame.withAlphaComponent(0.5), radius: 1)
            }
        case .special:
            fill(NSRect(x: 4, y: 5.5, width: 14, height: 8), frame.withAlphaComponent(0.35), radius: 1.5)
            let star = NSBezierPath()
            for index in 0..<10 {
                let radius: CGFloat = index.isMultiple(of: 2) ? 4.2 : 1.8
                let angle = CGFloat.pi / 2 + CGFloat(index) * .pi / 5
                let point = NSPoint(x: mid.x + radius * cos(angle), y: mid.y + radius * sin(angle))
                index == 0 ? star.move(to: point) : star.line(to: point)
            }
            star.close()
            accent.setFill()
            star.fill()
        case .layoutTiling:
            fill(NSRect(x: 4, y: 5.5, width: 6.5, height: 8), accent, radius: 1.5)
            fill(NSRect(x: 11.5, y: 9.5, width: 6.5, height: 4), frame.withAlphaComponent(0.6), radius: 1.5)
            fill(NSRect(x: 11.5, y: 5.5, width: 6.5, height: 3.2), frame.withAlphaComponent(0.6), radius: 1.5)
        case .layoutMaster:
            fill(NSRect(x: 4, y: 5.5, width: 8, height: 8), accent, radius: 1.5)
            fill(NSRect(x: 13, y: 9.5, width: 5, height: 4), frame.withAlphaComponent(0.6), radius: 1.5)
            fill(NSRect(x: 13, y: 5.5, width: 5, height: 3.2), frame.withAlphaComponent(0.6), radius: 1.5)
        case .layoutScrolling:
            fill(NSRect(x: 3.5, y: 5.5, width: 4.5, height: 8), frame.withAlphaComponent(0.5), radius: 1)
            fill(NSRect(x: 8.5, y: 5.5, width: 6, height: 8), accent, radius: 1)
            fill(NSRect(x: 15.2, y: 5.5, width: 3.3, height: 8), frame.withAlphaComponent(0.5), radius: 1)
        case .balance:
            for index in 0..<3 {
                fill(NSRect(x: 4 + CGFloat(index) * 5.2, y: 5.5, width: 4, height: 8), accent.withAlphaComponent(0.75), radius: 1)
            }
        case .rotate:
            let arc = NSBezierPath()
            arc.appendArc(withCenter: mid, radius: 4.5, startAngle: 40, endAngle: 330, clockwise: false)
            stroke(arc, accent, width: 1.6)
            arrow(from: NSPoint(x: mid.x + 4.2, y: mid.y + 2.2), to: NSPoint(x: mid.x + 4.6, y: mid.y - 0.2), accent)
        case .flip:
            fill(NSRect(x: 4, y: 5.5, width: 6.5, height: 8), frame.withAlphaComponent(0.45), radius: 1.5)
            fill(NSRect(x: 11.5, y: 5.5, width: 6.5, height: 8), accent, radius: 1.5)
            arrow(from: NSPoint(x: 6, y: 15.8), to: NSPoint(x: 16, y: 15.8), .white)
        case .split:
            fill(NSRect(x: 4, y: 5.5, width: 6.5, height: 8), frame.withAlphaComponent(0.6), radius: 1.5)
            fill(NSRect(x: 11.5, y: 5.5, width: 6.5, height: 8), accent, radius: 1.5)
        case .column:
            fill(NSRect(x: 4, y: 5.5, width: 3.5, height: 8), frame.withAlphaComponent(0.5), radius: 1)
            fill(NSRect(x: 8.5, y: 5.5, width: 5, height: 8), accent, radius: 1)
            fill(NSRect(x: 14.5, y: 5.5, width: 3.5, height: 8), frame.withAlphaComponent(0.5), radius: 1)
        case .stack:
            fill(NSRect(x: 4, y: 10.8, width: 14, height: 2.7), frame.withAlphaComponent(0.6), radius: 1)
            fill(NSRect(x: 4, y: 7.6, width: 14, height: 2.7), accent, radius: 1)
            fill(NSRect(x: 4, y: 4.6, width: 14, height: 2.4), frame.withAlphaComponent(0.6), radius: 1)
        case .preselect:
            fill(NSRect(x: 4, y: 5.5, width: 6.5, height: 8), frame.withAlphaComponent(0.6), radius: 1.5)
            accent.setStroke()
            let dashed = NSBezierPath(roundedRect: NSRect(x: 11.5, y: 5.5, width: 6.5, height: 8), xRadius: 1.5, yRadius: 1.5)
            dashed.setLineDash([1.6, 1.6], count: 2, phase: 0)
            dashed.lineWidth = 1.2
            dashed.stroke()
        case .pointer:
            let cursor = NSBezierPath()
            cursor.move(to: NSPoint(x: 8, y: 14)); cursor.line(to: NSPoint(x: 8, y: 6))
            cursor.line(to: NSPoint(x: 10.2, y: 8.2)); cursor.line(to: NSPoint(x: 12, y: 5))
            cursor.line(to: NSPoint(x: 13.2, y: 5.8)); cursor.line(to: NSPoint(x: 11.4, y: 9))
            cursor.line(to: NSPoint(x: 14.2, y: 9)); cursor.close()
            NSColor.white.setFill()
            cursor.fill()
        case .mode:
            for index in 0..<3 {
                let y = 6.5 + CGFloat(index) * 3.2
                fill(NSRect(x: 4, y: y, width: 14, height: 1.4), frame.withAlphaComponent(0.6), radius: 0.7)
                fill(NSRect(x: 5 + CGFloat((index * 5) % 9), y: y - 0.9, width: 3.2, height: 3.2), accent, radius: 1.6)
            }
        case .notify:
            fill(NSRect(x: 4, y: 7, width: 14, height: 6), accent, radius: 2)
            fill(NSRect(x: 6, y: 9.6, width: 8, height: 1.2), .white, radius: 0.6)
        case .overview, .switcher, .daemon, .generic:
            fill(NSRect(x: 4, y: 7, width: 14, height: 1.6), frame.withAlphaComponent(0.7), radius: 0.8)
            fill(NSRect(x: 4, y: 10.4, width: 9, height: 1.6), accent, radius: 0.8)
        }
    }
}
