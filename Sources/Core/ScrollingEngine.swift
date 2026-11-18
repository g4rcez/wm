// Semantics ported from paneru (MIT, github.com/karinushka/paneru)
import CoreGraphics
import Foundation

/// A horizontal strip of columns (niri / PaperWM style) and, optionally, a vertical strip of rows in a zone at one
/// side of the screen. The screen shows a window onto each strip.
///
/// With only one strip in use, that strip fills `gaps.tilingArea(viewport)`. With both, the area is split into two
/// zones (the vertical zone is `verticalWidth` of the area wide, on `settings.scrolling.vertical.side`). A lane
/// (a column or a row) has a `size` that is a fraction of its zone along the strip axis. The lanes lie edge to edge.
/// Each window cell goes through `gaps.tile(_:)`.
public struct ScrollingEngine: LayoutEngine {
    private static let minVerticalWidth = 0.1
    private static let maxVerticalWidth = 0.9

    private let settings: Settings
    private var horizontal = Strip(axis: .horizontal)
    private var vertical = Strip(axis: .vertical)

    /// Width of the vertical zone as a fraction of the tiling area. Starts at the setting; a mouse resize changes it.
    public private(set) var verticalWidth: Double

    /// Strip x of the left edge of the horizontal zone.
    public var scrollOffset: CGFloat { horizontal.scrollOffset }
    /// Strip y of the top edge of the vertical zone.
    public var verticalScrollOffset: CGFloat { vertical.scrollOffset }

    public init(settings: Settings) {
        self.settings = settings
        verticalWidth = Self.clampedVerticalWidth(settings.scrolling.vertical.width)
        applyStripSettings()
    }

    /// The strips take the settings that they cannot keep in their saved state.
    private mutating func applyStripSettings() {
        horizontal.centersSingleLane = settings.scrolling.alwaysCenterSingleColumn
        horizontal.fillsSingleLane = settings.scrolling.singleWindowFit == .fill
        horizontal.visibleLanes = settings.scrolling.visibleColumns
        vertical.centersSingleLane = settings.scrolling.alwaysCenterSingleColumn
    }

    /// A new engine with the lanes, sizes, offsets and `verticalWidth` of `previous`, and the new settings for what
    /// is inserted later. A config reload uses this.
    public init(settings: Settings, keeping previous: ScrollingEngine) {
        self.init(settings: settings, state: previous.savedState)
    }

    /// Lanes, sizes, scroll offsets and the vertical zone width, for saving. A pending manual scroll (`hold`) is not
    /// part of it.
    public struct State: Codable, Sendable {
        var horizontal: Strip
        var vertical: Strip
        var verticalWidth: Double
    }

    private var savedState: State { State(horizontal: horizontal, vertical: vertical, verticalWidth: verticalWidth) }

    public var state: LayoutState { .scrolling(savedState) }

    public init(settings: Settings, state: State) {
        self.settings = settings
        horizontal = state.horizontal
        vertical = state.vertical
        verticalWidth = Self.clampedVerticalWidth(state.verticalWidth)
        applyStripSettings()
    }

    private static func clampedVerticalWidth(_ fraction: Double) -> Double {
        min(max(fraction, minVerticalWidth), maxVerticalWidth)
    }

    /// The horizontal lanes' windows, then the vertical lanes' windows.
    public var windows: [WindowID] { horizontal.windows + vertical.windows }

    /// The strip that holds the window.
    public func strip(of window: WindowID) -> Orientation? { locate(window)?.strip }

    /// The windows of every lane of a strip, in order: the columns of the horizontal strip, the rows of the vertical one.
    public func lanes(of orientation: Orientation) -> [[WindowID]] {
        self[strip: orientation].lanes.map(\.windows)
    }

    /// The size of the window's column as a fraction of its zone. A maximized column reports the size it will go back to.
    public func columnSize(of window: WindowID) -> Double? {
        locate(window).map { at in
            let lane = self[strip: at.strip].lanes[at.lane]
            return lane.zoom?.size ?? lane.size
        }
    }

    /// The template of the block that holds the window, if any.
    public func template(of window: WindowID) -> SplitTemplate? {
        locate(window).flatMap { self[strip: $0.strip].lanes[$0.lane].template }
    }

    /// Whether `maximize` made the window's column fill the zone.
    public func isMaximized(_ window: WindowID) -> Bool {
        locate(window).map { self[strip: $0.strip].lanes[$0.lane].zoom != nil } ?? false
    }

    /// Why `template` cannot be applied around `focused`, or `nil` when it can.
    public func templateError(_ template: SplitTemplate, focused: WindowID?) -> String? {
        guard !template.isFrame else { return "this template is for the tiling layout" }
        guard let focused, locate(focused)?.strip == .horizontal else {
            return "tile works on a window of the horizontal strip"
        }
        let count = horizontal.windows.count
        if count < template.count { return "need at least \(template.count) windows in the strip (it has \(count))" }
        let at = horizontal.locate(focused)!
        if horizontal.lanes[at.lane].template != nil { return nil }
        return horizontal.group(count: template.count, around: at.lane) == nil
            ? "need whole columns with \(template.count) windows together around this window (a stack or a tab group is never split)" : nil
    }

    // MARK: Membership

    private subscript(strip orientation: Orientation) -> Strip {
        get { orientation == .horizontal ? horizontal : vertical }
        set { if orientation == .horizontal { horizontal = newValue } else { vertical = newValue } }
    }

    private func locate(_ window: WindowID) -> (strip: Orientation, lane: Int, index: Int)? {
        if let at = horizontal.locate(window) { return (.horizontal, at.lane, at.index) }
        if let at = vertical.locate(window) { return (.vertical, at.lane, at.index) }
        return nil
    }

    private func defaultSize(of orientation: Orientation) -> Double {
        Strip.clampedSize(orientation == .horizontal ? settings.scrolling.defaultWidth : settings.scrolling.vertical.rowHeight)
    }

    private var newLaneTabbed: Bool { settings.scrolling.defaultColumnDisplay == .tabbed }

    /// The window tabs of its column: all windows of the column, when it shows tabs and has more than one. The
    /// column's windows share one frame, and the focused one is on top.
    public func tabs(of window: WindowID) -> [WindowID]? {
        guard let at = locate(window) else { return nil }
        let lane = self[strip: at.strip].lanes[at.lane]
        return lane.tabbed && lane.windows.count > 1 && lane.zoom == nil ? lane.windows : nil
    }

    public mutating func insert(_ window: WindowID, after anchor: WindowID?) {
        guard locate(window) == nil else { return }
        if let anchor, let at = locate(anchor) {
            let lane = Lane(windows: [window], size: defaultSize(of: at.strip), tabbed: newLaneTabbed)
            self[strip: at.strip].lanes.insert(lane, at: at.lane + 1)
        } else {
            horizontal.lanes.append(Lane(windows: [window], size: defaultSize(of: .horizontal), tabbed: newLaneTabbed))
        }
    }

    public mutating func remove(_ window: WindowID) {
        guard let at = locate(window) else { return }
        // A template needs all its windows; the others go back to single columns.
        self[strip: at.strip].dissolve(lane: at.lane, size: defaultSize(of: at.strip))
        let moved = locate(window)!
        self[strip: moved.strip].remove(window, at: (moved.lane, moved.index))
    }

    public mutating func relabel(_ mapping: [WindowID: WindowID]) {
        horizontal.relabel(mapping)
        vertical.relabel(mapping)
    }

    // MARK: Zones

    private var usesBothStrips: Bool { !horizontal.lanes.isEmpty && !vertical.lanes.isEmpty }

    private var verticalOnLeft: Bool { settings.scrolling.vertical.side == .left }

    /// The cell of a strip: the whole tiling area, or one of the two halves of it when both strips have windows.
    private func zoneRect(of orientation: Orientation, in context: LayoutContext) -> CGRect {
        let area = context.gaps.tilingArea(context.viewport)
        guard usesBothStrips else { return area }
        let width = CGFloat(verticalWidth) * area.width
        var left = area, right = area
        if verticalOnLeft {
            left.size.width = width
            right.origin.x += width
            right.size.width -= width
            return orientation == .vertical ? left : right
        }
        right.origin.x = area.maxX - width
        right.size.width = width
        left.size.width -= width
        return orientation == .vertical ? right : left
    }

    /// The direction from a strip toward the other zone, or `nil` when the other strip is empty.
    private func boundary(of orientation: Orientation) -> Direction? {
        guard usesBothStrips else { return nil }
        let side: Direction = verticalOnLeft ? .left : .right
        return orientation == .horizontal ? side : side.opposite
    }

    // MARK: Commands

    /// The strip runs down the screen: the engine then works in a space with x and y swapped, and swaps the results back.
    /// Only the entry points know about this; everything below them thinks in columns.
    /// Whether the main strip runs down this screen (see `scrolling.orientation`).
    public func runsVertically(in context: LayoutContext) -> Bool {
        switch settings.scrolling.orientation {
        case .horizontal: false
        case .vertical: true
        case .auto: context.viewport.height > context.viewport.width
        }
    }

    /// The screen axis along which the strip of the window scrolls: sideways for a column strip on a normal screen, up
    /// and down for the same strip on a portrait monitor. `nil` when the window is not in the layout.
    public func screenAxis(of window: WindowID, in context: LayoutContext) -> Orientation? {
        strip(of: window).map { runsVertically(in: context) ? $0.transposed : $0 }
    }

    public mutating func perform(_ command: LayoutCommand, focused: WindowID?, in context: LayoutContext) -> Bool {
        guard runsVertically(in: context) else { return run(command, focused: focused, in: context) }
        return run(command.transposed, focused: focused, in: context.transposed)
    }

    private mutating func run(_ command: LayoutCommand, focused: WindowID?, in context: LayoutContext) -> Bool {
        switch command {
        case .toggleSplit, .swapSplit:
            return false
        case .scroll(let delta):
            let orientation = focused.flatMap { locate($0)?.strip } ?? (horizontal.lanes.isEmpty ? .vertical : .horizontal)
            guard !self[strip: orientation].lanes.isEmpty else { return false }
            let length = zoneRect(of: orientation, in: context).length(along: orientation)
            let before = self[strip: orientation].scrollOffset
            self[strip: orientation].scrollOffset = self[strip: orientation].clamped(before + delta, length: length)
            self[strip: orientation].hold = Hold(kind: .manual, focus: focused)
            let other = orientation.transposed
            if self[strip: other].hold?.kind == .manual { self[strip: other].hold = nil }
            return self[strip: orientation].scrollOffset != before
        default:
            break
        }

        // Every other command ends a manual scroll or a one-shot centring.
        horizontal.hold = nil
        vertical.hold = nil

        if case .rotate(let clockwise) = command {
            // The ring follows the structure: columns left to right (a stack top to bottom), then rows top to bottom.
            let ring = windows
            guard ring.count > 1 else { return false }
            relabel(rotation(of: ring, clockwise: clockwise))
            return true
        }

        guard let focused, let at = locate(focused) else { return false }
        let strip = at.strip
        let here: Strip.Location = (at.lane, at.index)
        let zone = zoneRect(of: strip, in: context)
        let area = context.gaps.tilingArea(context.viewport)
        let length = zone.length(along: strip)

        switch command {
        case .move(let direction):
            if self[strip: strip].move(here, direction) { return true }
            // At the end of the strip, moving toward the other zone sends the window across.
            if direction == boundary(of: strip) { return send(focused, to: strip.transposed, in: context) }
            return false

        case .sendToStrip(let target):
            return send(focused, to: target, in: context)

        case .resize(let dimension, let delta):
            // `.width` of a row sets the width of the whole vertical zone.
            if strip == .vertical, dimension == .width {
                return resizeVerticalZone(by: delta, in: area)
            }
            let alongAxis = dimension == .smart || (dimension == .width) == (strip == .horizontal)
            if alongAxis {
                return resizeLane(here.lane, of: strip, by: delta, length: length)
            }
            return self[strip: strip].resizeCross(here, by: Double(delta / zone.length(along: strip.transposed)))

        case .resizeEdge(let direction, let delta):
            guard delta != 0 else { return false }
            if self[strip: strip].isMain(direction) {
                // A lane has no neighbour to trade size with: dragging either end outward grows it.
                return resizeLane(here.lane, of: strip, by: delta, length: length)
            }
            let neighbour = here.index + Strip.step(direction)
            if self[strip: strip].lanes[here.lane].windows.indices.contains(neighbour) {
                return self[strip: strip].resizeCross(
                    here, by: Double(delta / zone.length(along: strip.transposed)), neighbour: neighbour)
            }
            // The side of a row that faces the horizontal zone is its divider.
            if strip == .vertical, direction == boundary(of: .vertical) {
                return resizeVerticalZone(by: delta, in: area)
            }
            return false

        case .balance:
            return self[strip: strip].fit()

        case .expandColumn:
            return self[strip: strip].expand(lane: here.lane, length: length)

        case .matchWidth:
            return self[strip: strip].matchSize(of: here.lane)

        case .equalizeStack:
            return self[strip: strip].equalize(lane: here.lane)

        case .columnWidth(.fraction(let fraction)):
            return self[strip: strip].setSize(of: here.lane, to: fraction)

        case .columnWidth(.cycle):
            return self[strip: strip].cycleSize(of: here.lane, presets: settings.scrolling.presets)

        case .stack(let direction):
            return self[strip: strip].stack(focused, at: here, toward: direction)

        case .unstack(let direction):
            return self[strip: strip].unstack(focused, at: here, size: defaultSize(of: strip), tabbed: newLaneTabbed, toward: direction)

        case .moveColumn(let index):
            return self[strip: strip].moveLane(here.lane, to: index)

        case .toggleTabs:
            guard self[strip: strip].lanes[here.lane].template == nil else { return false }
            self[strip: strip].lanes[here.lane].tabbed.toggle()
            return true

        case .applyTemplate(let template):
            guard strip == .horizontal else { return false }
            return self[strip: strip].apply(template, focused: focused, size: defaultSize(of: strip))

        case .releaseTemplate:
            guard self[strip: strip].lanes[here.lane].template != nil else { return false }
            self[strip: strip].dissolve(lane: here.lane, size: defaultSize(of: strip))
            return true

        case .maximize:
            return self[strip: strip].toggleMaximize(lane: here.lane)

        case .center:
            let before = self[strip: strip].scrollOffset
            self[strip: strip].scrollOffset = self[strip: strip].centeredOffset(of: here.lane, length: length)
            self[strip: strip].hold = Hold(kind: .centered, focus: focused)
            return self[strip: strip].scrollOffset != before

        case .centerVisible:
            let before = self[strip: strip].scrollOffset
            guard let offset = self[strip: strip].visibleBlockOffset(length: length) else { return false }
            self[strip: strip].scrollOffset = offset
            self[strip: strip].hold = Hold(kind: .centered, focus: focused)
            return self[strip: strip].scrollOffset != before

        case .windowHeight(.fraction(let fraction)):
            return self[strip: strip].setCrossFraction(here, to: fraction)

        case .windowHeight(.cycle):
            return self[strip: strip].cycleCrossFraction(here, presets: settings.scrolling.presetHeights)

        default:
            return false
        }
    }

    private mutating func resizeLane(_ lane: Int, of strip: Orientation, by delta: CGFloat, length: CGFloat) -> Bool {
        let current = self[strip: strip]
        // A lone lane that fills the zone starts from its shown size, not from the stored one.
        let stored = current.fillsLone(lane) ? Strip.maxSize : current.lanes[lane].size
        guard current.fillScale != 1 else { return self[strip: strip].setSize(of: lane, to: stored + Double(delta / length)) }
        // With `visible_columns` a lane is shown larger than it is stored. Find the stored size that shows the lane
        // `delta` larger, so the edge follows the mouse: shown = stored / (stored + others).
        let others = current.lanes.enumerated().reduce(0.0) { $1.offset == lane ? $0 : $0 + $1.element.size }
        let shown = min(max(stored * current.fillScale + Double(delta / length), 0.05), 0.95)
        return self[strip: strip].setSize(of: lane, to: shown * others / (1 - shown))
    }

    /// Changes the width of the vertical zone. Needs a horizontal zone to trade width with.
    private mutating func resizeVerticalZone(by delta: CGFloat, in area: CGRect) -> Bool {
        guard usesBothStrips else { return false }
        let value = Self.clampedVerticalWidth(verticalWidth + Double(delta / area.width))
        guard abs(value - verticalWidth) > 1e-9 else { return false }
        verticalWidth = value
        return true
    }

    /// Moves the window into a new lane of the strip `target`, after that strip's most visible lane.
    private mutating func send(_ window: WindowID, to target: Orientation, in context: LayoutContext) -> Bool {
        guard let at = locate(window), at.strip != target else { return false }
        self[strip: at.strip].remove(window, at: (at.lane, at.index))
        horizontal.hold = nil
        vertical.hold = nil
        let length = zoneRect(of: target, in: context).length(along: target)
        let index = self[strip: target].mostVisibleLane(length: length).map { $0 + 1 } ?? 0
        self[strip: target].lanes.insert(Lane(windows: [window], size: defaultSize(of: target), tabbed: newLaneTabbed), at: index)
        return true
    }

    // MARK: Scrolling

    /// Ends a manual scroll. Returns the first window of the lane nearest the centre of its zone, so the caller can
    /// focus it. The strip is moved to show that lane. Returns `nil` when no manual scroll is active.
    public mutating func settle(in context: LayoutContext) -> WindowID? {
        let context = runsVertically(in: context) ? context.transposed : context
        var result: WindowID?
        for orientation in [Orientation.horizontal, .vertical] {
            let length = zoneRect(of: orientation, in: context).length(along: orientation)
            let settled = self[strip: orientation].settle(length: length, center: settings.scrolling.center)
            result = result ?? settled
        }
        return result
    }

    // MARK: Layout

    /// A window cell before parking.
    private struct Placement {
        var window: WindowID
        var lane: Int
        var cell: CGRect
        /// The lane lies completely before the start of its zone, or completely after the end.
        var before: Bool
        var after: Bool
    }

    /// The only axis-specific geometry: (main, cross) coordinates to a rectangle.
    private static func rect(_ axis: Orientation, main: CGFloat, mainSize: CGFloat, cross: CGFloat, crossSize: CGFloat) -> CGRect {
        axis == .horizontal
            ? CGRect(x: main, y: cross, width: mainSize, height: crossSize)
            : CGRect(x: cross, y: main, width: crossSize, height: mainSize)
    }

    private func placements(of orientation: Orientation, zone: CGRect, offset: CGFloat) -> [Placement] {
        let strip = self[strip: orientation]
        let tolerance = Strip.tolerance
        let mainStart = zone.start(orientation), mainLength = zone.length(along: orientation)
        let crossStart = zone.start(orientation.transposed), crossLength = zone.length(along: orientation.transposed)

        var result: [Placement] = []
        var position: CGFloat = 0
        let sizes = strip.displaySizes()
        for (index, lane) in strip.lanes.enumerated() {
            let size = CGFloat(sizes[index]) * mainLength
            let main = mainStart + position - offset
            position += size
            let before = main + size <= mainStart + tolerance
            let after = main >= mainStart + mainLength - tolerance

            if let template = lane.template {
                // Only the horizontal strip has templates: each cell is a fraction of the lane's width and the zone's height.
                for (cell, window) in zip(template.cells, lane.windows) {
                    let rect = CGRect(
                        x: main + cell.minX * size, y: crossStart + cell.minY * crossLength,
                        width: cell.width * size, height: cell.height * crossLength)
                    result.append(Placement(window: window, lane: index, cell: rect, before: before, after: after))
                }
                continue
            }
            var cross = crossStart
            let fractions = lane.crossFractions()
            for (slot, window) in lane.windows.enumerated() {
                let crossSize = lane.tabbed ? crossLength : crossLength * CGFloat(fractions[slot])
                let start = lane.tabbed ? crossStart : cross
                cross += crossSize
                let cell = Self.rect(orientation, main: main, mainSize: size, cross: start, crossSize: crossSize)
                result.append(Placement(window: window, lane: index, cell: cell, before: before, after: after))
            }
        }
        return result
    }

    public mutating func frames(in context: LayoutContext, focused: WindowID?) -> [WindowID: CGRect] {
        guard runsVertically(in: context) else { return layout(in: context, focused: focused) }
        return layout(in: context.transposed, focused: focused).mapValues(\.transposed)
    }

    private mutating func layout(in context: LayoutContext, focused: WindowID?) -> [WindowID: CGRect] {
        let center = settings.scrolling.center
        var result: [WindowID: CGRect] = [:]
        for orientation in [Orientation.horizontal, .vertical] {
            let zone = zoneRect(of: orientation, in: context)
            self[strip: orientation].follow(focused: focused, length: zone.length(along: orientation), center: center)
            let strip = self[strip: orientation]
            for placement in placements(of: orientation, zone: zone, offset: strip.scrollOffset) {
                var frame = context.gaps.tile(placement.cell)
                if placement.before || placement.after {
                    frame = parked(frame, lane: strip.lanes[placement.lane], strip: orientation,
                                   before: placement.before, zone: zone, in: context)
                }
                result[placement.window] = frame
            }
        }
        return result
    }

    /// macOS refuses a window that is fully off screen and never puts one above the menu bar. A lane next to the
    /// other zone, above the screen, or at an edge with no room for a sliver goes to the hidden corner. Any other
    /// parked lane keeps a sliver at the screen edge.
    private func parked(_ frame: CGRect, lane: Lane, strip: Orientation, before: Bool, zone: CGRect, in context: LayoutContext) -> CGRect {
        let side: Direction = strip == .horizontal ? (before ? .left : .right) : (before ? .up : .down)
        let nextToOtherZone = strip == .horizontal && boundary(of: .horizontal) == side
        var frame = frame
        guard !nextToOtherZone, context.sliverEdges.contains(side) else {
            frame.origin = context.hiddenCorner ?? CGPoint(x: context.viewport.maxX - 1, y: context.viewport.maxY - 1)
            return frame
        }

        let viewport = context.viewport
        let sliver = settings.scrolling.sliverWidth
        let fraction = CGFloat(settings.scrolling.sliverHeight)
        let isStack = lane.windows.count > 1 && !lane.tabbed
        switch side {
        case .left:
            frame.origin.x = viewport.minX - frame.width + sliver
        case .right:
            frame.origin.x = viewport.maxX - sliver
        default:
            frame.origin.y = viewport.maxY - sliver
        }
        if !isStack {
            // The cross size of a parked lane, centred.
            if strip == .horizontal {
                let height = viewport.height * fraction
                frame.origin.y = viewport.minY + (viewport.height - height) / 2
                frame.size.height = height
            } else {
                let width = zone.width * fraction
                frame.origin.x = zone.minX + (zone.width - width) / 2
                frame.size.width = width
            }
        }
        return frame
    }

    // MARK: Overview

    public func overview(in context: LayoutContext, focused: WindowID?) -> LayoutOverview {
        guard runsVertically(in: context) else { return miniature(in: context, focused: focused) }
        let result = miniature(in: context.transposed, focused: focused)
        return LayoutOverview(frames: result.frames.mapValues(\.transposed), viewports: result.viewports.map(\.transposed))
    }

    private func miniature(in context: LayoutContext, focused: WindowID?) -> LayoutOverview {
        guard !horizontal.lanes.isEmpty || !vertical.lanes.isEmpty else {
            return LayoutOverview(frames: [:], viewports: [context.viewport])
        }
        var copy = self
        var frames: [WindowID: CGRect] = [:]
        var viewports: [CGRect] = []
        let hzone = zoneRect(of: .horizontal, in: context)
        var vzone = zoneRect(of: .vertical, in: context)
        // The horizontal strip may be longer than its zone. The vertical strip starts after its end.
        if usesBothStrips, !verticalOnLeft {
            vzone.origin.x = max(hzone.maxX, hzone.minX + horizontal.totalLength(hzone.width))
        }
        for (orientation, zone) in [(Orientation.horizontal, hzone), (.vertical, vzone)] {
            copy[strip: orientation].follow(
                focused: focused, length: zone.length(along: orientation), center: settings.scrolling.center)
            guard !copy[strip: orientation].lanes.isEmpty else { continue }
            for placement in placements(of: orientation, zone: zone, offset: 0) {
                frames[placement.window] = context.gaps.tile(placement.cell)
            }
            let offset = copy[strip: orientation].scrollOffset
            viewports.append(zone.offsetBy(dx: orientation == .horizontal ? offset : 0, dy: orientation == .vertical ? offset : 0))
        }
        return LayoutOverview(frames: frames, viewports: viewports)
    }

    // MARK: Focus

    public mutating func neighbor(of window: WindowID, _ direction: Direction, wrap: Bool, in context: LayoutContext) -> WindowID? {
        guard runsVertically(in: context) else { return step(from: window, direction, wrap: wrap, in: context) }
        return step(from: window, direction.transposed, wrap: wrap, in: context.transposed)
    }

    private mutating func step(from window: WindowID, _ direction: Direction, wrap: Bool, in context: LayoutContext) -> WindowID? {
        guard let at = locate(window) else { return nil }
        let strip = self[strip: at.strip]
        let step = Strip.step(direction)

        // Inside a template the neighbour is the adjacent cell.
        if let template = strip.lanes[at.lane].template, let cell = template.neighbor(of: at.index, direction) {
            return strip.lanes[at.lane].windows[cell]
        }

        if strip.isMain(direction) {
            let length = zoneRect(of: at.strip, in: context).length(along: at.strip)
            var target = at.lane + step
            // From the last visible lane, the way on leads into the other zone.
            if boundary(of: at.strip) == direction,
               !(strip.lanes.indices.contains(target) && strip.isVisible(target, length: length)) {
                return crossing(from: window, at.strip, in: context)
            }
            if !strip.lanes.indices.contains(target) {
                guard wrap else { return nil }
                target = step < 0 ? strip.lanes.count - 1 : 0
            }
            let stack = strip.lanes[target].windows
            let here = strip.lanes[at.lane]
            let there = strip.lanes[target]
            if here.template != nil || there.template != nil {
                // Keep the height: enter the next lane (or template cell) at the same level.
                let y = here.template.map { $0.cells[at.index].midY } ?? (CGFloat(at.index) + 0.5) / CGFloat(max(here.windows.count, 1))
                if let template = there.template { return stack[template.entryCell(fromLeft: step > 0, nearY: y)] }
                var total = 0.0
                for (index, share) in there.crossFractions().enumerated() {
                    total += share
                    if CGFloat(total) >= y - 1e-9 { return stack[index] }
                }
                return stack[stack.count - 1]
            }
            return stack[min(at.index, stack.count - 1)]
        }

        guard strip.lanes[at.lane].template == nil else { return nil }
        let stack = strip.lanes[at.lane].windows
        var target = at.index + step
        if !stack.indices.contains(target) {
            if boundary(of: at.strip) == direction { return crossing(from: window, at.strip, in: context) }
            guard wrap else { return nil }
            target = step < 0 ? stack.count - 1 : 0
        }
        return stack[target]
    }

    /// The window of the other strip that overlaps the source the most (along the shared edge) on screen. Ties go to
    /// the one nearest the other zone.
    private func crossing(from window: WindowID, _ orientation: Orientation, in context: LayoutContext) -> WindowID? {
        let other = orientation.transposed
        let ownZone = zoneRect(of: orientation, in: context)
        let otherZone = zoneRect(of: other, in: context)
        guard let source = placements(of: orientation, zone: ownZone, offset: self[strip: orientation].scrollOffset)
            .first(where: { $0.window == window })?.cell else { return nil }
        let divider = zoneRect(of: .vertical, in: context)
        let dividerX = verticalOnLeft ? divider.maxX : divider.minX

        func overlap(_ cell: CGRect) -> CGFloat {
            let low = max(cell.minY, source.minY, otherZone.minY, ownZone.minY)
            let high = min(cell.maxY, source.maxY, otherZone.maxY, ownZone.maxY)
            return max(0, high - low)
        }

        var best: (window: WindowID, overlap: CGFloat, distance: CGFloat)?
        for placement in placements(of: other, zone: otherZone, offset: self[strip: other].scrollOffset)
        where !placement.before && !placement.after {
            let candidate = (
                placement.window,
                overlap(placement.cell),
                min(abs(placement.cell.minX - dividerX), abs(placement.cell.maxX - dividerX))
            )
            guard let current = best else { best = candidate; continue }
            if candidate.1 > current.overlap + 0.5
                || (abs(candidate.1 - current.overlap) <= 0.5 && candidate.2 < current.distance - 0.5) {
                best = candidate
            }
        }
        return best?.window
    }
}

private extension CGRect {
    func start(_ axis: Orientation) -> CGFloat { axis == .horizontal ? minX : minY }
    func length(along axis: Orientation) -> CGFloat { axis == .horizontal ? width : height }
}
