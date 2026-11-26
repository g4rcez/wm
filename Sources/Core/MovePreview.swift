import CoreGraphics

/// Where a tiled window lands when the user drops it: the slot that a placeholder shows while the window is dragged.
public enum MovePreview {
    /// Points that the window has to travel before the drag counts as a move (a click on a title bar does not).
    public static let threshold: CGFloat = 4

    /// The slot of the drop. Over another tile of the workspace the windows swap, so the dragged window takes that tile;
    /// anywhere else it goes back to its own tile. `tiles` are the tiled windows of the workspace with their tiles, the
    /// dragged one included. `nil` when the dragged window has no tile.
    public static func target(pointer: CGPoint, dragged: WindowID, tiles: [WindowID: CGRect]) -> CGRect? {
        if let other = tiles.first(where: { $0.key != dragged && $0.value.contains(pointer) }) { return other.value }
        return tiles[dragged]
    }

    /// Whether a window that was at `start` when the button went down is being moved: it went at least `threshold` points
    /// and kept its size (a window that changes size is being resized, not moved).
    public static func isMoving(from start: CGRect, to now: CGRect) -> Bool {
        let travelled = hypot(now.minX - start.minX, now.minY - start.minY)
        let sameSize = abs(now.width - start.width) <= 2 && abs(now.height - start.height) <= 2
        return travelled >= threshold && sameSize
    }
}
