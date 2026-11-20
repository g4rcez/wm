import CoreGraphics
import Foundation

/// Where the windows of a workspace start when a workspace switch slides them in (`animations.workspaces.style`).
public enum WorkspaceSlide {
    public enum Style: String, Sendable, CaseIterable {
        /// The windows jump to their place.
        case none
        /// The windows come in from the side: from the right when you go to a later workspace, from the left for an earlier one.
        case slide
        /// The windows come in from the bottom.
        case slidevert
    }

    /// Whether `new` comes after `old`: numbers by value, other names in the order of the Finder.
    public static func isForward(from old: String, to new: String) -> Bool {
        if let a = Int(old), let b = Int(new) { return b > a }
        return new.localizedStandardCompare(old) == .orderedDescending
    }

    /// The frame a window slides in from, or `nil` when it must jump: a window cannot start beyond an edge that has another monitor
    /// (it would show there while it moves), and macOS keeps a window that is fully off screen from being placed, so it starts with
    /// one point of itself on the screen. `freeEdges` are the edges of the monitor that have no neighbour (`LayoutContext.sliverEdges`).
    public static func start(
        of target: CGRect, viewport: CGRect, style: Style, forward: Bool, freeEdges: Set<Direction>
    ) -> CGRect? {
        var frame = target
        switch style {
        case .none:
            return nil
        case .slide:
            let sides: [Direction] = forward ? [.right, .left] : [.left, .right]
            guard let side = sides.first(where: freeEdges.contains) else { return nil }
            frame.origin.x = side == .right ? viewport.maxX - 1 : viewport.minX - target.width + 1
        case .slidevert:
            guard freeEdges.contains(.down) else { return nil }
            frame.origin.y = viewport.maxY - 1
        }
        return frame == target ? nil : frame
    }
}
