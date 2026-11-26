import CoreGraphics
import Foundation

/// The `master` layout: the first `count` windows are masters and fill a big area, the other windows are the stack. The
/// order of the windows is the layout: masters first, then the stack from top to bottom (and, with the master in the middle,
/// right side first, then left, one after the other).
public struct MasterEngine: LayoutEngine {
    private var order: [WindowID] = []
    private var ratio: Double
    private var count: Int
    private var orientation: MasterOrientation
    private let newWindow: MasterSettings.NewWindow
    /// What the config said when this engine took `ratio`, `count` and `orientation`: a changed config wins over the live values.
    private let config: MasterSettings

    public init(settings: Settings) {
        let master = settings.master
        config = master
        newWindow = master.newWindow
        ratio = min(max(master.ratio, MasterSettings.minRatio), MasterSettings.maxRatio)
        count = max(1, master.count)
        orientation = master.orientation
    }

    /// An engine with these windows in this order: the first ones are the masters. For a layout that changes to `master`.
    public init(settings: Settings, windows: [WindowID]) {
        self.init(settings: settings)
        order = windows
    }

    /// The order and the live values, for saving.
    public struct State: Codable, Sendable {
        fileprivate var order: [WindowID]
        fileprivate var ratio: Double
        fileprivate var count: Int
        fileprivate var orientation: MasterOrientation
        /// The config values that the live ones started from.
        fileprivate var configRatio: Double
        fileprivate var configCount: Int
        fileprivate var configOrientation: MasterOrientation
    }

    public init(settings: Settings, state: State) {
        self.init(settings: settings)
        order = state.order
        // The live values stay while the config is the same as when they were set; a changed config wins.
        let unchanged = state.configRatio == settings.master.ratio && state.configCount == settings.master.count
            && state.configOrientation == settings.master.orientation
        if unchanged {
            ratio = min(max(state.ratio, MasterSettings.minRatio), MasterSettings.maxRatio)
            count = max(1, state.count)
            orientation = state.orientation
        }
    }

    public var state: LayoutState {
        .master(State(
            order: order, ratio: ratio, count: count, orientation: orientation,
            configRatio: config.ratio, configCount: config.count, configOrientation: config.orientation))
    }

    public var windows: [WindowID] { order }

    /// How far the ratio moves for a window that grows by one unit: a centered master sits between two dividers, and the stack
    /// grows against the master.
    private func dividerFactor(inMaster: Bool, centered: Bool) -> Double {
        inMaster ? (centered ? 2 : 1) : (centered ? -2 : -1)
    }

    public func templateError(_ template: SplitTemplate, focused: WindowID?) -> String? {
        "tile templates are for the tiling and scrolling layouts"
    }

    public mutating func insert(_ window: WindowID, after anchor: WindowID?) {
        guard !order.contains(window) else { return }
        if order.isEmpty {
            order = [window]
        } else if newWindow == .master {
            order.insert(window, at: 0)
        } else {
            order.insert(window, at: min(count, order.count))
        }
    }

    /// Puts `window` right before or after `target` in the order of the layout (a drop beside it).
    mutating func place(_ window: WindowID, near target: WindowID, after: Bool) {
        order.removeAll { $0 == window }
        guard let index = order.firstIndex(of: target) else { return order.append(window) }
        order.insert(window, at: after ? index + 1 : index)
    }

    public mutating func remove(_ window: WindowID) {
        order.removeAll { $0 == window }
    }

    public mutating func relabel(_ mapping: [WindowID: WindowID]) {
        order = order.map { mapping[$0] ?? $0 }
    }

    public mutating func frames(in context: LayoutContext, focused: WindowID?) -> [WindowID: CGRect] {
        let area = context.gaps.tilingArea(context.viewport)
        let cells = Self.cells(windows: order.count, masters: count, ratio: ratio, orientation: orientation, in: area)
        return Dictionary(uniqueKeysWithValues: zip(order, cells.map { context.gaps.tile($0) }))
    }

    // MARK: Geometry

    /// The cell of every window, in the order of the windows (masters, then the stack).
    public static func cells(windows n: Int, masters: Int, ratio: Double, orientation: MasterOrientation, in area: CGRect) -> [CGRect] {
        guard n > 0 else { return [] }
        let m = min(max(masters, 1), n), s = n - m
        /// `k` equal slices of `rect`, one above the other, or side by side.
        func rows(_ rect: CGRect, _ k: Int) -> [CGRect] {
            (0..<k).map { CGRect(x: rect.minX, y: rect.minY + rect.height * CGFloat($0) / CGFloat(k), width: rect.width, height: rect.height / CGFloat(k)) }
        }
        func columns(_ rect: CGRect, _ k: Int) -> [CGRect] {
            (0..<k).map { CGRect(x: rect.minX + rect.width * CGFloat($0) / CGFloat(k), y: rect.minY, width: rect.width / CGFloat(k), height: rect.height) }
        }
        let share = CGFloat(min(max(ratio, MasterSettings.minRatio), MasterSettings.maxRatio))
        switch orientation {
        case .left, .right:
            if s == 0 { return rows(area, m) }
            let width = area.width * share
            let masterX = orientation == .left ? area.minX : area.maxX - width
            let stackX = orientation == .left ? area.minX + width : area.minX
            let master = CGRect(x: masterX, y: area.minY, width: width, height: area.height)
            let stack = CGRect(x: stackX, y: area.minY, width: area.width - width, height: area.height)
            return rows(master, m) + rows(stack, s)
        case .top, .bottom:
            if s == 0 { return columns(area, m) }
            let height = area.height * share
            let masterY = orientation == .top ? area.minY : area.maxY - height
            let stackY = orientation == .top ? area.minY + height : area.minY
            let master = CGRect(x: area.minX, y: masterY, width: area.width, height: height)
            let stack = CGRect(x: area.minX, y: stackY, width: area.width, height: area.height - height)
            return columns(master, m) + columns(stack, s)
        case .center:
            // With one stack window there is nothing to put on the other side: it is the left layout (as in xmonad).
            if s <= 1 { return cells(windows: n, masters: masters, ratio: ratio, orientation: .left, in: area) }
            let width = area.width * share
            let side = (area.width - width) / 2
            let master = CGRect(x: area.minX + side, y: area.minY, width: width, height: area.height)
            let leftSide = CGRect(x: area.minX, y: area.minY, width: side, height: area.height)
            let rightSide = CGRect(x: area.maxX - side, y: area.minY, width: side, height: area.height)
            let right = rows(rightSide, (s + 1) / 2), left = rows(leftSide, s / 2)
            // The stack goes to the right first, then to the left, one window each.
            var stack: [CGRect] = []
            for index in 0..<s {
                stack.append(index % 2 == 0 ? right[index / 2] : left[index / 2])
            }
            return rows(master, m) + stack
        }
    }

    // MARK: Commands

    private var mastersInOrder: Int { min(count, order.count) }

    private mutating func setRatio(_ value: Double) -> Bool {
        let clamped = min(max(value, MasterSettings.minRatio), MasterSettings.maxRatio)
        guard abs(clamped - ratio) > 1e-9 else { return false }
        ratio = clamped
        return true
    }

    /// The side of the focused window that has the divider between the master area and the stack. A master in the middle has
    /// two, and so has a stack window of the left column of that layout only one.
    private func dividerSides(forIndex index: Int) -> [Direction] {
        let inMaster = index < mastersInOrder
        switch orientation {
        case .left: return [inMaster ? .right : .left]
        case .right: return [inMaster ? .left : .right]
        case .top: return [inMaster ? .down : .up]
        case .bottom: return [inMaster ? .up : .down]
        case .center:
            if order.count - mastersInOrder <= 1 { return [inMaster ? .right : .left] }
            if inMaster { return [.left, .right] }
            // The first stack window is on the right, so its divider is on its left side.
            return [(index - mastersInOrder) % 2 == 0 ? .left : .right]
        }
    }

    public mutating func perform(_ command: LayoutCommand, focused: WindowID?, in context: LayoutContext) -> Bool {
        guard command.isFinite else { return false }
        let area = context.gaps.tilingArea(context.viewport)
        let alongWidth = orientation != .top && orientation != .bottom
        let length = alongWidth ? area.width : area.height
        let index = focused.flatMap { order.firstIndex(of: $0) }
        let hasStack = order.count > mastersInOrder
        // With the master in the middle a window of a side column changes the ratio twice as fast.
        let centered = orientation == .center && order.count - mastersInOrder > 1

        switch command {
        case .move(let direction):
            guard let focused, let index,
                  let other = neighbor(of: focused, direction, wrap: false, in: context),
                  let target = order.firstIndex(of: other) else { return false }
            order.swapAt(index, target)
            return true

        case .resize(let dimension, let delta):
            guard let index, hasStack, length > 0, dimension == .smart || (dimension == .width) == alongWidth else { return false }
            let inMaster = index < mastersInOrder
            return setRatio(ratio + Double(delta / length) * (inMaster ? 1 : (centered ? -2 : -1)))

        case .resizeEdge(let direction, let points):
            guard let index, hasStack, points != 0, length > 0, dividerSides(forIndex: index).contains(direction) else { return false }
            let inMaster = index < mastersInOrder
            return setRatio(ratio + Double(points / length) * dividerFactor(inMaster: inMaster, centered: centered))

        case .resizeDirection(let direction, let points):
            // The divider is the one on the window's side (the right one for a centered master); it moves toward `direction`.
            guard let index, hasStack, points > 0, length > 0,
                  let side = dividerSides(forIndex: index).last, side.isHorizontal == direction.isHorizontal else { return false }
            let inMaster = index < mastersInOrder
            let growth = side == direction ? points : -points
            return setRatio(ratio + Double(growth / length) * dividerFactor(inMaster: inMaster, centered: centered))

        case .balance:
            return setRatio(0.5)

        case .rotate(let clockwise):
            guard order.count > 1 else { return false }
            if clockwise { order.insert(order.removeLast(), at: 0) } else { order.append(order.removeFirst()) }
            return true

        case .promote:
            guard let index, order.count > 1 else { return false }
            if index == 0 {
                order.swapAt(0, min(count, order.count - 1))
            } else {
                order.swapAt(0, index)
            }
            return true

        case .masterCount(let value, let relative):
            // A huge +n or -n must clamp, not trap: `count + value` overflows `Int`.
            let (sum, overflow) = count.addingReportingOverflow(value)
            let target = relative ? (overflow ? (value > 0 ? 99 : 1) : sum) : value
            let wanted = min(max(target, 1), 99)
            guard wanted != count else { return false }
            count = wanted
            return true

        case .masterRatio(let value, let relative):
            return setRatio(relative ? ratio + value : value)

        case .masterOrientation(let wanted):
            let next = wanted ?? orientation.next
            guard next != orientation else { return false }
            orientation = next
            return true

        default:
            return false
        }
    }
}
