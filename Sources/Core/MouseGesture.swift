import CoreGraphics

/// Whether a mouse press can start a native move or resize of a tiled window, the only gesture that wm has to measure.
/// macOS resizes a window from its edges and moves it from its title bar. wm reads the frames of every window at the press, an
/// AX call to every app, so a click inside a window (the most common click of all) should not pay for it.
public enum MouseGesture {
    /// How close to an edge, inside or outside, a press can grab it.
    public static let edge: CGFloat = 10
    /// The top strip that moves a window. Larger than a plain title bar: browsers and editors move from a tab strip or a toolbar.
    public static let titleBar: CGFloat = 60

    public static func mayRearrange(at point: CGPoint, frames: [CGRect]) -> Bool {
        frames.contains { frame in
            let grab = frame.insetBy(dx: -edge, dy: -edge)
            guard grab.contains(point) else { return false }
            let inner = frame.insetBy(dx: edge, dy: edge)
            let inTitleBar = point.y < frame.minY + titleBar
            return !inner.contains(point) || inTitleBar
        }
    }
}
