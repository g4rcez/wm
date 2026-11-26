import CoreGraphics

/// Where a dragged window would land if it were dropped at the pointer now: beside another window, on its middle, or along an
/// edge of the screen. A space opens there while the window is still being dragged.
public enum DropZone: Equatable, Sendable {
    /// Against this side of the window: a new tile opens on that side.
    case beside(WindowID, Direction)
    /// The centre of the window: the two swap (or, in a floating layout with Cmd, make a group).
    case middle(WindowID)
    /// Along this edge of the work area: the window takes that whole side.
    case screenEdge(Direction)
    case none

    /// The part of a window, from each side, that counts as that side and not as its middle.
    public static let sideShare: CGFloat = 0.3
    /// How far from an edge of the work area the pointer counts as being on that edge.
    public static let edgeBand: CGFloat = 16

    public static func find(pointer: CGPoint, dragged: WindowID, tiles: [WindowID: CGRect], area: CGRect) -> DropZone {
        if area.contains(pointer) || area.insetBy(dx: -edgeBand, dy: -edgeBand).contains(pointer) {
            let distances: [(Direction, CGFloat)] = [
                (.left, pointer.x - area.minX), (.right, area.maxX - pointer.x), (.up, pointer.y - area.minY), (.down, area.maxY - pointer.y),
            ]
            if let edge = distances.filter({ $0.1 <= edgeBand }).min(by: { $0.1 < $1.1 }) { return .screenEdge(edge.0) }
        }
        // The smallest window under the pointer: a window in front of a larger one (a floating one) is usually the smaller.
        let under = tiles.filter { $0.key != dragged && $0.value.contains(pointer) && $0.value.width > 0 && $0.value.height > 0 }
        guard let (target, frame) = under.min(by: { $0.value.width * $0.value.height < $1.value.width * $1.value.height }) else {
            return .none
        }
        let x = (pointer.x - frame.minX) / frame.width, y = (pointer.y - frame.minY) / frame.height
        let sides: [(Direction, CGFloat)] = [(.left, x), (.right, 1 - x), (.up, y), (.down, 1 - y)]
        let nearest = sides.min { $0.1 < $1.1 }!
        return nearest.1 < sideShare ? .beside(target, nearest.0) : .middle(target)
    }
}
