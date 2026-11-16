import CoreGraphics

public extension PixelFrame {
    /// A pseudotiled window: it keeps its own `size` (cut down to the cell when it does not fit) and sits in the middle
    /// of its `cell`.
    static func centered(_ size: CGSize, in cell: CGRect) -> CGRect {
        let width = min(size.width, cell.width), height = min(size.height, cell.height)
        return CGRect(x: cell.midX - width / 2, y: cell.midY - height / 2, width: width, height: height)
    }
}

public enum PixelFrame {
    /// The frame in whole points for the Accessibility API. Origin and size round on their own. `CGRect.integral` rounds
    /// the far edge up, so a window that only moves by a fraction of a point would change its width by one point from
    /// frame to frame, and the app would lay out its content again at each change.
    public static func rounded(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX.rounded(), y: frame.minY.rounded(), width: frame.width.rounded(), height: frame.height.rounded())
    }
}
