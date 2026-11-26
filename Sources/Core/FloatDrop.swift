import CoreGraphics

/// Where a floating window goes when it is dropped: snapped to an edge or a corner of the screen, put against another floating
/// window, or grouped with it (Cmd on its middle). `nil`: it stays where it was let go.
public enum FloatDrop: Equatable, Sendable {
    case frame(CGRect)
    case group(WindowID)

    /// How far from a corner, along each edge, the pointer counts as being in that corner.
    public static let cornerBand: CGFloat = 60

    /// `edges` is `false` when macOS tiles windows that are dragged to an edge itself: then wm leaves the edges to it.
    public static func target(
        pointer: CGPoint, dragged: WindowID, size: CGSize, others: [WindowID: CGRect], area: CGRect, edges: Bool, grouping: Bool
    ) -> FloatDrop? {
        if edges, let place = edgePlace(pointer, area) {
            return .frame(place == .top ? area : snapFrame(place, step: 0, in: area))
        }
        switch DropZone.find(pointer: pointer, dragged: dragged, tiles: others, area: area.insetBy(dx: -1000, dy: -1000)) {
        case .middle(let target): return grouping ? .group(target) : nil
        case .beside(let target, let side):
            guard let other = others[target] else { return nil }
            let fitted = CGSize(width: min(size.width, area.width), height: min(size.height, area.height))
            let origin: CGPoint = switch side {
            case .left: CGPoint(x: other.minX - fitted.width, y: other.minY)
            case .right: CGPoint(x: other.maxX, y: other.minY)
            case .up: CGPoint(x: other.minX, y: other.minY - fitted.height)
            case .down: CGPoint(x: other.minX, y: other.maxY)
            }
            return .frame(MonitorGeometry.clamped(CGRect(origin: origin, size: fitted), in: area))
        case .screenEdge, .none: return nil
        }
    }

    /// The place of the screen that an edge or a corner under the pointer stands for: a half at the sides, all of it at the top,
    /// a quarter in a corner.
    static func edgePlace(_ pointer: CGPoint, _ area: CGRect) -> SnapPlace? {
        let band = DropZone.edgeBand
        let left = pointer.x - area.minX <= band, right = area.maxX - pointer.x <= band
        let top = pointer.y - area.minY <= band, bottom = area.maxY - pointer.y <= band
        let nearTop = pointer.y - area.minY <= cornerBand, nearBottom = area.maxY - pointer.y <= cornerBand
        let nearLeft = pointer.x - area.minX <= cornerBand, nearRight = area.maxX - pointer.x <= cornerBand
        if (left && nearTop) || (top && nearLeft) { return .topLeft }
        if (right && nearTop) || (top && nearRight) { return .topRight }
        if (left && nearBottom) || (bottom && nearLeft) { return .bottomLeft }
        if (right && nearBottom) || (bottom && nearRight) { return .bottomRight }
        if left { return .left }
        if right { return .right }
        if top { return .top }
        if bottom { return .bottom }
        return nil
    }
}
