import CoreGraphics

/// Moving and resizing a floating window by keyboard. The window stays inside `area`, the work area of its monitor.
public enum FloatGeometry {
    /// The smallest side that a resize leaves (less when the area itself is smaller).
    public static let minimumSize: CGFloat = 100

    /// The frame `step` points further in `direction`. At the edge of the area it stops.
    public static func moved(_ frame: CGRect, _ direction: Direction, by step: CGFloat, in area: CGRect) -> CGRect {
        var origin = frame.origin
        switch direction {
        case .left: origin.x -= step
        case .right: origin.x += step
        case .up: origin.y -= step
        case .down: origin.y += step
        }
        return inside(CGRect(origin: origin, size: frame.size), area)
    }

    /// The frame with `delta` points more (or less) in one dimension. The top left corner stays, unless the window would leave the
    /// area. `smart` is the width: a floating window has no split direction.
    public static func resized(_ frame: CGRect, _ dimension: ResizeDimension, by delta: CGFloat, in area: CGRect) -> CGRect {
        var size = frame.size
        switch dimension {
        case .width, .smart: size.width = min(max(size.width + delta, min(minimumSize, area.width)), area.width)
        case .height: size.height = min(max(size.height + delta, min(minimumSize, area.height)), area.height)
        }
        return inside(CGRect(origin: frame.origin, size: size), area)
    }

    /// The frame with the same size in the middle of the area.
    public static func centered(_ frame: CGRect, in area: CGRect) -> CGRect {
        inside(CGRect(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2, width: frame.width, height: frame.height), area)
    }

    /// The frame moved the least that puts it in the area. A side that is longer than the area sits at its start.
    private static func inside(_ frame: CGRect, _ area: CGRect) -> CGRect {
        let x = frame.width >= area.width ? area.minX : min(max(frame.minX, area.minX), area.maxX - frame.width)
        let y = frame.height >= area.height ? area.minY : min(max(frame.minY, area.minY), area.maxY - frame.height)
        return CGRect(x: x, y: y, width: frame.width, height: frame.height)
    }
}
