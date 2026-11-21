import AppKit
import Core

extension WindowManager {
    /// The windows of `wm jump`: tiled and floating windows of the workspace that each monitor shows, with their frames.
    func jumpWindows() -> (frames: [WindowID: CGRect], focused: WindowID?, displays: [CGRect]) {
        var frames: [WindowID: CGRect] = [:]
        for monitor in monitors {
            let name = activeWorkspace(of: monitor)
            let floating = windows.filter { $0.value.workspace == name && $0.value.floating && !$0.value.isOutOfLayout }.keys
            for id in workspace(name).engine.windows + floating {
                if windows[id] != nil, let frame = currentFrame(of: id) { frames[id] = frame }
            }
        }
        return (frames, focused, monitors.map(\.frame))
    }

    /// The window that was picked in `wm jump`.
    func jumpChoose(_ id: WindowID, _ action: JumpAction) {
        guard let managed = windows[id] else { return }
        switch action {
        case .focus:
            focus(id)
        case .close:
            watcher(for: managed.info.pid)?.close(id)
        case .swap:
            guard let current = focused, current != id else { return }
            // Two tiled windows of one workspace trade slots; any other pair just moves the focus.
            if let other = windows[current], !other.floating, !managed.floating, other.workspace == managed.workspace,
               swapWindows(current, id) {
                workspace(managed.workspace).fullscreen = nil
                relayout()
            } else {
                focus(id)
            }
        }
    }
}
