import CoreGraphics

/// The layout after a drop: a copy of the engine with the dragged window moved into the zone. The engine that the workspace
/// holds is not changed, so a drag can try zones and still go back.
public enum DropPlan {
    /// `nil` when the zone does not change this layout (monocle, the floating layout, a zone with no target).
    public static func apply(_ zone: DropZone, dragged: WindowID, to engine: any LayoutEngine, in context: LayoutContext) -> (any LayoutEngine)? {
        guard engine.windows.contains(dragged) else { return nil }
        switch engine {
        case let dwindle as DwindleEngine: return tilingPlan(zone, dragged, dwindle, context)
        case let scrolling as ScrollingEngine: return scrollingPlan(zone, dragged, scrolling, context)
        case let master as MasterEngine: return masterPlan(zone, dragged, master, context)
        default: return nil
        }
    }

    private static func swapped(_ engine: any LayoutEngine, _ a: WindowID, _ b: WindowID) -> (any LayoutEngine)? {
        guard a != b, engine.windows.contains(b) else { return nil }
        var copy = engine
        copy.relabel([a: b, b: a])
        return copy
    }

    private static func tilingPlan(_ zone: DropZone, _ dragged: WindowID, _ engine: DwindleEngine, _ context: LayoutContext) -> (any LayoutEngine)? {
        var copy = engine
        switch zone {
        case .middle(let target): return swapped(engine, dragged, target)
        case .beside(let target, let side):
            guard target != dragged, copy.windows.contains(target) else { return nil }
            copy.remove(dragged)
            _ = copy.perform(.preselect(side), focused: target, in: context)
            copy.insert(dragged, after: target)
            return copy
        case .screenEdge(let side):
            guard copy.windows.count > 1 else { return nil }
            // Beside the first window on that side, then up to the root: the window takes that whole side of the screen.
            copy.remove(dragged)
            let frames = copy.frames(in: context, focused: nil)
            guard let anchor = frames.min(by: { edgeDistance($0.value, side, context.viewport) < edgeDistance($1.value, side, context.viewport) })?.key
            else { return nil }
            _ = copy.perform(.preselect(side), focused: anchor, in: context)
            copy.insert(dragged, after: anchor)
            _ = copy.perform(.moveToRoot, focused: dragged, in: context)
            return copy
        case .none: return nil
        }
    }

    private static func edgeDistance(_ frame: CGRect, _ side: Direction, _ area: CGRect) -> CGFloat {
        switch side {
        case .left: frame.minX - area.minX
        case .right: area.maxX - frame.maxX
        case .up: frame.minY - area.minY
        case .down: area.maxY - frame.maxY
        }
    }

    private static func scrollingPlan(_ zone: DropZone, _ dragged: WindowID, _ engine: ScrollingEngine, _ context: LayoutContext) -> (any LayoutEngine)? {
        var copy = engine
        switch zone {
        case .middle(let target): return swapped(engine, dragged, target)
        case .beside(let target, let side):
            guard target != dragged, copy.windows.contains(target) else { return nil }
            copy.remove(dragged)
            // A new column right after the target's, then over to the side that was asked for.
            copy.insert(dragged, after: target)
            switch side {
            case .left: _ = copy.perform(.move(.left), focused: dragged, in: context)
            case .right: break
            case .up, .down:
                // Into the target's stack, at its bottom; then up past the target for the top side.
                _ = copy.perform(.stack(.left), focused: dragged, in: context)
                if side == .up, let stack = copy.lanes(of: .horizontal).first(where: { $0.contains(target) }) ?? copy.lanes(of: .vertical).first(where: { $0.contains(target) }),
                   let at = stack.firstIndex(of: target), let mine = stack.firstIndex(of: dragged) {
                    for _ in 0..<max(0, mine - at) { _ = copy.perform(.move(.up), focused: dragged, in: context) }
                }
            }
            return copy
        case .screenEdge(let side):
            guard side.isHorizontal else { return nil }
            copy.remove(dragged)
            let ends = copy.lanes(of: .horizontal).compactMap { side == .left ? $0.first : $0.last }
            guard let anchor = side == .left ? ends.first : ends.last else { return nil }
            copy.insert(dragged, after: anchor)
            if side == .left { _ = copy.perform(.moveColumn(.first), focused: dragged, in: context) }
            return copy
        case .none: return nil
        }
    }

    private static func masterPlan(_ zone: DropZone, _ dragged: WindowID, _ engine: MasterEngine, _ context: LayoutContext) -> (any LayoutEngine)? {
        var copy = engine
        switch zone {
        case .middle(let target): return swapped(engine, dragged, target)
        case .beside(let target, let side):
            guard target != dragged, copy.windows.contains(target) else { return nil }
            copy.place(dragged, near: target, after: side == .right || side == .down)
            return copy
        case .screenEdge:
            // An edge of the screen makes the window the master.
            guard let first = copy.windows.first, first != dragged else { return nil }
            copy.place(dragged, near: first, after: false)
            return copy
        case .none: return nil
        }
    }
}
