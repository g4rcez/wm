import CoreGraphics

/// How one workspace was arranged at one moment: what `layout undo` goes back to.
public struct LayoutStep: Sendable {
    public var layout: LayoutState
    /// The floating windows and where each one was.
    public var floating: [WindowID: CGRect]
    public var maximized: Set<WindowID>
    public var fullscreen: WindowID?

    public init(layout: LayoutState, floating: [WindowID: CGRect] = [:], maximized: Set<WindowID> = [], fullscreen: WindowID? = nil) {
        self.layout = layout
        self.floating = floating
        self.maximized = maximized
        self.fullscreen = fullscreen
    }

    /// Any screen will do to compare two steps, as long as both use the same one: the workspace may have been on another
    /// monitor, or on none, when each was taken.
    private static let comparisonContext = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1600, height: 1000))

    func signature(settings: Settings) -> LayoutSignature {
        let engine = makeEngine(restoring: layout, settings: settings)
        return LayoutSignature(
            kind: layout.kind, order: engine.windows,
            // The miniature does not depend on how far a scrolling strip is scrolled, so scrolling is not a change.
            frames: engine.overview(in: Self.comparisonContext, focused: nil).frames,
            floating: floating, maximized: maximized, fullscreen: fullscreen)
    }

    /// Whether `later` arranges the same windows in another way. Steps with other windows are not comparable: a window
    /// that opens, closes or moves to another workspace is not a layout change.
    public func isRearranged(by later: LayoutStep, settings: Settings) -> Bool {
        let before = signature(settings: settings), after = later.signature(settings: settings)
        return before.members == after.members && before != after
    }

    /// This step fitted to the windows that the workspace has now, which `current` holds. Windows that are gone drop out.
    /// Windows that arrived since stay as they are: floating in place, or tiled as the
    /// layout adds a new window.
    public func fitted(to current: LayoutStep, settings: Settings) -> LayoutStep {
        var engine = makeEngine(restoring: layout, settings: settings)
        let now = makeEngine(restoring: current.layout, settings: settings).windows
        let members = Set(now).union(current.floating.keys)
        let known = Set(engine.windows).union(floating.keys)
        var floats = floating.filter { members.contains($0.key) }
        for (id, frame) in current.floating where !known.contains(id) { floats[id] = frame }
        let tiled = members.subtracting(floats.keys)
        for id in engine.windows where !tiled.contains(id) { engine.remove(id) }
        // In the order of the current layout, so that several new windows keep their order.
        let missing = tiled.subtracting(engine.windows)
        for id in now + current.floating.keys.sorted() where missing.contains(id) { engine.insert(id, after: engine.windows.last) }
        var state = engine.state
        if layout.kind == .floating, case .tiling(let dwindle) = state { state = .floating(dwindle) }
        return LayoutStep(
            layout: state, floating: floats, maximized: maximized.intersection(tiled),
            fullscreen: fullscreen.flatMap { members.contains($0) ? $0 : nil })
    }
}

struct LayoutSignature: Equatable {
    var kind: LayoutKind
    var order: [WindowID]
    var frames: [WindowID: CGRect]
    var floating: [WindowID: CGRect]
    var maximized: Set<WindowID>
    var fullscreen: WindowID?

    var members: Set<WindowID> { Set(order).union(floating.keys) }
}

public enum HistoryDirection: String, Sendable {
    case undo, redo

    var opposite: HistoryDirection { self == .undo ? .redo : .undo }
}

/// The steps that `layout undo` and `layout redo` walk, one list for each workspace. Not saved: it ends with the daemon.
public struct LayoutHistory: Sendable {
    public static let depth = 50

    private var steps: [HistoryDirection: [String: [LayoutStep]]] = [:]
    /// How many changes are open: only the outermost one records.
    private var openChanges = 0
    private var before: [String: LayoutStep] = [:]

    public init() {}

    /// Starts a change of the layouts. `capture` reads the workspaces as they are; it runs for the outermost change only,
    /// so that a batch or a drag becomes one step.
    public mutating func begin(_ capture: () -> [String: LayoutStep]) {
        if openChanges == 0 { before = capture() }
        openChanges += 1
    }

    /// Ends a change. Each workspace that the outermost change rearranged gets a step, and loses its redo steps.
    public mutating func end(_ capture: () -> [String: LayoutStep], settings: (String) -> Settings) {
        guard openChanges > 0 else { return }
        openChanges -= 1
        guard openChanges == 0, !before.isEmpty else { return }
        let after = capture()
        for (name, old) in before {
            guard let new = after[name], old.isRearranged(by: new, settings: settings(name)) else { continue }
            push(old, to: .undo, of: name)
            steps[.redo]?[name] = nil
        }
        before = [:]
    }

    /// The step to apply to go one way from `current`, or `nil` when there is none. `current` is kept to come back to.
    /// Steps that look the same as `current`, because their windows are gone, are dropped.
    public mutating func take(_ direction: HistoryDirection, of workspace: String, from current: LayoutStep, settings: Settings) -> LayoutStep? {
        // A change that walks the history is not recorded as a new one.
        before = [:]
        while let step = steps[direction]?[workspace]?.popLast() {
            let fitted = step.fitted(to: current, settings: settings)
            guard current.isRearranged(by: fitted, settings: settings) else { continue }
            push(current, to: direction.opposite, of: workspace)
            return fitted
        }
        return nil
    }

    public mutating func forget(_ workspace: String) {
        for direction in [HistoryDirection.undo, .redo] { steps[direction]?[workspace] = nil }
        before[workspace] = nil
    }

    private mutating func push(_ step: LayoutStep, to direction: HistoryDirection, of workspace: String) {
        var list = steps[direction]?[workspace] ?? []
        list.append(step)
        if list.count > Self.depth { list.removeFirst(list.count - Self.depth) }
        steps[direction, default: [:]][workspace] = list
    }
}
