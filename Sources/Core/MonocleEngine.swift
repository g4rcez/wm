import CoreGraphics
import Foundation

/// The `monocle` layout: one window fills the workspace and the other windows wait out of sight. `focus next` and
/// `focus prev` walk through them. The order of the windows is the order of that walk.
///
/// The windows that wait are parked in the hidden corner, like the windows of a hidden workspace. They are not stacked
/// behind the shown window: macOS brings every window of the active app forward, so equal windows could not be ordered.
public struct MonocleEngine: LayoutEngine {
    private var order: [WindowID] = []
    /// The window that fills the area: the focused one, or the last one that was while focus is on a floating window.
    private var current: WindowID?

    public init(settings: Settings) {}

    /// An engine with these windows in this order. For a layout that changes to `monocle`.
    public init(settings: Settings, windows: [WindowID]) {
        order = windows
        current = windows.first
    }

    /// The order and the window in view, for saving.
    public struct State: Codable, Sendable {
        fileprivate var order: [WindowID]
        fileprivate var current: WindowID?
    }

    public init(settings: Settings, state: State) {
        order = state.order
        current = state.current.flatMap { state.order.contains($0) ? $0 : nil } ?? state.order.first
    }

    public var state: LayoutState { .monocle(State(order: order, current: current)) }

    public var windows: [WindowID] { order }

    /// The place of `window` in the walk (0 is the first) and how many windows there are, for the tab indicator.
    public func position(of window: WindowID) -> (index: Int, count: Int)? {
        order.firstIndex(of: window).map { ($0, order.count) }
    }

    public func templateError(_ template: SplitTemplate, focused: WindowID?) -> String? {
        "tile templates are for the tiling and scrolling layouts"
    }

    public mutating func insert(_ window: WindowID, after anchor: WindowID?) {
        guard !order.contains(window) else { return }
        if let anchor, let index = order.firstIndex(of: anchor) {
            order.insert(window, at: index + 1)
        } else {
            order.append(window)
        }
        if current == nil { current = window }
    }

    public mutating func remove(_ window: WindowID) {
        guard let index = order.firstIndex(of: window) else { return }
        order.remove(at: index)
        // The window that was after the closed one comes into view, or the last one.
        if current == window { current = order.isEmpty ? nil : order[min(index, order.count - 1)] }
    }

    public mutating func relabel(_ mapping: [WindowID: WindowID]) {
        order = order.map { mapping[$0] ?? $0 }
        current = current.map { mapping[$0] ?? $0 }
    }

    public mutating func frames(in context: LayoutContext, focused: WindowID?) -> [WindowID: CGRect] {
        if let focused, order.contains(focused) { current = focused }
        if current == nil || !order.contains(current!) { current = order.first }
        let area = context.gaps.tile(context.gaps.tilingArea(context.viewport))
        let corner = context.hiddenCorner ?? CGPoint(x: context.viewport.maxX - 1, y: context.viewport.maxY - 1)
        let parked = CGRect(origin: corner, size: area.size)
        return Dictionary(uniqueKeysWithValues: order.map { ($0, $0 == current ? area : parked) })
    }

    /// Every window at the same place, so the miniature of the switcher shows what monocle does: one window per screen.
    public func overview(in context: LayoutContext, focused: WindowID?) -> LayoutOverview {
        let area = context.gaps.tile(context.gaps.tilingArea(context.viewport))
        return LayoutOverview(frames: Dictionary(uniqueKeysWithValues: order.map { ($0, area) }), viewports: [context.viewport])
    }

    /// The window before (left, up) or after (right, down) `window`, going around at the ends with `wrap`.
    public mutating func neighbor(of window: WindowID, _ direction: Direction, wrap: Bool, in context: LayoutContext) -> WindowID? {
        guard let index = order.firstIndex(of: window) else { return nil }
        let next = index + (direction == .right || direction == .down ? 1 : -1)
        if order.indices.contains(next) { return order[next] }
        return wrap && order.count > 1 ? order[(next + order.count) % order.count] : nil
    }

    public mutating func perform(_ command: LayoutCommand, focused: WindowID?, in context: LayoutContext) -> Bool {
        switch command {
        case .move(let direction):
            guard let focused, let index = order.firstIndex(of: focused),
                  let other = neighbor(of: focused, direction, wrap: false, in: context),
                  let target = order.firstIndex(of: other) else { return false }
            order.swapAt(index, target)
            return true

        case .rotate(let clockwise):
            guard order.count > 1 else { return false }
            if clockwise { order.insert(order.removeLast(), at: 0) } else { order.append(order.removeFirst()) }
            return true

        default:
            return false
        }
    }
}
