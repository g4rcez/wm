import CoreGraphics

/// The side of `frame` that `point` is nearest to, measured along the diagonals of the frame (Hyprland's `smart_split`).
public func smartSplitSide(of frame: CGRect, at point: CGPoint) -> Direction {
    let dx = (point.x - frame.midX) / max(frame.width / 2, 1)
    let dy = (point.y - frame.midY) / max(frame.height / 2, 1)
    if abs(dx) > abs(dy) { return dx < 0 ? .left : .right }
    return dy < 0 ? .up : .down
}

/// The window whose frame contains `point`. Frames that share an edge both contain it; the lowest id wins, so the answer
/// does not depend on the order of a dictionary.
public func windowUnder(_ point: CGPoint, in frames: [WindowID: CGRect]) -> WindowID? {
    frames.filter { $0.value.contains(point) }.keys.min()
}

/// The `tiling` layout. Hyprland-style dwindle: a binary tree whose leaves are windows.
public struct DwindleEngine: LayoutEngine {
    private var root: Node?
    /// The part of the tiling area that the windows fill, as fractions (`layout tile center`). `nil`: the whole area.
    private var frame: CGRect?
    private let splitRatio: Double
    private let preserveSplit: Bool
    private let newWindowFirst: Bool
    private let widthMultiplier: Double
    /// The side that the next new window takes (set by `preselect`; used once, not saved).
    private var preselected: Direction?

    public init(settings: Settings) {
        splitRatio = min(max(settings.tiling.splitRatio, 0.1), 0.9)
        preserveSplit = settings.tiling.preserveSplit
        newWindowFirst = settings.tiling.forceSplit == .first
        widthMultiplier = min(max(settings.tiling.splitWidthMultiplier, 0.1), 3)
    }

    /// The split tree, for saving. Settings are not part of it: they come from the config.
    public struct State: Codable, Sendable {
        fileprivate var root: Node?
        /// The frame of `layout tile center`; missing in a state that an older version saved.
        fileprivate var area: CGRect?
    }

    public init(settings: Settings, state: State) {
        self.init(settings: settings)
        root = state.root
        frame = state.area
    }

    public var state: LayoutState { .tiling(State(root: root, area: frame)) }

    /// The area that the tree fills: the tiling area, or the part of it that the frame names.
    private func region(in context: LayoutContext) -> CGRect {
        let whole = context.gaps.tilingArea(context.viewport)
        guard let frame else { return whole }
        return CGRect(
            x: whole.minX + frame.minX * whole.width, y: whole.minY + frame.minY * whole.height,
            width: frame.width * whole.width, height: frame.height * whole.height)
    }

    public func templateError(_ template: SplitTemplate, focused: WindowID?) -> String? {
        // A frame keeps the windows as they are, so any number of them is fine.
        if template.isFrame { return nil }
        let count = windows.count
        return count == template.count ? nil : "tile needs exactly \(template.count) windows in this layout (the workspace has \(count))"
    }

    public var windows: [WindowID] { root?.windows ?? [] }

    /// The side that the next new window takes, when `preselect` set one.
    public var preselection: Direction? { preselected }

    public mutating func insert(_ window: WindowID, after anchor: WindowID?) {
        guard let current = root else {
            root = .leaf(window)
            return
        }
        let all = current.windows
        guard !all.contains(window) else { return }
        let target = anchor.flatMap { all.contains($0) ? $0 : nil } ?? all[all.count - 1]
        // A preselected side decides the direction and the side, once; else `force_split` decides the side.
        let side = preselected
        preselected = nil
        let placement = Placement(
            newFirst: side.map { $0 == .left || $0 == .up } ?? newWindowFirst,
            orientation: side.map { $0.isHorizontal ? .horizontal : .vertical }
        )
        root = current.inserting(window, at: target, ratio: splitRatio, placement: placement)
    }

    public mutating func remove(_ window: WindowID) {
        root = root?.removing(window)
    }

    public mutating func frames(in context: LayoutContext, focused: WindowID?) -> [WindowID: CGRect] {
        var cells: [WindowID: CGRect] = [:]
        let area = region(in: context)
        root?.layout(in: area, preserve: preserveSplit, widthMultiplier: widthMultiplier, into: &cells)
        return cells.mapValues { context.gaps.tile($0) }
    }

    public mutating func relabel(_ mapping: [WindowID: WindowID]) {
        root = root?.relabeling(mapping)
    }

    public mutating func perform(_ command: LayoutCommand, focused: WindowID?, in context: LayoutContext) -> Bool {
        if command == .balance { return root?.balance() ?? false }
        if case .applyTemplate(let template) = command {
            // A template also sets the frame, so a grid after `center` fills the whole area again.
            let area: CGRect? = template.area == SplitTemplate.unit ? nil : template.area
            if template.isFrame {
                frame = area
                return true
            }
            let order = windows
            guard templateError(template, focused: focused) == nil,
                  let tree = Node.partition(Array(zip(template.cells, order)), in: CGRect(x: 0, y: 0, width: 1, height: 1)) else { return false }
            root = tree
            frame = area
            return true
        }
        if command == .releaseTemplate {
            let hadFrame = frame != nil
            frame = nil
            let order = windows
            guard order.count > 1 else { return hadFrame }
            root = nil
            var previous: WindowID?
            for window in order {
                insert(window, after: previous)
                previous = window
            }
            return true
        }
        if command == .rotateLayout {
            guard windows.count > 1 else { return false }
            // Orientations must be resolved before they can be flipped.
            _ = frames(in: context, focused: focused)
            root?.flipSplits()
            return true
        }
        if case .rotate(let clockwise) = command {
            guard windows.count > 1 else { return false }
            let ring = clockwiseRing(frames(in: context, focused: focused))
            relabel(rotation(of: ring, clockwise: clockwise))
            return true
        }
        if case .preselect(let side) = command {
            preselected = side
            return true
        }
        guard let focused, root?.contains(focused) == true else { return false }

        switch command {
        case .splitRatio(let value, let relative):
            return root?.updateParent(of: focused) { split, isSecond in
                let share = isSecond ? 1 - split.ratio : split.ratio
                let clamped = min(max(relative ? share + value : value, 0.1), 0.9)
                guard abs(clamped - share) > 1e-9 else { return false }
                split.ratio = isSecond ? 1 - clamped : clamped
                return true
            } ?? false

        case .moveToRoot:
            // Orientations must be resolved before the root can keep its direction.
            _ = frames(in: context, focused: focused)
            guard let moved = root?.movedToRoot(focused) else { return false }
            root = moved
            return true

        case .move(let direction):
            guard let other = neighbor(of: focused, direction, wrap: false, in: context) else { return false }
            root = root?.swapping(focused, other)
            return true

        case .resize(let dimension, let points):
            // Orientations must be resolved before the ancestors can be matched by axis.
            _ = frames(in: context, focused: focused)
            let accept: (Orientation) -> Bool = switch dimension {
            case .width: { $0 == .horizontal }
            case .height: { $0 == .vertical }
            case .smart: { _ in true }
            }
            let area = region(in: context)
            return root?.resize(focused, in: area, accept: accept, points: points) ?? false

        case .resizeEdge(let direction, let points):
            guard points != 0 else { return false }
            // Orientations must be resolved before the ancestors can be matched by axis.
            _ = frames(in: context, focused: focused)
            let area = region(in: context)
            return root?.resizeEdge(focused, in: area, direction: direction, points: points) ?? false

        case .toggleSplit:
            _ = frames(in: context, focused: focused)
            return root?.updateParent(of: focused) { split, _ in
                split.orientation = split.orientation == .horizontal ? .vertical : .horizontal
                split.pinned = true
                return true
            } ?? false

        case .swapSplit:
            return root?.updateParent(of: focused) { split, _ in
                swap(&split.first, &split.second)
                return true
            } ?? false

        default:
            return false
        }
    }
}

extension DwindleEngine {
    /// `true` when the cells (fractions of the unit square) can be cut into a split tree with straight cuts.
    static func canPartition(_ cells: [CGRect]) -> Bool {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        return Node.partition(cells.enumerated().map { (rect: $0.element, window: WindowID($0.offset)) }, in: unit) != nil
    }
}

/// `.horizontal` puts the two children side by side, `.vertical` stacks them.
private struct Split: Sendable, Codable {
    /// `nil` until the first layout decides it.
    var orientation: Orientation?
    /// Set by `toggleSplit`: the orientation then stays even when `preserveSplit` is off.
    var pinned = false
    /// Share of the cell that `first` gets.
    var ratio: Double
    var first: Node
    var second: Node

    func cells(in cell: CGRect) -> (CGRect, CGRect) {
        if orientation == .horizontal {
            let width = cell.width * ratio
            return (
                CGRect(x: cell.minX, y: cell.minY, width: width, height: cell.height),
                CGRect(x: cell.minX + width, y: cell.minY, width: cell.width - width, height: cell.height)
            )
        }
        let height = cell.height * ratio
        return (
            CGRect(x: cell.minX, y: cell.minY, width: cell.width, height: height),
            CGRect(x: cell.minX, y: cell.minY + height, width: cell.width, height: cell.height - height)
        )
    }
}

/// Where a new window goes when it splits a window: on the first or the second side, with a forced direction or not.
private struct Placement {
    var newFirst: Bool
    var orientation: Orientation?
}

private indirect enum Node: Sendable, Codable {
    case leaf(WindowID)
    case split(Split)

    var windows: [WindowID] {
        switch self {
        case .leaf(let window): [window]
        case .split(let split): split.first.windows + split.second.windows
        }
    }

    func contains(_ window: WindowID) -> Bool { windows.contains(window) }

    /// The tree for windows in cells that partition `region` with cuts through the whole region (every pattern of
    /// `SplitTemplate` does). Rows are cut first, then columns. Every split keeps its direction. `nil` when the cells
    /// cannot be cut that way.
    static func partition(_ cells: [(rect: CGRect, window: WindowID)], in region: CGRect) -> Node? {
        guard cells.count > 1 else { return cells.first.map { .leaf($0.window) } }
        let eps = 1e-9
        for orientation in [Orientation.vertical, .horizontal] {
            let stacked = orientation == .vertical
            let start = stacked ? region.minY : region.minX
            let size = stacked ? region.height : region.width
            for cut in cells.map({ stacked ? $0.rect.maxY : $0.rect.maxX }).sorted() where cut < start + size - eps {
                let low = cells.filter { (stacked ? $0.rect.maxY : $0.rect.maxX) <= cut + eps }
                let high = cells.filter { (stacked ? $0.rect.minY : $0.rect.minX) >= cut - eps }
                guard !low.isEmpty, low.count + high.count == cells.count else { continue }
                let lowRegion = stacked
                    ? CGRect(x: region.minX, y: region.minY, width: region.width, height: cut - start)
                    : CGRect(x: region.minX, y: region.minY, width: cut - start, height: region.height)
                let highRegion = stacked
                    ? CGRect(x: region.minX, y: cut, width: region.width, height: region.maxY - cut)
                    : CGRect(x: cut, y: region.minY, width: region.maxX - cut, height: region.height)
                guard let first = partition(low, in: lowRegion), let second = partition(high, in: highRegion) else { return nil }
                return .split(Split(orientation: orientation, pinned: true, ratio: Double((cut - start) / size), first: first, second: second))
            }
        }
        return nil
    }

    /// Every split switches between side by side and stacked, and keeps that direction from now on.
    mutating func flipSplits() {
        guard case .split(var split) = self else { return }
        split.orientation = split.orientation == .horizontal ? .vertical : .horizontal
        split.pinned = true
        split.first.flipSplits()
        split.second.flipSplits()
        self = .split(split)
    }

    func inserting(_ window: WindowID, at target: WindowID, ratio: Double, placement: Placement) -> Node {
        switch self {
        case .leaf(let existing):
            guard existing == target else { return self }
            // `ratio` is the share that the window that was there keeps.
            let pinned = placement.orientation != nil
            return placement.newFirst
                ? .split(Split(orientation: placement.orientation, pinned: pinned, ratio: 1 - ratio, first: .leaf(window), second: self))
                : .split(Split(orientation: placement.orientation, pinned: pinned, ratio: ratio, first: self, second: .leaf(window)))
        case .split(var split):
            split.first = split.first.inserting(window, at: target, ratio: ratio, placement: placement)
            split.second = split.second.inserting(window, at: target, ratio: ratio, placement: placement)
            return .split(split)
        }
    }

    /// The window becomes a direct child of this root split and keeps its side; the rest of the tree is the other child.
    /// `nil` when it already is a direct child (or when this is not a split).
    func movedToRoot(_ window: WindowID) -> Node? {
        guard case .split(let split) = self else { return nil }
        if case .leaf(window) = split.first { return nil }
        if case .leaf(window) = split.second { return nil }
        guard let rest = removing(window) else { return nil }
        let inFirst = split.first.contains(window)
        return .split(Split(
            orientation: split.orientation, pinned: true, ratio: 0.5,
            first: inFirst ? .leaf(window) : rest, second: inFirst ? rest : .leaf(window)))
    }

    /// The sibling of the removed leaf takes the place of its parent.
    func removing(_ window: WindowID) -> Node? {
        switch self {
        case .leaf(let existing):
            return existing == window ? nil : self
        case .split(var split):
            guard let first = split.first.removing(window) else { return split.second }
            guard let second = split.second.removing(window) else { return first }
            split.first = first
            split.second = second
            return .split(split)
        }
    }

    func swapping(_ a: WindowID, _ b: WindowID) -> Node {
        mappingLeaves { $0 == a ? b : $0 == b ? a : $0 }
    }

    func relabeling(_ mapping: [WindowID: WindowID]) -> Node {
        mappingLeaves { mapping[$0] ?? $0 }
    }

    /// The same tree with every window replaced by `transform(window)`.
    private func mappingLeaves(_ transform: (WindowID) -> WindowID) -> Node {
        switch self {
        case .leaf(let window): return .leaf(transform(window))
        case .split(var split):
            split.first = split.first.mappingLeaves(transform)
            split.second = split.second.mappingLeaves(transform)
            return .split(split)
        }
    }

    /// Resolves unresolved orientations from the aspect ratio of the cell, and fills `cells`.
    mutating func layout(in cell: CGRect, preserve: Bool, widthMultiplier: Double, into cells: inout [WindowID: CGRect]) {
        switch self {
        case .leaf(let window):
            cells[window] = cell
        case .split(var split):
            if split.orientation == nil || !(preserve || split.pinned) {
                split.orientation = cell.width * CGFloat(widthMultiplier) > cell.height ? .horizontal : .vertical
            }
            let (firstCell, secondCell) = split.cells(in: cell)
            split.first.layout(in: firstCell, preserve: preserve, widthMultiplier: widthMultiplier, into: &cells)
            split.second.layout(in: secondCell, preserve: preserve, widthMultiplier: widthMultiplier, into: &cells)
            self = .split(split)
        }
    }

    /// Gives every leaf the same size. Returns `true` when a ratio changed.
    mutating func balance() -> Bool {
        guard case .split(var split) = self else { return false }
        let target = Double(split.first.windows.count) / Double(windows.count)
        var changed = split.ratio != target
        split.ratio = target
        let first = split.first.balance()
        let second = split.second.balance()
        changed = changed || first || second
        self = .split(split)
        return changed
    }

    /// Runs `body` on the split that directly holds `window` (`isSecond` tells which side).
    mutating func updateParent(of window: WindowID, _ body: (inout Split, _ isSecond: Bool) -> Bool) -> Bool {
        guard case .split(var split) = self else { return false }
        let changed: Bool
        if case .leaf(window) = split.first {
            changed = body(&split, false)
        } else if case .leaf(window) = split.second {
            changed = body(&split, true)
        } else if split.first.contains(window) {
            changed = split.first.updateParent(of: window, body)
        } else {
            changed = split.second.updateParent(of: window, body)
        }
        self = .split(split)
        return changed
    }

    /// Changes the ratio of the nearest ancestor of `window` that `accept` allows. `points` is the growth of
    /// the window; the ratio changes by `points` divided by the ancestor cell size.
    mutating func resize(_ window: WindowID, in cell: CGRect, accept: (Orientation) -> Bool, points: CGFloat) -> Bool? {
        moveDivider(of: window, in: cell, points: points) { orientation, _ in accept(orientation) }
    }

    /// Moves the divider on the `direction` side of `window`: the nearest ancestor split on that axis where the window
    /// lies on the matching side (first child for right/down, second child for left/up). Returns `nil` when there
    /// is no such divider.
    mutating func resizeEdge(_ window: WindowID, in cell: CGRect, direction: Direction, points: CGFloat) -> Bool? {
        moveDivider(of: window, in: cell, points: points) { orientation, inSecond in
            (orientation == .horizontal) == direction.isHorizontal && inSecond == (direction == .left || direction == .up)
        }
    }

    /// Moves the divider of the nearest ancestor split of `window` that `accepts` (given its orientation and whether
    /// `window` lies in its second child). `nil` when no ancestor does; else whether the ratio changed.
    private mutating func moveDivider(
        of window: WindowID, in cell: CGRect, points: CGFloat, accepts: (Orientation, _ inSecond: Bool) -> Bool
    ) -> Bool? {
        guard case .split(var split) = self, contains(window) else { return nil }
        let (firstCell, secondCell) = split.cells(in: cell)
        let inSecond = split.second.contains(window)
        var result = inSecond
            ? split.second.moveDivider(of: window, in: secondCell, points: points, accepts: accepts)
            : split.first.moveDivider(of: window, in: firstCell, points: points, accepts: accepts)
        if result == nil, let orientation = split.orientation, accepts(orientation, inSecond) {
            let size = orientation == .horizontal ? cell.width : cell.height
            if size > 0 {
                let share = Double(points / size)
                let ratio = min(max(split.ratio + (inSecond ? -share : share), 0.1), 0.9)
                result = ratio != split.ratio
                split.ratio = ratio
            }
        }
        self = .split(split)
        return result
    }
}
