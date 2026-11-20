import CoreGraphics

/// Where a window goes when it becomes floating: the middle of `area`. It keeps its size, unless it is almost the whole area
/// (a maximized or filled window, 90% or more both ways, or bigger): then it gets 60% of the area, so the change can be seen.
public func floatFrame(current: CGRect, in area: CGRect) -> CGRect {
    let almostFull = current.width >= area.width * 0.9 && current.height >= area.height * 0.9
    let size = almostFull
        ? CGSize(width: area.width * 0.6, height: area.height * 0.6)
        : CGSize(width: min(current.width, area.width), height: min(current.height, area.height))
    return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
}

/// The frame that the tiling layout would give `new` when it opens: the windows of `existing` are tiled in order, then `new`
/// splits `anchor` (the last window when `anchor` is `nil` or not in `existing`). Nothing is kept; only the frame of `new` is returned.
public func tilingFrame(for new: WindowID, among existing: [WindowID], after anchor: WindowID?, settings: Settings, context: LayoutContext) -> CGRect? {
    var scratch = DwindleEngine(settings: settings)
    var previous: WindowID?
    for id in existing where id != new {
        scratch.insert(id, after: previous)
        previous = id
    }
    scratch.insert(new, after: anchor.flatMap { existing.contains($0) ? $0 : nil } ?? previous)
    return scratch.frames(in: context, focused: new)[new]
}
