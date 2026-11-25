import Common
import Core

/// `layout undo` and `layout redo`: what is recorded, and how a step goes back on the screen.
extension WindowManager {
    /// The commands that can rearrange a layout. The others are not worth a look.
    static let layoutCommandNames: Set<String> = ["layout", "move", "swap", "resize", "window", "workspace", "workspaces"]

    private func layoutStep(of space: Workspace) -> LayoutStep {
        let floating = windows.filter { $0.value.workspace == space.name && $0.value.floating && !$0.value.isOutOfLayout }
        return LayoutStep(
            layout: space.savedLayout, floating: floating.mapValues { $0.floatFrame ?? $0.info.frame },
            maximized: space.maximized, fullscreen: space.fullscreen)
    }

    /// Nothing while a restart is restored: the layouts hold places for windows that have not opened yet.
    private func layoutSteps() -> [String: LayoutStep] {
        isRestoringAfterReboot ? [:] : workspaces.mapValues { layoutStep(of: $0) }
    }

    func beginLayoutChange() {
        layoutHistory.begin { layoutSteps() }
    }

    func endLayoutChange() {
        layoutHistory.end({ layoutSteps() }, settings: { settings(forWorkspace: $0) })
    }

    func recordingLayout<T>(_ change: () -> T) -> T {
        beginLayoutChange()
        defer { endLayoutChange() }
        return change()
    }

    /// For changes that are not the user's: nothing that `change` does becomes a step.
    func withoutLayoutHistory(_ change: () -> Void) {
        layoutHistory.begin { [:] }
        defer { endLayoutChange() }
        change()
    }

    func walkLayoutHistory(_ direction: HistoryDirection, workspace name: String?) -> ServerAnswer {
        guard !isRestoringAfterReboot else { return fail("wm is still restoring the windows after the restart") }
        guard let space = name.map({ workspaces[$0] }) ?? focusedWorkspace else {
            return fail(name.map { "there is no workspace '\($0)'" } ?? "there is no workspace", 1, hint: "see `wm list workspaces`")
        }
        let current = layoutStep(of: space)
        guard let step = layoutHistory.take(direction, of: space.name, from: current, settings: settings(forWorkspace: space.name)) else {
            return fail("there is nothing to \(direction.rawValue) on workspace \(space.name)")
        }
        apply(step, to: space)
        return ok()
    }

    private func apply(_ step: LayoutStep, to space: Workspace) {
        for (id, managed) in windows where managed.workspace == space.name && !managed.isOutOfLayout {
            setFloating(id, step.floating[id] != nil)
            if let frame = step.floating[id] { setFloatFrame(id, frame) }
        }
        // After the floating flags: `setFloating` edits the engine that this replaces.
        space.kind = step.layout.kind
        space.engine = makeEngine(restoring: step.layout, settings: settings(forWorkspace: space.name))
        space.maximized = step.maximized
        space.fullscreen = step.fullscreen
        events.emit("layout_changed", ["workspace": .string(space.name), "layout": .string(space.kind.rawValue)])
        relayout()
    }
}
