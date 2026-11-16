import CoreGraphics
import Foundation

/// The state of the window switcher: which windows it lists, in which order, and which one is selected.
/// Pure logic, so the overlay only draws it.
public struct SwitcherModel: Sendable, Equatable {
    private let overview: LayoutOverview
    private let floating: [WindowID: CGRect]
    /// Windows by recency (most recent first), then the other tiled windows from top-left, then the other floating ones.
    public let order: [WindowID]
    public private(set) var selected: WindowID?

    /// `mru` may contain ids that are not on screen any more; they are ignored.
    public init(overview: LayoutOverview, floating: [WindowID: CGRect], mru: [WindowID], focused: WindowID?) {
        self.overview = overview
        self.floating = floating

        func known(_ id: WindowID) -> Bool { overview.frames[id] != nil || floating[id] != nil }
        var seen = Set<WindowID>()
        var order = mru.filter { known($0) && seen.insert($0).inserted }
        let tiled = overview.frames.filter { !seen.contains($0.key) }
            .sorted { ($0.value.minY, $0.value.minX, $0.key) < ($1.value.minY, $1.value.minX, $1.key) }
            .map(\.key)
        seen.formUnion(tiled)
        order += tiled
        order += floating.keys.filter { !seen.contains($0) }.sorted()
        self.order = order
        selected = order.count > 1 ? order[1] : order.first
    }

    /// Frames of the tiled and the floating windows, in the overview's coordinate space.
    public var frames: [WindowID: CGRect] { overview.frames.merging(floating) { _, floating in floating } }

    public var viewports: [CGRect] { overview.viewports }

    /// Tab is `+1`, Shift+Tab is `-1`. Wraps around.
    public mutating func step(_ delta: Int) {
        guard let selected, let index = order.firstIndex(of: selected) else { return }
        let count = order.count
        self.selected = order[((index + delta) % count + count) % count]
    }

    public mutating func move(_ direction: Direction) {
        guard let selected, let next = nearestWindow(from: selected, direction, in: frames, wrap: true) else { return }
        self.selected = next
    }

    public mutating func select(_ id: WindowID) {
        if order.contains(id) { selected = id }
    }
}

public enum Miniature {
    /// Uniform scale and translation that centre the union of `rects` in `bounds` inset by `padding`. The scale
    /// never exceeds `maxScale`, so a small layout is not enlarged beyond it. No rectangles: the identity.
    public static func transform(fitting rects: [CGRect], into bounds: CGRect, padding: CGFloat, maxScale: CGFloat) -> CGAffineTransform {
        guard let first = rects.first else { return .identity }
        let union = rects.dropFirst().reduce(first) { $0.union($1) }
        let area = bounds.insetBy(dx: padding, dy: padding)
        guard union.width > 0, union.height > 0, area.width > 0, area.height > 0 else { return .identity }
        let scale = min(area.width / union.width, area.height / union.height, maxScale)
        let x = area.midX - union.midX * scale
        let y = area.midY - union.midY * scale
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: x, ty: y)
    }

    /// Several layouts as one, for the overview of all workspaces: one row per layout, top to bottom, `spacing` apart.
    /// The on-screen parts start at the same x, so a scrolling strip sticks out to the left and right of its row.
    /// `rows` is the area of each layout in the combined space.
    public static func rows(_ overviews: [LayoutOverview], spacing: CGFloat) -> (overview: LayoutOverview, rows: [CGRect]) {
        var combined = LayoutOverview(frames: [:], viewports: [])
        var rows: [CGRect] = []
        var top: CGFloat = 0
        for overview in overviews {
            let rects = Array(overview.frames.values) + overview.viewports
            guard let first = rects.first else { continue }
            let union = rects.dropFirst().reduce(first) { $0.union($1) }
            let move = CGAffineTransform(translationX: -(overview.viewports.first?.minX ?? union.minX), y: top - union.minY)
            for (id, frame) in overview.frames { combined.frames[id] = frame.applying(move) }
            combined.viewports += overview.viewports.map { $0.applying(move) }
            let row = union.applying(move)
            rows.append(row)
            top = row.maxY + spacing
        }
        return (combined, rows)
    }
}
