import CoreGraphics
import Foundation

/// Native window id (`CGWindowID`).
public typealias WindowID = UInt32

public enum Direction: String, Sendable, CaseIterable {
    case left, right, up, down

    public var opposite: Direction {
        switch self {
        case .left: .right
        case .right: .left
        case .up: .down
        case .down: .up
        }
    }

    public var isHorizontal: Bool { self == .left || self == .right }
}

public enum Orientation: String, Sendable, Codable {
    case horizontal, vertical
}

/// All rectangles in this module use screen coordinates with the origin at the top-left and y growing down
/// (the Accessibility API convention).
public struct Gaps: Sendable, Equatable {
    /// Space between two windows, in points.
    public var inner: CGFloat
    public var top: CGFloat
    public var right: CGFloat
    public var bottom: CGFloat
    public var left: CGFloat

    public init(inner: CGFloat = 0, top: CGFloat = 0, right: CGFloat = 0, bottom: CGFloat = 0, left: CGFloat = 0) {
        self.inner = inner
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    public init(inner: CGFloat, outer: CGFloat) {
        self.init(inner: inner, top: outer, right: outer, bottom: outer, left: outer)
    }

    /// The area that tiles partition: the viewport minus the outer gaps, grown by half the inner gap so that
    /// `tile(_:)` leaves exactly `outer` at the screen edge and `inner` between neighbours.
    public func tilingArea(_ viewport: CGRect) -> CGRect {
        let half = inner / 2
        return CGRect(
            x: viewport.minX + left - half,
            y: viewport.minY + top - half,
            width: viewport.width - left - right + inner,
            height: viewport.height - top - bottom + inner
        )
    }

    /// The viewport inset by the outer gaps only: where a maximized window goes.
    public func outerArea(_ viewport: CGRect) -> CGRect {
        CGRect(x: viewport.minX + left, y: viewport.minY + top, width: viewport.width - left - right, height: viewport.height - top - bottom)
    }

    /// The window frame inside one cell of the partition.
    public func tile(_ cell: CGRect) -> CGRect {
        cell.insetBy(dx: inner / 2, dy: inner / 2)
    }
}

/// What an engine needs to know about the screen it lays out.
public struct LayoutContext: Sendable, Equatable {
    public var viewport: CGRect
    public var gaps: Gaps
    /// Where a window that must disappear is parked (the bottom-right corner of all monitors). `nil` falls back to the
    /// viewport's own bottom-right corner.
    public var hiddenCorner: CGPoint?
    /// Screen edges where a window may stick out as a thin sliver. An edge with a neighbouring monitor is left out
    /// (the sliver would show there), and so is `.up` (macOS keeps title bars below the menu bar).
    public var sliverEdges: Set<Direction>

    public init(
        viewport: CGRect,
        gaps: Gaps = Gaps(),
        hiddenCorner: CGPoint? = nil,
        sliverEdges: Set<Direction> = [.left, .right, .down]
    ) {
        self.viewport = viewport
        self.gaps = gaps
        self.hiddenCorner = hiddenCorner
        self.sliverEdges = sliverEdges
    }
}

/// The layout drawn as a miniature, for the window switcher.
public struct LayoutOverview: Sendable, Equatable {
    /// Every window at its un-parked position, in the engine's own coordinate space (a scrolling strip may extend
    /// beyond the screen).
    public var frames: [WindowID: CGRect]
    /// The parts of that space that are on screen now (one rectangle per zone), to outline in the miniature.
    public var viewports: [CGRect]

    public init(frames: [WindowID: CGRect], viewports: [CGRect]) {
        self.frames = frames
        self.viewports = viewports
    }
}

public enum ResizeDimension: String, Sendable {
    case width, height
    /// The dimension that changes the focused window in the layout's natural split direction.
    case smart
}

public enum ColumnWidth: Sendable, Equatable {
    /// Fraction of the viewport width (for example 0.5).
    case fraction(Double)
    /// Next preset after the current one; wraps around.
    case cycle
}

/// Layout commands. An engine ignores (returns `false` for) the commands that do not apply to it.
public enum LayoutCommand: Sendable, Equatable {
    /// Swap the focused window with its neighbour in that direction (reorder, or move into the neighbour's slot).
    case move(Direction)
    /// Grow (`delta > 0`) or shrink the focused window by `delta` points.
    case resize(ResizeDimension, CGFloat)
    /// A mouse resize: move the divider on the `direction` side of the focused window by this many points. A positive
    /// delta makes the window larger on that side. Returns `false` when that side is the edge of the screen (there is no
    /// divider to move), when the delta is zero, or when the layout cannot honour it. The delta is clamped like `resize`.
    case resizeEdge(Direction, CGFloat)
    /// scrolling: move the focused window into the horizontal strip (`.horizontal`) or the vertical strip (`.vertical`).
    case sendToStrip(Orientation)
    /// scrolling: the focused window and the windows after it form a group that fills one screen in this pattern.
    /// tiling: all windows of the workspace take this pattern (there must be exactly as many as the pattern has cells).
    case applyTemplate(SplitTemplate)
    /// scrolling: the group of the focused window goes back to single columns ("back to the chain").
    /// tiling: the automatic dwindle layout again, in the same window order.
    case releaseTemplate
    /// tiling: every split switches between side by side and stacked (columns become rows, and back).
    case rotateLayout
    /// Every window moves one slot clockwise (or counterclockwise) around the layout. Slot sizes stay with the slot.
    case rotate(clockwise: Bool)
    /// Give all windows an equal share. Scrolling: every column gets 1/N of the screen width, so all columns fit
    /// on screen at once (Ribbon's "fit columns on screen").
    case balance
    /// scrolling: every column gets the width of the focused column.
    case matchWidth
    /// scrolling: the windows of the focused column's stack get equal heights.
    case equalizeStack
    /// tiling: flip the split orientation of the focused window's parent.
    case toggleSplit
    /// tiling: swap the two children of the focused window's parent.
    case swapSplit
    /// tiling: the next window that opens splits the focused window on this side, once.
    case preselect(Direction)
    /// tiling: the share of its split that the focused window gets: exact (0.1...0.9) or a change of its share.
    case splitRatio(Double, relative: Bool)
    /// tiling: the focused window becomes a direct child of the root split, so it gets half of the screen.
    case moveToRoot
    /// scrolling: set or cycle the width of the focused column.
    case columnWidth(ColumnWidth)
    /// scrolling: join the focused window into the column to its left (a stack).
    case stack
    /// scrolling: pull the focused window out of its stack into its own column to the right.
    case unstack
    /// scrolling: toggle tabbed display of the focused column's stack.
    case toggleTabs
    /// scrolling: the focused window keeps its place in the strip and grows to the whole zone (the column gets the full
    /// width, a stack shows it at the full height). The same command again restores the old size.
    case maximize
    /// scrolling: scroll the strip so the focused column is centred.
    case center
    /// scrolling: scroll the strip so the columns that are fully on screen are centred together.
    case centerVisible
    /// scrolling: set or cycle the height of the focused window inside its stack.
    case windowHeight(ColumnWidth)
    /// scrolling: scroll the strip by this many points (positive moves the view to the right).
    case scroll(CGFloat)
}

public protocol LayoutEngine: Sendable {
    init(settings: Settings)

    /// All managed windows in layout order.
    var windows: [WindowID] { get }

    /// Everything that `makeEngine(restoring:settings:)` needs to build the same layout again.
    var state: LayoutState { get }

    /// Adds a window. `anchor` is the focused window; the new window opens beside it (or splits it).
    mutating func insert(_ window: WindowID, after anchor: WindowID?)
    mutating func remove(_ window: WindowID)

    /// Why `template` cannot be applied around `focused`, or `nil` when it can.
    func templateError(_ template: SplitTemplate, focused: WindowID?) -> String?

    /// Returns `true` when the command changed the layout.
    mutating func perform(_ command: LayoutCommand, focused: WindowID?, in context: LayoutContext) -> Bool

    /// Target frame of every window. A scrolling engine may return frames outside the viewport (parked slivers).
    mutating func frames(in context: LayoutContext, focused: WindowID?) -> [WindowID: CGRect]

    /// The window to focus when moving in `direction`, or `nil` at the edge when `wrap` is `false`.
    mutating func neighbor(of window: WindowID, _ direction: Direction, wrap: Bool, in context: LayoutContext) -> WindowID?

    /// The layout as a miniature for the window switcher: un-parked positions, and the on-screen parts.
    func overview(in context: LayoutContext, focused: WindowID?) -> LayoutOverview

    /// Puts other windows into the same slots without changing any geometry: the window `old` is replaced by
    /// `mapping[old]`. Windows missing from `mapping` stay. This is how `rotate` is applied.
    mutating func relabel(_ mapping: [WindowID: WindowID])
}

public extension LayoutEngine {
    /// Default: what `frames` returns, and the whole viewport as the on-screen part.
    func overview(in context: LayoutContext, focused: WindowID?) -> LayoutOverview {
        var copy = self
        return LayoutOverview(frames: copy.frames(in: context, focused: focused), viewports: [context.viewport])
    }

    /// Default: nothing. Every engine that supports `rotate` implements it.
    mutating func relabel(_ mapping: [WindowID: WindowID]) {}

    /// Geometric default: the nearest window whose frame lies in that direction.
    mutating func neighbor(of window: WindowID, _ direction: Direction, wrap: Bool, in context: LayoutContext) -> WindowID? {
        let layout = frames(in: context, focused: window)
        return nearestWindow(from: window, direction, in: layout, wrap: wrap)
    }
}

/// Picks the window nearest to `window` in `direction`. Windows overlapping the source on the perpendicular axis
/// win over diagonal ones. With `wrap`, the farthest overlapping window on the opposite side is used at an edge.
public func nearestWindow(from window: WindowID, _ direction: Direction, in frames: [WindowID: CGRect], wrap: Bool) -> WindowID? {
    guard let source = frames[window] else { return nil }

    func overlap(_ rect: CGRect) -> Bool {
        direction.isHorizontal
            ? rect.maxY > source.minY + 0.5 && rect.minY < source.maxY - 0.5
            : rect.maxX > source.minX + 0.5 && rect.minX < source.maxX - 0.5
    }
    func distance(_ rect: CGRect) -> CGFloat {
        switch direction {
        case .left: source.minX - rect.maxX
        case .right: rect.minX - source.maxX
        case .up: source.minY - rect.maxY
        case .down: rect.minY - source.maxY
        }
    }
    func offAxis(_ rect: CGRect) -> CGFloat {
        direction.isHorizontal ? abs(rect.midY - source.midY) : abs(rect.midX - source.midX)
    }

    let others = frames.filter { $0.key != window }
    // Ties on distance are broken by perpendicular offset, then by id so the result is deterministic.
    let ahead = others
        .filter { distance($0.value) >= -0.5 }
        .min { lhs, rhs in
            let l = (overlap(lhs.value) ? 0 : 1, distance(lhs.value), offAxis(lhs.value), lhs.key)
            let r = (overlap(rhs.value) ? 0 : 1, distance(rhs.value), offAxis(rhs.value), rhs.key)
            return l < r
        }
    if let ahead, overlap(ahead.value) { return ahead.key }
    guard wrap else { return ahead?.key }

    let opposite = direction.opposite
    return others
        .filter { overlap($0.value) }
        .min { lhs, rhs in
            let l = (distanceFromEdge(lhs.value, opposite, source), offAxis(lhs.value), lhs.key)
            let r = (distanceFromEdge(rhs.value, opposite, source), offAxis(rhs.value), rhs.key)
            return l < r
        }?.key
}

/// Like `nearestWindow`, for a window that lies on top of the others (a floating window): another window is "in that
/// direction" when its centre is, even if the two overlap. Windows that are near and straight ahead win over far or
/// sideways ones; ties go to the lower id. With `wrap`, at the edge the farthest window on the opposite side is used.
public func nearestWindowByCenter(from window: WindowID, _ direction: Direction, in frames: [WindowID: CGRect], wrap: Bool) -> WindowID? {
    guard let source = frames[window] else { return nil }
    func offsets(_ rect: CGRect) -> (along: CGFloat, across: CGFloat) {
        let dx = rect.midX - source.midX, dy = rect.midY - source.midY
        switch direction {
        case .right: return (dx, abs(dy))
        case .left: return (-dx, abs(dy))
        case .down: return (dy, abs(dx))
        case .up: return (-dy, abs(dx))
        }
    }
    func cost(_ rect: CGRect) -> CGFloat {
        let offset = offsets(rect)
        return offset.along + 2 * offset.across
    }
    let others = frames.filter { $0.key != window }
    let ahead = others.filter { offsets($0.value).along > 0.5 }.min { (cost($0.value), $0.key) < (cost($1.value), $1.key) }
    if let ahead { return ahead.key }
    guard wrap else { return nil }
    // Behind the source: `along` is negative, so the lowest cost is the farthest window, straight behind.
    return others.filter { offsets($0.value).along < -0.5 }.min { (cost($0.value), $0.key) < (cost($1.value), $1.key) }?.key
}

/// How far `rect` is from the far edge on the `opposite` side of the source; smaller is closer to that edge.
private func distanceFromEdge(_ rect: CGRect, _ opposite: Direction, _ source: CGRect) -> CGFloat {
    switch opposite {
    case .left: rect.minX
    case .right: -rect.maxX
    case .up: rect.minY
    case .down: -rect.maxY
    }
}
