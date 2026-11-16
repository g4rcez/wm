import CoreGraphics
import Foundation

/// The windows in clockwise order around the centre of the layout. Rectangles use screen coordinates (y grows down),
/// where a growing angle is a clockwise turn. Ties (windows on top of each other, as tabs) are broken by distance and id.
public func clockwiseRing(_ frames: [WindowID: CGRect]) -> [WindowID] {
    guard let first = frames.values.first else { return [] }
    let bounds = frames.values.reduce(first) { $0.union($1) }
    let center = CGPoint(x: bounds.midX, y: bounds.midY)

    func key(_ id: WindowID) -> (Double, Double, WindowID) {
        let frame = frames[id]!
        let dx = Double(frame.midX - center.x), dy = Double(frame.midY - center.y)
        // Rounded so that two windows on the same ray (for example a column and its neighbour) tie.
        return ((atan2(dy, dx) * 1e6).rounded() / 1e6, dx * dx + dy * dy, id)
    }
    return frames.keys.sorted { key($0) < key($1) }
}

/// The `relabel` mapping that moves every window of `ring` to the next slot (clockwise), or the previous one.
/// The window now in slot *i* is replaced by the window that was in slot *i - 1* (clockwise) or *i + 1*.
public func rotation(of ring: [WindowID], clockwise: Bool) -> [WindowID: WindowID] {
    let count = ring.count
    guard count > 1 else { return [:] }
    var mapping: [WindowID: WindowID] = [:]
    for (index, window) in ring.enumerated() {
        mapping[window] = ring[(index + (clockwise ? count - 1 : 1)) % count]
    }
    return mapping
}
