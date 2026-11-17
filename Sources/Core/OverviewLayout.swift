import CoreGraphics
import Foundation

/// What one workspace of the overview shows: the layout as its engine draws it, and the part of it that is on screen.
public struct OverviewRowInput: Sendable, Equatable {
    /// Every window in the engine's own space (a scrolling strip can be wider than the screen).
    public var frames: [WindowID: CGRect]
    /// The parts of that space that are on screen now.
    public var viewports: [CGRect]
    /// The size of the screen that the workspace is shown on. An empty workspace is drawn with its shape.
    public var screen: CGSize
    /// The top left corner of the screen in the engine's space: the first viewport of a scrolling strip, else the work area.
    public var origin: CGPoint

    public init(frames: [WindowID: CGRect], viewports: [CGRect], screen: CGSize, origin: CGPoint = .zero) {
        self.frames = frames
        self.viewports = viewports
        self.screen = screen
        self.origin = origin
    }
}

/// One workspace as a small copy of its screen.
public struct OverviewSlot: Sendable, Equatable {
    /// The screen of the workspace, scaled. Also the drop target of the workspace.
    public var frame: CGRect
    /// The on-screen parts of the layout, in the same space as `frame`.
    public var viewports: [CGRect]
}

/// The overview as one tall column of workspaces, in a "world" that scrolls up and down behind the screen. The origin is the top
/// left of the world, and `screen` is the part of it that you see. Pure geometry: the overlay draws it.
public struct OverviewGeometry: Sendable, Equatable {
    public var slots: [OverviewSlot]
    /// Every window, in world coordinates.
    public var cards: [WindowID: CGRect]
    public var screen: CGSize
    /// The space between two slots.
    public var gap: CGFloat
    /// The height of the world: the slots, the gaps, and room to put the first and the last slot in the middle of the screen.
    public var worldHeight: CGFloat
    /// For each slot, the scroll offset that puts its middle in the middle of the screen.
    public var centers: [CGFloat]

    public var scrollRange: ClosedRange<CGFloat> { 0...(centers.last ?? 0) }

    public func clampedScroll(_ value: CGFloat) -> CGFloat {
        min(max(value, scrollRange.lowerBound), scrollRange.upperBound)
    }

    /// The window under a point of the world. The smallest card wins: a floating window lies on top of the tiles.
    public func card(at point: CGPoint) -> WindowID? {
        cards.filter { $0.value.contains(point) }.min { $0.value.width * $0.value.height < $1.value.width * $1.value.height }?.key
    }

    /// The slot that a point of the world belongs to: its screen, and half of the gap above and below it.
    public func slotIndex(at point: CGPoint) -> Int? {
        slots.firstIndex { point.y >= $0.frame.minY - gap / 2 && point.y < $0.frame.maxY + gap / 2 }
    }

    /// The slot that has a card, by the middle of the card.
    public func slotIndex(ofCard id: WindowID) -> Int? {
        cards[id].flatMap { slotIndex(at: CGPoint(x: $0.midX, y: $0.midY)) }
    }

    /// The cards of one slot.
    public func cardIDs(inSlot index: Int) -> [WindowID] {
        cards.keys.filter { slotIndex(ofCard: $0) == index }
    }

    /// How far the layout of the slot of `id` has to move sideways to put the card in the middle of the screen. A layout that fits
    /// the screen (the tiles of a tiling workspace) stays where it is: 0. A wider one (a scrolling strip) moves, but not so far
    /// that its first or last card leaves the screen by more than `margin`.
    public func panToCenter(_ id: WindowID, margin: CGFloat = 24) -> CGFloat {
        guard let card = cards[id], let index = slotIndex(ofCard: id) else { return 0 }
        let frames = cardIDs(inSlot: index).compactMap { cards[$0] }
        guard let first = frames.first else { return 0 }
        let start = frames.reduce(first.minX) { min($0, $1.minX) }, end = frames.reduce(first.maxX) { max($0, $1.maxX) }
        guard end - start > screen.width - 2 * margin else { return 0 }
        let wanted = screen.width / 2 - card.midX
        return min(max(wanted, screen.width - margin - end), margin - start)
    }

    /// Moves the cards of a slot, and the on-screen parts of its layout, sideways.
    public mutating func pan(slot index: Int, by dx: CGFloat) {
        guard slots.indices.contains(index), dx != 0 else { return }
        for id in cardIDs(inSlot: index) { cards[id] = cards[id]?.offsetBy(dx: dx, dy: 0) }
        slots[index].viewports = slots[index].viewports.map { $0.offsetBy(dx: dx, dy: 0) }
    }
}

public enum OverviewLayout {
    /// The slots are `zoom` times the size of their screens, in the middle of `screen`, one under the other with `gap` between.
    /// A card is its window moved and scaled the same way, so a scrolling strip keeps its real offset: columns outside the
    /// screen stick out of the slot.
    public static func compute(_ rows: [OverviewRowInput], screen: CGSize, zoom: CGFloat, gap: CGFloat) -> OverviewGeometry {
        var geometry = OverviewGeometry(slots: [], cards: [:], screen: screen, gap: gap, worldHeight: screen.height, centers: [])
        let heights = rows.map { $0.screen.height * zoom }
        var top = ((screen.height - (heights.first ?? 0)) / 2).rounded()
        for (index, row) in rows.enumerated() {
            let size = CGSize(width: row.screen.width * zoom, height: heights[index])
            let origin = CGPoint(x: ((screen.width - size.width) / 2).rounded(), y: top)
            func place(_ rect: CGRect) -> CGRect {
                CGRect(
                    x: origin.x + (rect.minX - row.origin.x) * zoom, y: origin.y + (rect.minY - row.origin.y) * zoom,
                    width: rect.width * zoom, height: rect.height * zoom)
            }
            for (id, frame) in row.frames { geometry.cards[id] = place(frame) }
            let frame = CGRect(origin: origin, size: size)
            geometry.slots.append(OverviewSlot(frame: frame, viewports: row.viewports.map(place)))
            geometry.centers.append(frame.midY - screen.height / 2)
            top += size.height + gap
        }
        let last = geometry.slots.last?.frame.maxY ?? 0
        geometry.worldHeight = max(screen.height, last + (screen.height - (heights.last ?? 0)) / 2)
        return geometry
    }
}
