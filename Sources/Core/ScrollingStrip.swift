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
        /// Relative size of each window along the cross axis. Missing means 1.
        var shares: [WindowID: Double] = [:]

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
            guard abs(value - lanes[lane].size) > 1e-9 else { return false }
            lanes[lane].size = value
            return true
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
            // Rounded so that a clamped share is exactly 0.1 and not 0.09999999999999998.
            let rounded = fractions.map { ($0 * 1e9).rounded() / 1e9 }
            lanes[at.lane].shares = Dictionary(uniqueKeysWithValues: zip(lane.windows, rounded))
            return true
        }

        /// Every lane gets 1/N of the zone, so all of them fit at once. With more than 1/minSize lanes the share
        /// stops at the minimum size.
        mutating func fit() -> Bool {
            let before = lanes
            let size = Self.clampedSize(1 / Double(lanes.count))
            for index in lanes.indices { lanes[index].size = size }
            return lanes != before
        }

        mutating func matchSize(of lane: Int) -> Bool {
            let before = lanes
            let size = lanes[lane].size
            for index in lanes.indices { lanes[index].size = size }
            return lanes != before
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
        mutating func stack(_ window: WindowID, at: Location) -> Bool {
            guard at.lane > 0, lanes[at.lane].template == nil, lanes[at.lane - 1].template == nil else { return false }
            lanes[at.lane].windows.remove(at: at.index)
            lanes[at.lane].shares = [:]
            lanes[at.lane - 1].windows.append(window)
            lanes[at.lane - 1].shares = [:]
            if lanes[at.lane].windows.isEmpty { lanes.remove(at: at.lane) }
            return true
        }

        /// Pulls the window out into its own lane after its lane.
        mutating func unstack(_ window: WindowID, at: Location, size: Double, tabbed: Bool = false) -> Bool {
            guard lanes[at.lane].windows.count > 1, lanes[at.lane].template == nil else { return false }
            lanes[at.lane].windows.remove(at: at.index)
            lanes[at.lane].shares = [:]
            lanes.insert(Lane(windows: [window], size: size, tabbed: tabbed), at: at.lane + 1)
            return true
        }

        // MARK: Templates

        /// Replaces a template lane with one lane per window, in cell order, each `size` wide.
        mutating func dissolve(lane: Int, size: Double) {
            guard lanes[lane].template != nil else { return }
            let singles = lanes[lane].windows.map { Lane(windows: [$0], size: size) }
            lanes.replaceSubrange(lane...lane, with: singles)
        }

        /// The focused window and the windows after it (before it when too few come after) fill one screen in the
        /// pattern. Applying the pattern the focused window already has goes back to single columns. Returns `false`
        /// when the strip has fewer windows than the pattern, or nothing changes.
        mutating func apply(_ template: SplitTemplate, focused: WindowID, size: Double) -> Bool {
            guard let at = locate(focused) else { return false }
            if lanes[at.lane].template == template {
                dissolve(lane: at.lane, size: size)
                return true
            }
            let flat = windows
            guard flat.count >= template.count, let position = flat.firstIndex(of: focused) else { return false }
            let start = min(position, flat.count - template.count)
            let group = Array(flat[start..<(start + template.count)])
            // A template that is cut by the new group cannot stay.
            for index in lanes.indices.reversed() where lanes[index].template != nil
                && lanes[index].windows.contains(where: group.contains) {
                dissolve(lane: index, size: size)
            }
            var rebuilt: [Lane] = []
            var placed = false
            for lane in lanes {
                let remaining = lane.windows.filter { !group.contains($0) }
                if remaining.count != lane.windows.count, !placed {
                    rebuilt.append(Lane(windows: group, size: Self.maxSize, template: template))
                    placed = true
                }
                guard !remaining.isEmpty else { continue }
                var kept = lane
                kept.windows = remaining
                kept.shares = lane.shares.filter { remaining.contains($0.key) }
                rebuilt.append(kept)
            }
            lanes = rebuilt
            return true
        }

        // MARK: Scrolling

        func span(of lane: Int, length: CGFloat) -> (start: CGFloat, size: CGFloat) {
            let start = lanes[..<lane].reduce(0) { $0 + CGFloat($1.size) * length }
            return (start, CGFloat(lanes[lane].size) * length)
        }

        func totalLength(_ length: CGFloat) -> CGFloat {
            lanes.reduce(0) { $0 + CGFloat($1.size) * length }
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
            let full = lanes.indices.filter { lane in
                let span = span(of: lane, length: length)
                return span.start >= scrollOffset - Self.tolerance && span.start + span.size <= scrollOffset + length + Self.tolerance
            }
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
            let rounded = next.map { ($0 * 1e9).rounded() / 1e9 }
            lanes[at.lane].shares = Dictionary(uniqueKeysWithValues: zip(lane.windows, rounded))
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
            let fullyVisible = span.start >= scrollOffset - Self.tolerance
                && span.start + span.size <= scrollOffset + length + Self.tolerance
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
            for index in lanes.indices {
                lanes[index].windows = lanes[index].windows.map { mapping[$0] ?? $0 }
                var shares: [WindowID: Double] = [:]
                for (window, share) in lanes[index].shares { shares[mapping[window] ?? window] = share }
                lanes[index].shares = shares
            }
        }
    }
}
