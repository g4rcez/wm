import CoreGraphics

/// Where the window of the zen mode goes: the middle of `area`, `width` of its width (0.3...1) and its whole height.
public func zenFrame(in area: CGRect, width: Double) -> CGRect {
    let fraction = CGFloat(min(max(width, ZenSettings.minWidth), 1))
    let size = area.width * fraction
    return CGRect(x: area.midX - size / 2, y: area.minY, width: size, height: area.height)
}
