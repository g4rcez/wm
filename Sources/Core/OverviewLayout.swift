import CoreGraphics
import Foundation

/// What one workspace row of the overview shows: the layout as its engine draws it, and the part of it that is on screen.
public struct OverviewRowInput: Sendable, Equatable {
    /// Every window in the engine's own space (a scrolling strip can be wider than the screen).
    public var frames: [WindowID: CGRect]
    /// The parts of that space that are on screen now.
    public var viewports: [CGRect]
    /// The size of the screen that the workspace is shown on. An empty workspace is drawn with its shape.
    public var screen: CGSize

    public init(frames: [WindowID: CGRect], viewports: [CGRect], screen: CGSize) {
        self.frames = frames
        self.viewports = viewports
        self.screen = screen
    }
}

public struct OverviewRowGeometry: Sendable, Equatable {
    /// The name and the layout of the workspace, at the left.
    public var label: CGRect
    /// The rounded area that holds the windows of the workspace. It is also the drop target of the row.
    public var stage: CGRect
    /// The on-screen parts of the layout, in the same space as `stage`.
    public var viewports: [CGRect]
    /// Where the empty workspace's screen sits. Equals the area that the windows fill when there are windows.
    public var content: CGRect
}

public struct OverviewGeometry: Sendable, Equatable {
    public var panel: CGSize
    public var rows: [OverviewRowGeometry]
    /// Every window, in the same space as the rows.
    public var cards: [WindowID: CGRect]
    /// Where the rows start, and how tall the part is that shows them. When `contentHeight` is larger, the rows scroll.
    public var rowsTop: CGFloat
    public var rowsViewportHeight: CGFloat
    public var contentHeight: CGFloat
}

/// The layout of the overview panel: a search field at the top, then one row for each workspace. Each row shows its
/// workspace in the layout that it has (a scrolling strip, or the tiles of the screen) scaled to fit its stage.
/// Coordinates have their origin at the top left of the panel.
public enum OverviewLayout {
    public static let topInset: CGFloat = 76
    public static let side: CGFloat = 28
    public static let bottomInset: CGFloat = 24
    public static let labelWidth: CGFloat = 116
    public static let rowGap: CGFloat = 14
    public static let preferredRowHeight: CGFloat = 232
    public static let minimumRowHeight: CGFloat = 96
    public static let stagePadding: CGFloat = 14

    /// The panel is `panelWidth` wide and as tall as the rows need, up to `maxPanelHeight`. Rows get their preferred height
    /// while they fit, then shrink to the minimum, then the list scrolls.
    public static func compute(_ rows: [OverviewRowInput], panelWidth: CGFloat, maxPanelHeight: CGFloat) -> OverviewGeometry {
        let count = max(rows.count, 1)
        let available = max(maxPanelHeight - topInset - bottomInset, minimumRowHeight)
        func needed(_ height: CGFloat) -> CGFloat { CGFloat(count) * height + CGFloat(count - 1) * rowGap }
        var rowHeight = preferredRowHeight
        if needed(rowHeight) > available {
            rowHeight = max(minimumRowHeight, (available - CGFloat(count - 1) * rowGap) / CGFloat(count))
        }
        let contentHeight = needed(rowHeight)
        let viewportHeight = min(contentHeight, available)

        let stageX = side + labelWidth
        let stageWidth = max(panelWidth - 2 * side - labelWidth, 1)
        var geometry = OverviewGeometry(
            panel: CGSize(width: panelWidth, height: topInset + viewportHeight + bottomInset), rows: [], cards: [:],
            rowsTop: topInset, rowsViewportHeight: viewportHeight, contentHeight: contentHeight)

        for (index, input) in rows.enumerated() {
            let top = topInset + CGFloat(index) * (rowHeight + rowGap)
            let stage = CGRect(x: stageX, y: top, width: stageWidth, height: rowHeight)
            let inner = stage.insetBy(dx: stagePadding, dy: stagePadding)
            let rects = Array(input.frames.values) + input.viewports
            let bounds = rects.dropFirst().reduce(rects.first ?? CGRect(origin: .zero, size: input.screen)) { $0.union($1) }
            let scale = (bounds.width > 0 && bounds.height > 0) ? min(inner.width / bounds.width, inner.height / bounds.height) : 1
            let origin = CGPoint(x: inner.midX - bounds.width * scale / 2, y: inner.midY - bounds.height * scale / 2)
            func place(_ rect: CGRect) -> CGRect {
                CGRect(
                    x: origin.x + (rect.minX - bounds.minX) * scale, y: origin.y + (rect.minY - bounds.minY) * scale,
                    width: rect.width * scale, height: rect.height * scale)
            }
            for (id, frame) in input.frames { geometry.cards[id] = place(frame) }
            geometry.rows.append(OverviewRowGeometry(
                label: CGRect(x: side, y: top, width: labelWidth, height: rowHeight), stage: stage,
                viewports: input.viewports.map(place), content: place(bounds)))
        }
        return geometry
    }
}
