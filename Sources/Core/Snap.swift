import CoreGraphics
import Foundation

/// Where `window snap` puts a floating window in the work area.
public enum SnapPlace: String, Sendable, CaseIterable {
    case left, right, top, bottom
    case topLeft = "top-left", topRight = "top-right", bottomLeft = "bottom-left", bottomRight = "bottom-right"
    case topCenter = "top-center", bottomCenter = "bottom-center"
    case center

    /// The sizes that the same place takes in turn when the key is pressed again, as fractions of the area.
    var steps: [Double] {
        switch self {
        case .left, .right, .top, .bottom: [1.0 / 2, 1.0 / 3, 2.0 / 3]
        case .topLeft, .topRight, .bottomLeft, .bottomRight, .topCenter, .bottomCenter: [1.0 / 2]
        case .center: [0.6, 0.8, 0.4]
        }
    }

    public var stepCount: Int { steps.count }
}

/// The frame of `place` in `area` for a step of its cycle (`step` counts from 0 and wraps).
public func snapFrame(_ place: SnapPlace, step: Int, in area: CGRect) -> CGRect {
    let steps = place.steps
    let fraction = CGFloat(steps[((step % steps.count) + steps.count) % steps.count])
    let width = area.width * fraction, height = area.height * fraction
    switch place {
    case .left: return CGRect(x: area.minX, y: area.minY, width: width, height: area.height)
    case .right: return CGRect(x: area.maxX - width, y: area.minY, width: width, height: area.height)
    case .top: return CGRect(x: area.minX, y: area.minY, width: area.width, height: height)
    case .bottom: return CGRect(x: area.minX, y: area.maxY - height, width: area.width, height: height)
    case .topLeft: return CGRect(x: area.minX, y: area.minY, width: width, height: height)
    case .topRight: return CGRect(x: area.maxX - width, y: area.minY, width: width, height: height)
    case .bottomLeft: return CGRect(x: area.minX, y: area.maxY - height, width: width, height: height)
    case .bottomRight: return CGRect(x: area.maxX - width, y: area.maxY - height, width: width, height: height)
    case .topCenter: return CGRect(x: area.midX - width / 2, y: area.minY, width: width, height: height)
    case .bottomCenter: return CGRect(x: area.midX - width / 2, y: area.maxY - height, width: width, height: height)
    case .center: return CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
    }
}

/// The step to use now: the one after the step whose frame the window has (within 4 points), else the first. So pressing the
/// same place again goes on to the next size.
public func nextSnapStep(current: CGRect, place: SnapPlace, in area: CGRect) -> Int {
    let tolerance: CGFloat = 4
    func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= tolerance }
    for step in 0..<place.stepCount {
        let frame = snapFrame(place, step: step, in: area)
        if near(frame.minX, current.minX), near(frame.minY, current.minY), near(frame.width, current.width), near(frame.height, current.height) {
            return (step + 1) % place.stepCount
        }
    }
    return 0
}
