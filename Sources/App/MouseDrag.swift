import AppKit
import Core
import Platform
import Scripting

/// A drag that started with the mouse modifier held (`mouse = { move_modifier, resize_modifier }`): the left button
/// moves the window under the pointer, the right button resizes it.
struct ModifierDrag {
    enum Kind { case move, resize }

    var kind: Kind
    var button: MouseButton
    var window: WindowID
    var floating: Bool
    var startPointer: CGPoint
    var startFrame: CGRect
    var edges: (horizontal: Direction, vertical: Direction)
    /// Where the window is now while it follows the pointer.
    var frame: CGRect
    /// A tiled resize moves dividers step by step: the pointer of the last step and its time.
    var lastPointer: CGPoint
    var lastStep: TimeInterval = 0

    /// The window itself follows the pointer: a move, or the resize of a floating window. The resize of a tiled window
    /// moves dividers, and the layout decides the frame.
    var followsPointer: Bool { kind == .move || floating }
}

extension WindowManager {
    private static let minimumDragSize = CGSize(width: 120, height: 80)

    /// The modifiers of `text` as event flags, or `nil` when the text is not valid (the config was checked already).
    private func eventFlags(_ text: String?) -> CGEventFlags? {
        guard let text, let modifiers = try? parseModifiers(text) else { return nil }
        var flags: CGEventFlags = []
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        return flags
    }

    private static let modifierMask: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]

    /// Returns `true` when the event belongs to a modifier drag, so apps never see it.
    func handleMouse(_ event: MouseEvent) -> Bool {
        switch event.kind {
        case .down: return beginDrag(event)
        case .dragged:
            guard let drag = modifierDrag, drag.button == event.button else {
                refreshLiveBorder()
                return false
            }
            continueDrag(drag, to: event.location)
            return true
        case .up:
            guard let drag = modifierDrag, drag.button == event.button else { return false }
            endDrag(drag, at: event.location)
            return true
        }
    }

    private func beginDrag(_ event: MouseEvent) -> Bool {
        guard modifierDrag == nil else { return false }
        let text = event.button == .left ? settings.mouse.moveModifier : settings.mouse.resizeModifier
        guard let wanted = eventFlags(text), event.flags.intersection(Self.modifierMask) == wanted else { return false }
        let candidates = Set(windows.filter { !$0.value.isOutOfLayout && isVisible($0.value.workspace) }.keys)
        guard let id = WindowList.topmost(at: event.location, among: candidates), let managed = windows[id],
              workspace(managed.workspace).fullscreen != id, let frame = currentFrame(of: id) else { return false }
        focus(id, warpMouse: false)
        // The user moves the window: where it ends is its place, even if it just opened.
        openingHold[id] = nil
        modifierDrag = ModifierDrag(
            kind: event.button == .left ? .move : .resize, button: event.button, window: id, floating: managed.floating,
            startPointer: event.location, startFrame: frame,
            edges: MonitorGeometry.nearestEdges(of: frame, to: event.location), frame: frame, lastPointer: event.location)
        return true
    }

    private func continueDrag(_ start: ModifierDrag, to pointer: CGPoint) {
        var drag = start
        let delta = CGPoint(x: pointer.x - drag.startPointer.x, y: pointer.y - drag.startPointer.y)
        switch drag.kind {
        case .move:
            drag.frame = drag.startFrame.offsetBy(dx: delta.x, dy: delta.y)
        case .resize where drag.floating:
            drag.frame = MonitorGeometry.resized(drag.startFrame, edges: drag.edges, by: delta, minimum: Self.minimumDragSize)
        case .resize:
            // Tiled: the dividers follow the pointer, at most once per frame. A skipped step is not lost: the next one
            // measures from the last step that ran.
            let now = ProcessInfo.processInfo.systemUptime
            guard now - drag.lastStep >= 1.0 / 60 else { return }
            let step = CGPoint(x: pointer.x - drag.lastPointer.x, y: pointer.y - drag.lastPointer.y)
            if let managed = windows[drag.window] {
                let space = workspace(managed.workspace)
                let context = layoutContext(forWorkspace: managed.workspace)
                let horizontal = drag.edges.horizontal == .right ? step.x : -step.x
                let vertical = drag.edges.vertical == .down ? step.y : -step.y
                if horizontal != 0 { _ = space.engine.perform(.resizeEdge(drag.edges.horizontal, horizontal), focused: drag.window, in: context) }
                if vertical != 0 { _ = space.engine.perform(.resizeEdge(drag.edges.vertical, vertical), focused: drag.window, in: context) }
            }
            drag.lastPointer = pointer
            drag.lastStep = now
            modifierDrag = drag
            relayout(snapAll: true)
            return
        }
        modifierDrag = drag
        if drag.floating { setFloatFrame(drag.window, drag.frame) }
        animator.place(drag.window, at: drag.frame)
        applier.send([drag.window: drag.frame], windows: windows)
        updateBorder()
    }

    private func endDrag(_ drag: ModifierDrag, at pointer: CGPoint) {
        modifierDrag = nil
        // A tiled window that was moved and dropped on the tile of another window of its workspace swaps places with it.
        // Anywhere else it goes back to its tile.
        if drag.kind == .move, !drag.floating, let managed = windows[drag.window] {
            let other = windows.first { id, window in
                id != drag.window && window.workspace == managed.workspace && !window.floating && !window.isOutOfLayout
                    && currentFrame(of: id)?.contains(pointer) == true
            }?.key
            if let other { _ = swapWindows(drag.window, other) }
        }
        relayout()
    }
}
