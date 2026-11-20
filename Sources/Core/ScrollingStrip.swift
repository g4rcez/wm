import CoreGraphics
import Foundation

extension Orientation {
    var transposed: Orientation { self == .horizontal ? .vertical : .horizontal }
}

extension ScrollingEngine {
    struct Zoom: Equatable, Codable {
        var size: Double
        var tabbed: Bool
    }

    /// One column of the horizontal strip or one row of the vertical strip.
    struct Lane: Equatable, Codable {
        var windows: [WindowID]
        /// Fraction of the zone length along the strip axis.
        var size: Double
        var tabbed = false
        /// The size and tabs that `maximize` replaced. Present while the lane is maximized.
        var zoom: Zoom?
        /// A lane made by a split template: it holds exactly `template.count` windows, each in its own cell, and no
        /// structural command (stack, tabs, cross resize) applies to it.
        var template: SplitTemplate?
        /// The columns that a template block was made from, to give back when the block ends. Optional, so that a saved
        /// state without it still loads.
        var parts: [Lane]?
        /// Relative size of each window along the cross axis. Missing means 1.
        var shares: [WindowID: Double] = [:]
        /// The size was set by a command or a resize. A lone lane that has one keeps it, and does not fill the zone
        /// (`single_window_fit = "fill"`). Optional, so that a saved state without it still loads.
        var userSized: Bool?

        mutating func relabel(_ mapping: [WindowID: WindowID]) {
            windows = windows.map { mapping[$0] ?? $0 }
            shares = Dictionary(uniqueKeysWithValues: shares.map { (mapping[$0.key] ?? $0.key, $0.value) })
            for index in (parts ?? []).indices { parts?[index].relabel(mapping) }
        }

        /// Cross-axis fraction of every window, in lane order. They add up to 1.
        func crossFractions() -> [Double] {
            let values = windows.map { shares[$0] ?? 1 }
            let total = values.reduce(0, +)
            return values.map { $0 / total }
        }
    }

    /// A scroll position that a later `frames` call must not override.
    struct Hold {
        enum Kind { case manual, centered }
        var kind: Kind
        var focus: WindowID?
    }

    /// Lanes along one axis plus the scroll state. `.horizontal`: lanes are columns. `.vertical`: lanes are rows.
    /// Positions here are "main" coordinates: distance along the axis from the start of the strip.
    /// `length` is the length of the zone along the axis.
    struct Strip: Codable {
        private enum CodingKeys: String, CodingKey { case axis, lanes, scrollOffset }

        typealias Location = (lane: Int, index: Int)

        static let minSize = 0.1
        static let maxSize = 1.0
        static let minShare = 0.1
        static let tolerance: CGFloat = 0.01

        var axis: Orientation
        var lanes: [Lane] = []
        var scrollOffset: CGFloat = 0
        var hold: Hold?
        /// A strip with one lane centres it, even when it is shorter than the zone. Set from the settings.
        var centersSingleLane = false
        /// A lone lane fills the zone (`single_window_fit = "fill"`). Set from the settings.
        var fillsSingleLane = false
        /// With 2 or more lanes but fewer than this number, the lanes grow in proportion to fill the zone. 0 is off.
        var visibleLanes = 0

        init(axis: Orientation) { self.axis = axis }

        var windows: [WindowID] { lanes.flatMap(\.windows) }

        static func clampedSize(_ fraction: Double) -> Double { min(max(fraction, minSize), maxSize) }

        /// -1 for left and up, +1 for right and down.
        static func step(_ direction: Direction) -> Int { direction == .left || direction == .up ? -1 : 1 }

        /// Whether `direction` runs along the strip axis.
        func isMain(_ direction: Direction) -> Bool { (axis == .horizontal) == direction.isHorizontal }

        func locate(_ window: WindowID) -> Location? {
            for (lane, value) in lanes.enumerated() {
                if let index = value.windows.firstIndex(of: window) { return (lane, index) }
            }
            return nil
        }

        // MARK: Membership

        mutating func remove(_ window: WindowID, at: Location) {
            lanes[at.lane].windows.remove(at: at.index)
            lanes[at.lane].shares[window] = nil
            if lanes[at.lane].windows.isEmpty { lanes.remove(at: at.lane) }
        }

        // MARK: Commands

        mutating func move(_ at: Location, _ direction: Direction) -> Bool {
            if lanes[at.lane].template != nil {
                // Inside a template the neighbour is the adjacent cell; past its edge the whole block moves.
                if let target = lanes[at.lane].template?.neighbor(of: at.index, direction) {
                    lanes[at.lane].windows.swapAt(at.index, target)
                    return true
                }
                guard isMain(direction) else { return false }
            }
            if isMain(direction) {
                let target = at.lane + Self.step(direction)
                guard lanes.indices.contains(target) else { return false }
                lanes.swapAt(at.lane, target)
            } else {
                let target = at.index + Self.step(direction)
                guard lanes[at.lane].windows.indices.contains(target) else { return false }
                lanes[at.lane].windows.swapAt(at.index, target)
            }
            return true
        }

        /// The lane takes the whole zone along the axis, and a stack shows each window at the full cross length (as
        /// tabs do). The next call gives the old size and stack back. A template lane has fixed cells: `false`.
        mutating func toggleMaximize(lane: Int) -> Bool {
            guard lanes[lane].template == nil else { return false }
            if let zoom = lanes[lane].zoom {
                lanes[lane].size = zoom.size
                lanes[lane].tabbed = zoom.tabbed
                lanes[lane].zoom = nil
            } else {
                lanes[lane].zoom = Zoom(size: lanes[lane].size, tabbed: lanes[lane].tabbed)
                lanes[lane].size = Self.maxSize
                lanes[lane].tabbed = true
            }
            return true
        }

        mutating func setSize(of lane: Int, to fraction: Double) -> Bool {
            let value = Self.clampedSize(fraction)
            // A lone lane that filled the zone now shows the size that was chosen, even when it is the stored one.
            let wasFilling = fillsLone(lane)
            lanes[lane].userSized = true
            guard abs(value - lanes[lane].size) > 1e-9 else { return wasFilling }
            lanes[lane].size = value
            return true
        }

        /// The lane is alone and the zone shows it at full size because of `single_window_fit = "fill"`.
        func fillsLone(_ lane: Int) -> Bool {
            lanes.count == 1 && fillsSingleLane && lanes[lane].userSized != true
        }

        /// Stores the cross fractions of a lane, rounded so that a clamped share is exactly 0.1 and not 0.09999999999999998.
        private mutating func setShares(of lane: Int, _ fractions: [Double]) {
            let rounded = fractions.map { ($0 * 1e9).rounded() / 1e9 }
            lanes[lane].shares = Dictionary(uniqueKeysWithValues: zip(lanes[lane].windows, rounded))
        }

        /// Moves `delta` (a fraction of the cross length) from the neighbour after the window, or before it for the
        /// last window, to the window.
        mutating func resizeCross(_ at: Location, by delta: Double, neighbour explicit: Int? = nil) -> Bool {
            let lane = lanes[at.lane]
            guard lane.windows.count > 1, lane.template == nil else { return false }
            var fractions = lane.crossFractions()
            let neighbour = explicit ?? (at.index + 1 < fractions.count ? at.index + 1 : at.index - 1)
            let lower = Self.minShare - fractions[at.index]
            let upper = fractions[neighbour] - Self.minShare
            guard lower <= upper else { return false }
            let applied = min(max(delta, lower), upper)
            guard abs(applied) > 1e-9 else { return false }
            fractions[at.index] += applied
            fractions[neighbour] -= applied
            setShares(of: at.lane, fractions)
            return true
        }

        /// Every lane gets 1/N of the zone, so all of them fit at once. With more than 1/minSize lanes the share
        /// stops at the minimum size.
        mutating func fit() -> Bool {
            setEverySize(to: Self.clampedSize(1 / Double(lanes.count)))
        }

        mutating func matchSize(of lane: Int) -> Bool { setEverySize(to: lanes[lane].size) }

        private mutating func setEverySize(to size: Double) -> Bool {
            let before = lanes
            for index in lanes.indices {
                lanes[index].size = size
                lanes[index].userSized = true
            }
            return lanes != before
        }

        private func isFullyVisible(_ lane: Int, length: CGFloat) -> Bool {
            let span = span(of: lane, length: length)
            return span.start >= scrollOffset - Self.tolerance && span.start + span.size <= scrollOffset + length + Self.tolerance
        }

        mutating func equalize(lane: Int) -> Bool {
            guard !lanes[lane].shares.isEmpty, lanes[lane].template == nil else { return false }
            lanes[lane].shares = [:]
            return true
        }

        mutating func cycleSize(of lane: Int, presets: [Double]) -> Bool {
            let current = lanes[lane].size
            guard let next = presets.first(where: { $0 > current + 0.001 }) ?? presets.first else { return false }
            return setSize(of: lane, to: next)
        }

        /// Joins the window to the lane before its own (the column on the left, the row above).
        mutating func stack(_ window: WindowID, at: Location, toward direction: Direction = .left) -> Bool {
            let target = at.lane + Self.step(direction)
            guard lanes.indices.contains(target), lanes[at.lane].template == nil, lanes[target].template == nil else { return false }
            lanes[at.lane].windows.remove(at: at.index)
            lanes[at.lane].shares = [:]
            lanes[target].windows.append(window)
            lanes[target].shares = [:]
            if lanes[at.lane].windows.isEmpty { lanes.remove(at: at.lane) }
            return true
        }

        /// Pulls the window out into its own lane before or after its lane, as `direction` says.
        mutating func unstack(_ window: WindowID, at: Location, size: Double, tabbed: Bool = false, toward direction: Direction = .right) -> Bool {
            guard lanes[at.lane].windows.count > 1, lanes[at.lane].template == nil else { return false }
            lanes[at.lane].windows.remove(at: at.index)
            lanes[at.lane].shares = [:]
            let position = Self.step(direction) < 0 ? at.lane : at.lane + 1
            lanes.insert(Lane(windows: [window], size: size, tabbed: tabbed), at: position)
            return true
        }

        /// Moves a lane to another place in the strip. A lane of a template moves like any other.
        mutating func moveLane(_ from: Int, to index: LaneIndex) -> Bool {
            guard let target = index.resolve(count: lanes.count), target != from else { return false }
            lanes.insert(lanes.remove(at: from), at: target)
            return true
        }

        // MARK: Templates

        /// Replaces a template lane with the columns it was made from (their sizes, stacks and tabs come back), or with one
        /// lane per window, each `size` wide, when those columns no longer match its windows.
        mutating func dissolve(lane: Int, size: Double) {
            guard lanes[lane].template != nil else { return }
            if let parts = lanes[lane].parts, Set(parts.flatMap(\.windows)) == Set(lanes[lane].windows) {
                lanes.replaceSubrange(lane...lane, with: parts)
                return
            }
            let singles = lanes[lane].windows.map { Lane(windows: [$0], size: size) }
            lanes.replaceSubrange(lane...lane, with: singles)
        }

        /// The columns that a template of `count` windows takes: whole columns next to each other, around the focused
        /// column, with exactly `count` windows together. The group starts at the focused column when it can, else
        /// earlier. A column that holds a template is never taken. `nil` when no such group exists.
        func group(count: Int, around lane: Int) -> Range<Int>? {
            for start in stride(from: lane, through: 0, by: -1) {
                var total = 0, end = start
                while end < lanes.count, lanes[end].template == nil, total < count {
                    total += lanes[end].windows.count
                    end += 1
                }
                if total == count, end > lane { return start..<end }
            }
            return nil
        }

        /// The focused window's column and the columns after it (before it when too few come after) fill one screen in
        /// the pattern. Only whole columns move into the block, so no stack or tab group is split, and the block keeps
        /// them to give them back. Applying the pattern the focused window already has goes back to those columns.
        /// Returns `false` when no group of whole columns has the pattern's number of windows.
        mutating func apply(_ template: SplitTemplate, focused: WindowID, size: Double) -> Bool {
            guard var at = locate(focused) else { return false }
            if lanes[at.lane].template != nil {
                let same = lanes[at.lane].template == template
                dissolve(lane: at.lane, size: size)
                if same { return true }
                guard let moved = locate(focused) else { return false }
                at = moved
            }
            guard let range = group(count: template.count, around: at.lane) else { return false }
            let parts = Array(lanes[range])
            var block = Lane(windows: parts.flatMap(\.windows), size: Self.maxSize, template: template)
            block.parts = parts
            lanes.replaceSubrange(range, with: [block])
            return true
        }

        // MARK: Scrolling

        /// How much the stored sizes grow to fill the zone: more than 1 only with `visibleLanes` and fewer lanes than that.
        /// The stored sizes stay as they are, so the chosen widths come back when enough lanes exist.
        var fillScale: Double {
            guard visibleLanes > 0, lanes.count >= 2, lanes.count < visibleLanes else { return 1 }
            let total = lanes.reduce(0) { $0 + $1.size }
            return total > 1e-9 && total < 1 - 1e-9 ? 1 / total : 1
        }

        /// The size of every lane as the zone shows it.
        func displaySizes() -> [Double] {
            if fillsLone(0) { return [Self.maxSize] }
            let scale = fillScale
            return lanes.map { $0.size * scale }
        }

        func span(of lane: Int, length: CGFloat) -> (start: CGFloat, size: CGFloat) {
            let sizes = displaySizes()
            let start = sizes[..<lane].reduce(0) { $0 + CGFloat($1) * length }
            return (start, CGFloat(sizes[lane]) * length)
        }

        func totalLength(_ length: CGFloat) -> CGFloat {
            displaySizes().reduce(0) { $0 + CGFloat($1) * length }
        }

        /// The lane grows to take the room that the other lanes on screen leave free. `false` when it would not grow.
        mutating func expand(lane: Int, length: CGFloat) -> Bool {
            guard lanes[lane].template == nil else { return false }
            let sizes = displaySizes()
            var others = 0.0
            for index in lanes.indices where index != lane {
                if isFullyVisible(index, length: length) { others += sizes[index] }
            }
            let target = Self.clampedSize(1 - others)
            guard target > sizes[lane] + 1e-9 else { return false }
            return setSize(of: lane, to: target / fillScale)
        }

        /// Keeps the strip from showing empty space at either end. A strip shorter than the zone sits at the start,
        /// except a lone lane when `centersSingleLane` is set: it sits in the middle (a negative offset).
        func clamped(_ offset: CGFloat, length: CGFloat) -> CGFloat {
            let overflow = totalLength(length) - length
            if overflow <= 0 { return centersSingleLane && lanes.count == 1 ? overflow / 2 : 0 }
            return min(max(offset, 0), overflow)
        }

        /// The offset that centres the lanes that are fully on screen as one block, or `nil` when none is.
        func visibleBlockOffset(length: CGFloat) -> CGFloat? {
            let full = lanes.indices.filter { isFullyVisible($0, length: length) }
            guard let first = full.first, let last = full.last else { return nil }
            let start = span(of: first, length: length).start
            let end = span(of: last, length: length).start + span(of: last, length: length).size
            return (start + end) / 2 - length / 2
        }

        /// Gives the window its share of the column height (a fraction of the cross length); the others shrink or
        /// grow together, keeping their relative sizes. `false` when it changes nothing or a window would get less
        /// than `minShare`.
        mutating func setCrossFraction(_ at: Location, to fraction: Double) -> Bool {
            let lane = lanes[at.lane]
            guard lane.windows.count > 1, lane.template == nil, fraction >= Self.minShare else { return false }
            let fractions = lane.crossFractions()
            let others = 1 - fractions[at.index]
            guard others > 1e-9 else { return false }
            let scale = (1 - fraction) / others
            var next = fractions.map { $0 * scale }
            next[at.index] = fraction
            guard next.allSatisfy({ $0 >= Self.minShare - 1e-9 }), abs(fraction - fractions[at.index]) > 1e-9 else { return false }
            setShares(of: at.lane, next)
            return true
        }

        /// The next preset above the current share of the window that fits; the first one that fits after the last.
        mutating func cycleCrossFraction(_ at: Location, presets: [Double]) -> Bool {
            let lane = lanes[at.lane]
            guard lane.windows.count > 1, lane.template == nil else { return false }
            let current = lane.crossFractions()[at.index]
            let candidates = presets.filter { $0 > current + 0.001 } + presets.filter { $0 <= current + 0.001 }
            for fraction in candidates where setCrossFraction(at, to: fraction) { return true }
            return false
        }

        func centeredOffset(of lane: Int, length: CGFloat) -> CGFloat {
            let span = span(of: lane, length: length)
            return span.start + span.size / 2 - length / 2
        }

        /// The offset that shows the lane, following the centre mode.
        func revealedOffset(of lane: Int, length: CGFloat, center: CenterMode) -> CGFloat {
            let span = span(of: lane, length: length)
            let fullyVisible = isFullyVisible(lane, length: length)
            switch center {
            case .always:
                return centeredOffset(of: lane, length: length)
            case .onOverflow:
                return clamped(fullyVisible ? scrollOffset : centeredOffset(of: lane, length: length), length: length)
            case .never:
                // Move only by the part that sticks out. The range is reversed for a lane longer than the zone.
                let farAligned = span.start + span.size - length
                let low = min(span.start, farAligned)
                let high = max(span.start, farAligned)
                return clamped(min(max(scrollOffset, low), high), length: length)
            }
        }

        /// Puts the scroll position where the focus wants it, unless a hold keeps it.
        mutating func follow(focused: WindowID?, length: CGFloat, center: CenterMode) {
            if let hold, hold.focus == focused {
                if hold.kind == .manual { scrollOffset = clamped(scrollOffset, length: length) }
            } else {
                hold = nil
                if let focused, let at = locate(focused) {
                    scrollOffset = revealedOffset(of: at.lane, length: length, center: center)
                } else {
                    scrollOffset = clamped(scrollOffset, length: length)
                }
            }
        }

        /// How much of the lane is inside the zone, along the axis.
        func visibleLength(of lane: Int, length: CGFloat) -> CGFloat {
            let span = span(of: lane, length: length)
            return min(span.start + span.size - scrollOffset, length) - max(span.start - scrollOffset, 0)
        }

        func isVisible(_ lane: Int, length: CGFloat) -> Bool {
            visibleLength(of: lane, length: length) > Self.tolerance
        }

        /// The lane with the largest part inside the zone; the first one on a tie.
        func mostVisibleLane(length: CGFloat) -> Int? {
            var best: (lane: Int, visible: CGFloat)?
            for lane in lanes.indices {
                let visible = visibleLength(of: lane, length: length)
                if best == nil || visible > best!.visible + Self.tolerance { best = (lane, visible) }
            }
            return best?.lane
        }

        /// Ends a manual scroll and shows the lane nearest the centre. Returns its first window.
        mutating func settle(length: CGFloat, center: CenterMode) -> WindowID? {
            guard let hold, hold.kind == .manual else { return nil }
            self.hold = nil
            var nearest: (lane: Int, distance: CGFloat)?
            for lane in lanes.indices {
                let span = span(of: lane, length: length)
                let distance = abs(span.start + span.size / 2 - scrollOffset - length / 2)
                if nearest == nil || distance < nearest!.distance { nearest = (lane, distance) }
            }
            guard let nearest else { return nil }
            scrollOffset = revealedOffset(of: nearest.lane, length: length, center: center)
            return lanes[nearest.lane].windows[0]
        }

        // MARK: Relabel

        mutating func relabel(_ mapping: [WindowID: WindowID]) {
            for index in lanes.indices { lanes[index].relabel(mapping) }
        }
    }
}
