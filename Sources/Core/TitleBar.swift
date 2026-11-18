import CoreGraphics

/// Whether `point` is in the title bar of a window: the top strip of `height` points of its frame (Accessibility coordinates,
/// y grows downward). This is a frame test, with no call to the app, so it also works for an app that draws its own title bar.
public func titleBarContains(_ point: CGPoint, frame: CGRect, height: CGFloat) -> Bool {
    point.x >= frame.minX && point.x < frame.maxX && point.y >= frame.minY && point.y < frame.minY + min(height, frame.height)
}
