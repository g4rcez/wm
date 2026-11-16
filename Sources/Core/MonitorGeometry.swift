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

    private static func distance(_ monitor: MonitorFrame, _ point: CGPoint) -> CGFloat {
        hypot(monitor.frame.midX - point.x, monitor.frame.midY - point.y)
    }
}

/// Workspace names in native mode. A desktop is "2" (or "2.3" on the second display); its virtual rows after the
/// first are "2/2", "2/3", ...
public enum NativeWorkspaceName {
    public static func desktops(displayNumber: Int, displayCount: Int, desktopCount: Int) -> [String] {
        let prefix = displayCount > 1 ? "\(displayNumber)." : ""
        return (1...max(desktopCount, 1)).prefix(desktopCount).map { prefix + String($0) }
    }

    public static func row(of desktop: String, _ row: Int) -> String {
        row <= 1 ? desktop : "\(desktop)/\(row)"
    }

    public static func desktop(of workspace: String) -> String {
        String(workspace.split(separator: "/", maxSplits: 1).first ?? "")
    }

    public static func rowNumber(of workspace: String) -> Int {
        workspace.split(separator: "/", maxSplits: 1).dropFirst().first.flatMap { Int($0) } ?? 1
    }
}
