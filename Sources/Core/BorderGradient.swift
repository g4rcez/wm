import CoreGraphics
import Foundation

/// The line that a border gradient runs along, for a box of one unit by one unit (y up, as in a layer on macOS).
public enum BorderGradient {
    /// The angle is in degrees and goes clockwise from "up", as in CSS: 0 runs from the bottom to the top, 90 from the left to the
    /// right, 180 from the top to the bottom, 270 from the right to the left. 45 runs from the bottom left corner to the top right one.
    /// The line goes through the center, and its ends are set so that the first color reaches one corner and the last color the
    /// opposite one, as in CSS. For an angle that is not a multiple of 45 the ends are outside the box.
    public static func points(angle degrees: Double) -> (start: CGPoint, end: CGPoint) {
        let radians = degrees * .pi / 180
        let dx = sin(radians), dy = cos(radians)
        let half = (abs(dx) + abs(dy)) / 2
        return (CGPoint(x: 0.5 - dx * half, y: 0.5 - dy * half), CGPoint(x: 0.5 + dx * half, y: 0.5 + dy * half))
    }
}
