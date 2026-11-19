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
    /// area. `smart` changes both dimensions by `delta` around the centre of the window: a floating window has no split direction,
    /// so it is the bigger / smaller control.
    public static func resized(_ frame: CGRect, _ dimension: ResizeDimension, by delta: CGFloat, in area: CGRect) -> CGRect {
        var size = frame.size
        func clamped(_ length: CGFloat, _ limit: CGFloat) -> CGFloat { min(max(length, min(minimumSize, limit)), limit) }
        switch dimension {
        case .width: size.width = clamped(size.width + delta, area.width)
        case .height: size.height = clamped(size.height + delta, area.height)
        case .smart:
            size = CGSize(width: clamped(size.width + delta, area.width), height: clamped(size.height + delta, area.height))
            let origin = CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
            return inside(CGRect(origin: origin, size: size), area)
        }
        return inside(CGRect(origin: frame.origin, size: size), area)
    }

    /// The frame with the width (or the height) set to `fraction` of the area, keeping its top left corner when it fits.
    public static func sized(_ frame: CGRect, _ dimension: ResizeDimension, fraction: Double, in area: CGRect) -> CGRect {
        let length = (dimension == .height ? area.height : area.width) * CGFloat(min(max(fraction, 0.1), 1))
        return resized(frame, dimension == .height ? .height : .width, by: length - (dimension == .height ? frame.height : frame.width), in: area)
    }

    /// The next of the usual fractions (a third, a half, two thirds, the whole area) after the current size of `frame`; the first one
    /// when it is at the last or none matches.
    public static func nextFraction(of frame: CGRect, _ dimension: ResizeDimension, in area: CGRect) -> Double {
        let steps = [1.0 / 3, 1.0 / 2, 2.0 / 3, 1.0]
        let current = Double((dimension == .height ? frame.height / area.height : frame.width / area.width))
        return steps.first { $0 > current + 0.02 } ?? steps[0]
    }

    /// The frame with the same size in the middle of the area.
    public static func centered(_ frame: CGRect, in area: CGRect) -> CGRect {
        inside(CGRect(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2, width: frame.width, height: frame.height), area)
    }

    /// The frame with the same size and its top left corner at `origin`, moved the least that keeps it in the area.
    public static func placed(_ frame: CGRect, at origin: CGPoint, in area: CGRect) -> CGRect {
        inside(CGRect(origin: origin, size: frame.size), area)
    }

    /// The frame moved the least that puts it in the area. A side that is longer than the area sits at its start.
    private static func inside(_ frame: CGRect, _ area: CGRect) -> CGRect {
        let x = frame.width >= area.width ? area.minX : min(max(frame.minX, area.minX), area.maxX - frame.width)
        let y = frame.height >= area.height ? area.minY : min(max(frame.minY, area.minY), area.maxY - frame.height)
        return CGRect(x: x, y: y, width: frame.width, height: frame.height)
    }
}
