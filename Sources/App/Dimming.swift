import Core
import Platform

/// The layers that darken the windows without the focus (`dim` in the config).
extension WindowManager {
    /// `actual`: ask the window server where each window is, for one that took another size than the layout asked for.
    func dimTargets(actual: Bool) -> [DimTarget] {
        var exempt: Set<WindowID> = []
        for id in lastVisible {
            guard let managed = windows[id] else {
                exempt.insert(id)
                continue
            }
            let settings = settings(forWorkspace: managed.workspace).dim
            if !(managed.dim ?? settings.enabled) || settings.amount <= 0 || managed.isOutOfLayout
                || SpecialWorkspace.isSpecial(managed.workspace) || workspaces[managed.workspace]?.zen == true {
                exempt.insert(id)
            }
        }
        return windowsToDim(shown: lastVisible, parked: lastParked, focused: focused, exempt: exempt).compactMap { id in
            guard let managed = windows[id], let frame = (actual ? WindowList.bounds(of: id) : nil) ?? currentFrame(of: id) else { return nil }
            let settings = settings(forWorkspace: managed.workspace)
            var color = settings.dim.color
            color.alpha = settings.dim.amount
            return DimTarget(id: id, frame: frame, color: color, radius: settings.border.radius)
        }
    }
}
