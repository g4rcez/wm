import CoreGraphics

public struct MonitorFrame: Sendable, Equatable {
    public var id: UInt32
    public var frame: CGRect

    public init(id: UInt32, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

/// Multi-monitor decisions as pure functions. Rectangles use Accessibility coordinates (origin top-left).
public enum MonitorGeometry {
    /// The monitor next to `current` in `direction`: its centre lies on that side, it overlaps `current` on the other
    /// axis (a monitor above the laptop is not "left" of it), and it is the nearest such one.
    public static func adjacent(to current: UInt32, _ direction: Direction, in monitors: [MonitorFrame]) -> UInt32? {
        guard let from = monitors.first(where: { $0.id == current }) else { return nil }
        let center = CGPoint(x: from.frame.midX, y: from.frame.midY)
        let verticalOverlap = { (other: CGRect) in other.maxY > from.frame.minY && other.minY < from.frame.maxY }
        let horizontalOverlap = { (other: CGRect) in other.maxX > from.frame.minX && other.minX < from.frame.maxX }
        return monitors
            .filter { $0.id != current }
            .filter { other in
                switch direction {
                case .left: other.frame.midX < center.x && verticalOverlap(other.frame)
                case .right: other.frame.midX > center.x && verticalOverlap(other.frame)
                case .up: other.frame.midY < center.y && horizontalOverlap(other.frame)
                case .down: other.frame.midY > center.y && horizontalOverlap(other.frame)
                }
            }
            .min { distance($0, center) < distance($1, center) }?.id
    }

    /// The monitor `step` places after `current` in left-to-right order; wraps around.
    public static func cycle(from current: UInt32, step: Int, in monitors: [MonitorFrame]) -> UInt32? {
        let ordered = monitors.sorted { ($0.frame.minX, $0.frame.minY, $0.id) < ($1.frame.minX, $1.frame.minY, $1.id) }
        guard let index = ordered.firstIndex(where: { $0.id == current }), ordered.count > 1 else { return nil }
        return ordered[((index + step) % ordered.count + ordered.count) % ordered.count].id
    }

    public static func monitor(containing point: CGPoint, in monitors: [MonitorFrame]) -> UInt32? {
        monitors.first { $0.frame.contains(point) }?.id
    }

    /// Where windows of hidden workspaces are parked: one pixel inside the bottom-right corner of all monitors together.
    public static func hiddenCorner(of monitors: [CGRect]) -> CGPoint {
        let right = monitors.map(\.maxX).max() ?? 0
        let bottom = monitors.map(\.maxY).max() ?? 0
        return CGPoint(x: right - 1, y: bottom - 1)
    }

    /// `frame` moved the shortest way into `area`. A frame that is larger than the area lines up with its top-left corner.
    public static func clamped(_ frame: CGRect, in area: CGRect) -> CGRect {
        CGRect(
            x: min(max(frame.minX, area.minX), max(area.minX, area.maxX - frame.width)),
            y: min(max(frame.minY, area.minY), max(area.minY, area.maxY - frame.height)),
            width: frame.width, height: frame.height)
    }

    /// `frame` as a floating window on `area`: where it is when its centre shows in the area, else moved the shortest way
    /// into it. It is never larger than the area. A layout gives a window that it hides (monocle, a column scrolled away)
    /// a frame off the screen: floated there, the window could not be found again.
    public static func floatable(_ frame: CGRect, in area: CGRect) -> CGRect {
        guard !area.isEmpty else { return frame }
        let size = CGSize(width: min(frame.width, area.width), height: min(frame.height, area.height))
        if area.contains(CGPoint(x: frame.midX, y: frame.midY)), frame.width <= area.width, frame.height <= area.height {
            return frame
        }
        return clamped(CGRect(origin: frame.origin, size: size), in: area)
    }

    /// The edges of `frame` that a drag starting at `point` takes hold of: the side of the centre that the point is on.
    public static func nearestEdges(of frame: CGRect, to point: CGPoint) -> (horizontal: Direction, vertical: Direction) {
        (point.x < frame.midX ? .left : .right, point.y < frame.midY ? .up : .down)
    }

    /// `frame` with its two edges moved by `delta` (the pointer's movement). The size never goes below `minimum`; the
    /// edge that is not dragged stays where it is.
    public static func resized(_ frame: CGRect, edges: (horizontal: Direction, vertical: Direction), by delta: CGPoint, minimum: CGSize) -> CGRect {
        var result = frame
        if edges.horizontal == .right {
            result.size.width = max(frame.width + delta.x, minimum.width)
        } else {
            let width = max(frame.width - delta.x, minimum.width)
            result.origin.x = frame.maxX - width
            result.size.width = width
        }
        if edges.vertical == .down {
            result.size.height = max(frame.height + delta.y, minimum.height)
        } else {
            let height = max(frame.height - delta.y, minimum.height)
            result.origin.y = frame.maxY - height
            result.size.height = height
        }
        return result
    }

    /// A window moves with its workspace to another monitor: it keeps its size (cut down to the new area) and its relative
    /// place, so a window in the middle of one area stays in the middle of the other.
    public static func translated(_ frame: CGRect, from old: CGRect, to new: CGRect) -> CGRect {
        guard old.width > 0, old.height > 0 else { return clamped(frame, in: new) }
        let size = CGSize(width: min(frame.width, new.width), height: min(frame.height, new.height))
        let origin = CGPoint(
            x: new.minX + (frame.minX - old.minX) / old.width * new.width,
            y: new.minY + (frame.minY - old.minY) / old.height * new.height)
        return clamped(CGRect(origin: origin, size: size), in: new)
    }

    /// Where a floating window that is mostly outside `area` should go: cut down to the size of the area when it is larger,
    /// then moved inside. `nil` when at least half of the window is inside already.
    public static func rescued(_ frame: CGRect, in area: CGRect) -> CGRect? {
        let visible = frame.intersection(area)
        if !visible.isNull, visible.width * visible.height * 2 >= frame.width * frame.height { return nil }
        let fitted = CGRect(origin: frame.origin, size: CGSize(width: min(frame.width, area.width), height: min(frame.height, area.height)))
        return clamped(fitted, in: area)
    }

    private static func distance(_ monitor: MonitorFrame, _ point: CGPoint) -> CGFloat {
        hypot(monitor.frame.midX - point.x, monitor.frame.midY - point.y)
    }
}
