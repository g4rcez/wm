import CoreGraphics

public enum PipCorner: String, CaseIterable, Sendable {
    case topLeft = "top-left", topRight = "top-right", bottomLeft = "bottom-left", bottomRight = "bottom-right"

    public var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    public var isTop: Bool { self == .topLeft || self == .topRight }
}

/// `window pip`: a small live copy of a window.
public struct PipSettings: Sendable, Equatable {
    public static let sizeRange = 0.1...0.6
    public static let fpsRange = 5...60
    public var corner = PipCorner.bottomRight
    /// The width of a picture as a fraction of the width of the work area.
    public var size = 0.25
    public var fps = 30
    /// Hide the picture while the window itself is on screen.
    public var hideWhenVisible = true
    public init() {}
}

/// Where the pictures of one corner go, the first one in the corner and each next one above or below it. `shapes` are the
/// sizes of the windows; a picture keeps the shape of its window and is at most half of the area high.
public func pipFrames(_ shapes: [CGSize], corner: PipCorner, widthFraction: Double, in area: CGRect, margin: CGFloat = 16) -> [CGRect] {
    var used = margin
    return shapes.map { shape in
        var width = area.width * CGFloat(widthFraction)
        let ratio = shape.width > 0 && shape.height > 0 ? shape.height / shape.width : 0.625
        var height = width * ratio
        let tallest = area.height / 2
        if height > tallest {
            height = tallest
            width = height / ratio
        }
        let x = corner.isLeft ? area.minX + margin : area.maxX - margin - width
        let y = corner.isTop ? area.minY + used : area.maxY - used - height
        used += height + margin / 2
        return CGRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }
}

/// The corner of `area` that `point` is nearest to, where a picture that was dragged goes.
public func nearestCorner(to point: CGPoint, in area: CGRect) -> PipCorner {
    switch (point.x < area.midX, point.y < area.midY) {
    case (true, true): .topLeft
    case (false, true): .topRight
    case (true, false): .bottomLeft
    case (false, false): .bottomRight
    }
}
