import AppKit
import Core
import Platform
import Scripting

struct ManagedWindow {
    var info: WindowInfo
    var workspace: String
    var floating: Bool
    var minimized = false
    /// Where a floating window lives; restored when its workspace is shown again.
    var floatFrame: CGRect?
}

final class Workspace {
    let name: String
    var kind: LayoutKind
    var engine: any LayoutEngine
    /// Most recently focused first.
    var history: [WindowID] = []
    var fullscreen: WindowID?
    /// Windows that fill the work area inside the outer gaps while the others stay tiled behind them. Each window keeps
    /// its own state: focusing another window does not end it.
    var maximized: Set<WindowID> = []
    /// Pseudotiled windows (tiling layout): the size each keeps, centred in its tile.
    var pseudo: [WindowID: CGSize] = [:]

    init(name: String, kind: LayoutKind, settings: Settings) {
        self.name = name
        self.kind = kind
        engine = makeEngine(kind, settings: settings)
    }
}

struct Monitor {
    var id: UInt32
    var name: String
    var frame: CGRect
    var workArea: CGRect
    var workspace: String
}

/// All window state and the layout pipeline. Everything here runs on the main actor.
@MainActor
final class WindowManager {
    var settings = Settings()
    var rules: [WindowRule] = []
    /// Layout per workspace from `wm.workspace`; other workspaces use `settings.layout`.
    private(set) var workspaceLayouts: [String: LayoutKind] = [:]
    /// What `wm.workspace` set per workspace: monitor binding, default, and the settings it changes.
    private(set) var workspaceRules: [String: WorkspaceRule] = [:]

    private(set) var windows: [WindowID: ManagedWindow] = [:]
    private(set) var workspaces: [String: Workspace] = [:]
    private(set) var monitors: [Monitor] = []
    private(set) var focused: WindowID?
    private(set) var focusedMonitorID: UInt32 = 0
    private(set) var previousWorkspace: String?
    /// The special workspace shown in place of the normal workspace, per monitor id. The normal workspace stays the
    /// monitor's workspace and comes back when the special one hides.
    private(set) var specials: [UInt32: String] = [:]
    /// The active binding mode ("main" by default).
    private(set) var mode = "main"
    var modeNames: Set<String> = ["main"]

    let events = EventHub()
    /// Called after every layout pass with the workspace and layout shown on the focused monitor.
    var onRelayout: ((_ workspace: String?, _ layout: String?) -> Void)?
    var runRuleCommand: ((_ command: [String], _ window: WindowID) -> Void)?
    /// Called after the binding mode is set (also to the mode it already was), for the menu bar icon and the label.
    var onModeChange: ((_ mode: String) -> Void)?

    private var tracker: AppTracker?
    private let applier = FrameApplier()
    private var animator = Animator()
    private let border = BorderOverlay()
    private let tabIndicator = TabIndicatorOverlay()
    private var clock: Timer?
    private var lastTick = CACurrentMediaTime()
    private var refreshing = false
    private var refreshAgain = false
    private var lastVisible: Set<WindowID> = []
    /// Windows of a shown workspace that a layout parked at the hidden corner (a scrolling strip does that at the
    /// boundary to the other strip). They jump to and from the corner instead of sweeping across the screen.
    private var lastParked: Set<WindowID> = []
    /// Native mode: the desktops of each display, in order, as macOS reports them.
    private var nativeSpaces: [UInt32: [String]] = [:]
    /// Native mode: the virtual row (1, 2, ...) shown on each desktop.
    private var activeRow: [String: Int] = [:]
    /// Where each window last was while its workspace was shown; used to bring parked windows back on quit.
    private var lastShownFrame: [WindowID: CGRect] = [:]

    /// The state of the previous daemon, until the windows that are still open took their places.
    private var pendingRestore: SavedState?
    /// Windows that `detect` took from `pendingRestore`; `finishRestore` builds their layouts.
    private var adopted: Set<WindowID> = []
    private var configApplied = false
    private var spawnRules: [(pid: Int32, rule: WindowRule, expires: TimeInterval)] = []
    /// The window that had the focus when a window with `focus = false` opened: it gets the focus back.
    private var refocusAfterOpen: WindowID?
    private var saveTimer: Timer?
    private var lastSaved: Data?

    init() {
        pendingRestore = StateStore.load()
        // The config layouts of the last run are what "changed" is measured against when the config loads.
        workspaceLayouts = pendingRestore?.configLayouts ?? [:]
    }

    // MARK: - Start

    func start() {
        tracker = AppTracker { [weak self] in self?.scheduleRefresh() }
        applier.watcher = { [weak self] pid in self?.tracker?.watcher(for: pid) }
        scheduleRefresh()
    }

    func apply(
        settings new: Settings, rules: [WindowRule], workspaceLayouts newLayouts: [String: LayoutKind] = [:],
        workspaceRules newRules: [String: WorkspaceRule] = [:]
    ) {
        let layoutChanged = new.layout != settings.layout
        if new.workspaces != settings.workspaces { resetState() }
        settings = new
        configApplied = true
        if let saved = pendingRestore, saved.mode != new.workspaces.rawValue { pendingRestore = nil }
        self.rules = rules
        animator.rate = new.animations.rate
        animator.enabled = new.animations.enabled
        let previousLayouts = workspaceLayouts
        workspaceLayouts = newLayouts
        workspaceRules = newRules
        if layoutChanged || workspaces.isEmpty {
            // A new default layout applies to workspaces that are still empty and have no layout of their own.
            for workspace in workspaces.values where workspace.engine.windows.isEmpty && newLayouts[workspace.name] == nil {
                workspace.kind = new.layout
                workspace.engine = makeEngine(new.layout, settings: settings(forWorkspace: workspace.name))
            }
        }
        // An empty workspace has no layout to keep: it takes the settings of its rule at once.
        for workspace in workspaces.values where workspace.engine.windows.isEmpty {
            workspace.engine = makeEngine(workspace.kind, settings: settings(forWorkspace: workspace.name))
        }
        // Existing engines keep their windows; rebuild them so changed per-layout settings take effect.
        for workspace in workspaces.values where !workspace.engine.windows.isEmpty {
            applySettings(to: workspace)
        }
        // A workspace layout from the config applies when it is new or changed. A layout that the user switched to
        // by hand with `wm layout` stays until the config says something different for that workspace.
        for (name, kind) in newLayouts where previousLayouts[name] != kind {
            let target = workspace(name)
            if target.kind != kind { rebuild(target, as: kind) }
        }
        scheduleRefresh()
    }

    var isNative: Bool { settings.workspaces == .native }

    /// The settings of a workspace: the global ones with the changes of its `wm.workspace` rule.
    func settings(forWorkspace name: String) -> Settings {
        guard let overrides = workspaceRules[name]?.overrides else { return settings }
        var copy = settings
        // The values were checked when the config loaded.
        try? applyWorkspaceOverrides(overrides, to: &copy)
        return copy
    }

    /// The monitor that the rule of a workspace binds it to, when that monitor is connected.
    func boundMonitor(of name: String) -> Monitor? {
        guard let spec = workspaceRules[name]?.monitor else { return nil }
        return monitors.enumerated().first { MonitorSelector.matches(spec, index: $0.offset, name: $0.element.name) }?.element
    }

    /// Switching between emulated and native workspaces starts over: every window is detected again.
    private func resetState() {
        windows = [:]
        workspaces = [:]
        monitors = []
        specials = [:]
        focused = nil
        lastVisible = []
        lastParked = []
        nativeSpaces = [:]
        activeRow = [:]
    }

    // MARK: - Refresh

    func scheduleRefresh() {
        guard !refreshing else {
            refreshAgain = true
            return
        }
        refreshing = true
        Task { @MainActor in
            repeat {
                refreshAgain = false
                await refresh()
            } while refreshAgain
            refreshing = false
        }
    }

    private func refresh() async {
        guard let tracker else { return }
        tracker.syncWatchers()
        let infos = await tracker.snapshot()
        let focusedID = await tracker.focusedWindow()
        updateMonitors()
        reconcile(infos)
        finishRestore()
        if let previous = refocusAfterOpen {
            refocusAfterOpen = nil
            if windows[previous] != nil { focus(previous) }
        } else if let focusedID, windows[focusedID] != nil, focusedID != focused {
            didFocus(focusedID)
        }
        relayout()
    }

    private func updateMonitors() {
        let displays = Displays.all().sorted { $0.frame.minX < $1.frame.minX }
        if let saved = activeRestore, activeRow.isEmpty { activeRow = saved.activeRows }
        let spaces = isNative ? SpaceReader.read() : nil
        var next: [Monitor] = []
        var nativeNames: [UInt32: [String]] = [:]
        for (displayIndex, display) in displays.enumerated() {
            let existing = monitors.first { $0.id == display.id }
            let taken = next.map(\.workspace)
            var workspace = existing?.workspace ?? restoredWorkspace(of: display.id, taken: taken)
                ?? defaultWorkspace(display: displayIndex, name: display.name, taken: taken)
                ?? unusedWorkspaceName(taken: taken, display: displayIndex, name: display.name)
            if let info = spaces?.first(where: { $0.displayID == display.id }) {
                let names = NativeWorkspaceName.desktops(displayNumber: displayIndex + 1, displayCount: displays.count, desktopCount: info.spaces.count)
                nativeNames[display.id] = names
                let desktop = info.spaces.firstIndex(of: info.current).map { names[$0] } ?? "fullscreen-\(info.current)"
                workspace = NativeWorkspaceName.row(of: desktop, activeRow[desktop] ?? 1)
            }
            next.append(Monitor(id: display.id, name: display.name, frame: display.frame, workArea: display.workArea, workspace: workspace))
            _ = self.workspace(workspace)
            if isNative, let existing, existing.workspace != workspace {
                previousWorkspace = existing.workspace
                events.emit("workspace_changed", ["workspace": .string(workspace), "previous": .string(existing.workspace), "monitor": .number(Double(display.id))])
            }
        }
        // A monitor that went away takes nothing with it: its windows move to a monitor that is left.
        if !isNative, let home = next.first(where: { $0.id == focusedMonitorID }) ?? next.first {
            for old in monitors where !next.contains(where: { $0.id == old.id }) {
                for (id, managed) in windows where managed.workspace == old.workspace { moveWindow(id, to: home.workspace) }
            }
        }
        monitors = next
        setSpecials(specials.filter { shown in next.contains { $0.id == shown.key } })
        nativeSpaces = nativeNames
        if !monitors.contains(where: { $0.id == focusedMonitorID }) {
            focusedMonitorID = monitors.first(where: { $0.frame.origin == .zero })?.id ?? monitors.first?.id ?? 0
        }
    }

    /// The workspace that a rule makes the default of this display (`default = true` with a matching `monitor`).
    private func defaultWorkspace(display index: Int, name: String, taken: [String]) -> String? {
        workspaceRules.sorted { $0.key < $1.key }.first { entry in
            entry.value.isDefault && !taken.contains(entry.key)
                && entry.value.monitor.map { MonitorSelector.matches($0, index: index, name: name) } == true
        }?.key
    }

    /// First numeric name (1, 2, ...) that no monitor shows, and that no rule binds to another monitor.
    private func unusedWorkspaceName(taken: [String], display index: Int, name: String) -> String {
        let used = Set(monitors.map(\.workspace)).union(taken)
        return (1...).lazy.map(String.init).first { candidate in
            !used.contains(candidate) && (workspaceRules[candidate]?.monitor.map { MonitorSelector.matches($0, index: index, name: name) } ?? true)
        }!
    }

    func workspace(_ name: String) -> Workspace {
        if let existing = workspaces[name] { return existing }
        let created = Workspace(name: name, kind: workspaceLayouts[name] ?? settings.layout, settings: settings(forWorkspace: name))
        workspaces[name] = created
        return created
    }

    private func reconcile(_ infos: [WindowInfo]) {
        var seen: Set<WindowID> = []
        for info in infos {
            seen.insert(info.id)
            if var managed = windows[info.id] {
                managed.info = info
                // Native mode: a window dragged to another desktop shows up there; follow it. Only the desktop
                // counts: virtual rows of one desktop are ours, and a snapshot can be older than a row switch.
                if isNative, let home = monitor(containing: CGPoint(x: info.frame.midX, y: info.frame.midY)),
                   NativeWorkspaceName.desktop(of: managed.workspace) != NativeWorkspaceName.desktop(of: home.workspace) {
                    moveWindow(info.id, to: NativeWorkspaceName.desktop(of: home.workspace))
                    managed = windows[info.id] ?? managed
                    managed.info = info
                }
                if info.isMinimized != managed.minimized { setMinimized(info.id, info.isMinimized) }
                windows[info.id]?.info = managed.info
                // A snapshot can be older than a workspace switch: never save a parked frame as the home frame.
                let parked = info.frame.minX >= hiddenCorner().x - 1 && info.frame.minY >= hiddenCorner().y - 1
                if managed.floating, !managed.minimized, !parked, managed.workspaceVisible(self) {
                    windows[info.id]?.floatFrame = info.frame
                }
                continue
            }
            detect(info)
        }
        // Native mode: windows of other desktops are not in the snapshot; only forget those that are gone.
        let missing = windows.keys.filter { !seen.contains($0) }
        let alive = isNative && !missing.isEmpty ? Self.systemWindowIDs() : []
        for id in missing where !alive.contains(id) { forget(id) }
    }

    private static func systemWindowIDs() -> Set<WindowID> {
        let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(list.compactMap { ($0[kCGWindowNumber as String] as? Int).map { WindowID($0) } })
    }

    private func detect(_ info: WindowInfo) {
        guard info.kind != .ignored, !info.isFullscreen else { return }
        if let saved = activeRestore?.windows.first(where: { $0.id == info.id && $0.bundleID == info.bundleID }) {
            adopt(info, as: saved)
            return
        }
        var rule = matchingRule(info)
        // A window that a `wm exec` command opened gets the options of that command on top of the rules.
        if let spawn = takeSpawnRule(for: info) { rule = rule.map { $0.merging(spawn) } ?? spawn }
        let home = monitor(containing: CGPoint(x: info.frame.midX, y: info.frame.midY)) ?? focusedMonitor
        let ruleMonitor = rule?.monitor.flatMap(monitor(matching:))
        let workspaceName = rule?.workspace ?? ruleMonitor.map(activeWorkspace(of:)) ?? home.map(activeWorkspace(of:)) ?? "1"
        let monitor = monitor(showing: workspaceName) ?? focusedMonitor
        var floating = info.kind == .floating || rule?.float == true
        var floatFrame: CGRect?
        if let area = monitor?.workArea, rule?.size != nil || rule?.center == true {
            floating = rule?.float != false
            var size = info.frame.size
            if let wanted = rule?.size {
                size.width = wanted.width <= 1 ? area.width * wanted.width : wanted.width
                size.height = wanted.height <= 1 ? area.height * wanted.height : wanted.height
            }
            var origin = info.frame.origin
            if rule?.center == true {
                origin = CGPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
            }
            floatFrame = CGRect(origin: origin, size: size)
        }
        windows[info.id] = ManagedWindow(info: info, workspace: workspaceName, floating: floating, minimized: info.isMinimized, floatFrame: floatFrame ?? (floating ? info.frame : nil))
        let target = workspace(workspaceName)
        if let layout = rule?.layout, target.engine.windows.isEmpty { target.kind = layout; target.engine = makeEngine(layout, settings: settings(forWorkspace: workspaceName)) }
        if !floating, !info.isMinimized {
            target.engine.insert(info.id, after: target.history.first { windows[$0]?.workspace == workspaceName && !(windows[$0]?.floating ?? true) })
            if let width = rule?.width {
                _ = target.engine.perform(.columnWidth(.fraction(width)), focused: info.id, in: layoutContext(forWorkspace: workspaceName))
            }
            if rule?.maximize == true { maximizeOnOpen(info.id, in: target) }
        }
        if rule?.focus == false, let previous = focused, previous != info.id { refocusAfterOpen = previous }
        animator.seed(info.id, at: info.frame)
        events.emit("window_open", ["id": .number(Double(info.id)), "app": .string(info.bundleID), "title": .string(info.title), "workspace": .string(workspaceName)])
        for command in rule?.commands ?? [] { runRuleCommand?(command.split(separator: " ").map(String.init), info.id) }
    }

    // MARK: - Saved state

    /// The previous state, when it was saved in the mode that runs now.
    private var activeRestore: SavedState? {
        pendingRestore.flatMap { $0.mode == settings.workspaces.rawValue ? $0 : nil }
    }

    private func restoredWorkspace(of display: UInt32, taken: [String]) -> String? {
        guard let name = activeRestore?.monitors[String(display)], !taken.contains(name) else { return nil }
        return name
    }

    /// A window of the previous run is not new: it keeps its workspace and floating state, and no rule or `window_open`
    /// hook runs for it. Its place in the layout comes with `finishRestore`.
    private func adopt(_ info: WindowInfo, as saved: SavedWindow) {
        windows[info.id] = ManagedWindow(
            info: info, workspace: saved.workspace, floating: saved.floating, minimized: info.isMinimized,
            floatFrame: saved.floatFrame ?? (saved.floating ? info.frame : nil))
        _ = workspace(saved.workspace)
        adopted.insert(info.id)
        animator.seed(info.id, at: info.frame)
    }

    /// Gives each workspace that got windows back the layout it had. A saved layout holds windows that are gone, and
    /// misses windows that are new: the first are removed (the engine closes the gap), the second are inserted.
    private func finishRestore() {
        guard let saved = pendingRestore else { return }
        guard saved.mode == settings.workspaces.rawValue else {
            // The config that comes next may change the mode; wait for it.
            if configApplied { pendingRestore = nil }
            return
        }
        pendingRestore = nil
        for name in Set(adopted.compactMap { windows[$0]?.workspace }) {
            guard let savedSpace = saved.workspaces[name] else { continue }
            let space = workspace(name)
            space.kind = savedSpace.layout.kind
            space.engine = makeEngine(restoring: savedSpace.layout, settings: settings(forWorkspace: name))
            let tiled = Set(windows.filter { $0.value.workspace == name && !$0.value.floating && !$0.value.minimized }.keys)
            for id in space.engine.windows where !tiled.contains(id) { space.engine.remove(id) }
            for id in tiled.subtracting(space.engine.windows).sorted() { space.engine.insert(id, after: space.engine.windows.last) }
            space.history = savedSpace.history.filter { windows[$0]?.workspace == name }
            space.maximized = Set(savedSpace.maximized.filter(tiled.contains))
            space.fullscreen = savedSpace.fullscreen.flatMap { windows[$0]?.workspace == name ? $0 : nil }
            // A layout that the config changed since the save wins over the saved one.
            if let kind = workspaceLayouts[name], saved.configLayouts[name] != kind, kind != space.kind { rebuild(space, as: kind) }
        }
        adopted = []
    }

    func snapshot() -> SavedState {
        SavedState(
            mode: settings.workspaces.rawValue,
            windows: windows.sorted { $0.key < $1.key }.map {
                SavedWindow(id: $0.key, bundleID: $0.value.info.bundleID, workspace: $0.value.workspace, floating: $0.value.floating, floatFrame: $0.value.floatFrame)
            },
            workspaces: workspaces.mapValues {
                SavedWorkspace(layout: $0.engine.state, history: $0.history, maximized: $0.maximized.sorted(), fullscreen: $0.fullscreen)
            },
            monitors: Dictionary(uniqueKeysWithValues: monitors.map { (String($0.id), $0.workspace) }),
            activeRows: activeRow,
            configLayouts: workspaceLayouts)
    }

    /// Writes the state at once. Not while the previous state waits to be used, and not with no windows: both would
    /// replace a good file with an empty one.
    func saveState() {
        saveTimer?.invalidate()
        saveTimer = nil
        guard pendingRestore == nil, !windows.isEmpty else { return }
        do {
            let data = try StateStore.encode(snapshot())
            guard data != lastSaved else { return }
            try StateStore.write(data)
            lastSaved = data
        } catch {
            fputs("wmd: cannot save state: \(error)\n", stderr)
        }
    }

    /// Layout changes come in bursts (a key held down, an animation): one write per half second at most.
    private func scheduleSave() {
        guard saveTimer == nil else { return }
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveState() }
        }
    }

    /// Options of `wm exec` for the window that the command opens: the process that was started, and the rule.
    func expectWindow(from pid: Int32, rule: WindowRule) {
        spawnRules.append((pid: pid, rule: rule, expires: ProcessInfo.processInfo.systemUptime + 15))
    }

    private func takeSpawnRule(for info: WindowInfo) -> WindowRule? {
        let now = ProcessInfo.processInfo.systemUptime
        spawnRules.removeAll { $0.expires < now }
        guard let index = spawnRules.firstIndex(where: { ProcessTree.isDescendant(info.pid, of: $0.pid) }) else { return nil }
        return spawnRules.remove(at: index).rule
    }

    /// The monitor that a rule names: its number (1 is the leftmost) or part of its name, ignoring case.
    private func monitor(matching spec: String) -> Monitor? {
        monitors.enumerated().first { MonitorSelector.matches(spec, index: $0.offset, name: $0.element.name) }?.element
    }

    /// A window that a rule opens maximized: a scrolling column fills its zone, any other layout uses the overlay.
    private func maximizeOnOpen(_ id: WindowID, in workspace: Workspace) {
        if workspace.engine is ScrollingEngine,
           workspace.engine.perform(.maximize, focused: id, in: layoutContext(forWorkspace: workspace.name)) { return }
        workspace.maximized.insert(id)
    }

    /// Rules apply in order. A matching rule with `stop = false` lets later rules add to it; later values win.
    private func matchingRule(_ info: WindowInfo) -> WindowRule? {
        var merged: WindowRule?
        for rule in rules {
            if let app = rule.app, app.caseInsensitiveCompare(info.bundleID) != .orderedSame,
               app.caseInsensitiveCompare(info.appName) != .orderedSame { continue }
            if let title = rule.title, info.title.range(of: title, options: .regularExpression) == nil { continue }
            guard let result = merged else {
                merged = rule
                if rule.stop { break }
                continue
            }
            merged = result.merging(rule)
            if rule.stop { break }
        }
        return merged
    }

    private func forget(_ id: WindowID) {
        guard let managed = windows.removeValue(forKey: id) else { return }
        lastShownFrame[id] = nil
        let workspace = workspace(managed.workspace)
        workspace.engine.remove(id)
        workspace.history.removeAll { $0 == id }
        if workspace.fullscreen == id { workspace.fullscreen = nil }
        workspace.maximized.remove(id)
        workspace.pseudo[id] = nil
        if focused == id { focused = workspace.history.first }
        hideSpecialIfEmpty(workspace.name)
        applier.forget(id)
        events.emit("window_close", ["id": .number(Double(id))])
    }

    private func setMinimized(_ id: WindowID, _ minimized: Bool) {
        guard var managed = windows[id] else { return }
        managed.minimized = minimized
        windows[id] = managed
        let workspace = workspace(managed.workspace)
        if minimized {
            workspace.maximized.remove(id)
            workspace.engine.remove(id)
        } else if !managed.floating {
            workspace.engine.insert(id, after: workspace.history.first)
        }
    }

    // MARK: - Focus

    var focusedMonitor: Monitor? { monitors.first { $0.id == focusedMonitorID } }

    var focusedWorkspace: Workspace? {
        focusedMonitor.map { workspace(activeWorkspace(of: $0)) }
    }

    /// Records a focus change that happened in macOS (click, Cmd-Tab) and follows it with the workspace view.
    private func didFocus(_ id: WindowID) {
        guard let managed = windows[id] else { return }
        focused = id
        let workspace = workspace(managed.workspace)
        workspace.history.removeAll { $0 == id }
        workspace.history.insert(id, at: 0)
        if !isNative, SpecialWorkspace.isSpecial(managed.workspace) {
            // A window of a special workspace: show that workspace where it is, or where the user is looking.
            let monitorID = monitor(showing: managed.workspace)?.id ?? focusedMonitorID
            if specials[monitorID] != managed.workspace {
                setSpecials(SpecialWorkspace.toggle(managed.workspace, on: monitorID, shown: specials))
            }
            focusedMonitorID = monitorID
        } else if let monitor = monitors.first(where: { $0.workspace == managed.workspace }) {
            focusedMonitorID = monitor.id
            // A normal window got the focus (Cmd-Tab, the Dock): its workspace must show, so the special workspace
            // hides. An empty one stays: the user opened it to start an app in it.
            if let special = specials[monitor.id], windows.values.contains(where: { $0.workspace == special }) {
                setSpecials(specials.filter { $0.key != monitor.id })
            }
        } else if isNative {
            // Same desktop, another virtual row: switch to that row.
            _ = setRow(NativeWorkspaceName.rowNumber(of: managed.workspace), desktop: NativeWorkspaceName.desktop(of: managed.workspace), focusWindow: false)
        } else if let monitor = focusedMonitor {
            // The window belongs to a hidden workspace: show that workspace where the user is looking.
            showWorkspace(managed.workspace, on: monitor.id, focusWindow: false)
        }
        events.emit("window_focus", ["id": .number(Double(id)), "app": .string(managed.info.bundleID), "title": .string(managed.info.title)])
    }

    /// Focuses a window on request of a command.
    func focus(_ id: WindowID, warpMouse: Bool = true) {
        guard let managed = windows[id] else { return }
        didFocus(id)
        applier.watcher(managed.info.pid)?.raise(id)
        relayout()
        if warpMouse, settings.mouseFollowsFocus, let frame = currentFrame(of: id) {
            CGWarpMouseCursorPosition(CGPoint(x: frame.midX, y: frame.midY))
        }
    }

    func currentFrame(of id: WindowID) -> CGRect? {
        animator.frames[id] ?? windows[id]?.info.frame
    }

    // MARK: - Workspaces

    /// A normal workspace under a shown special workspace is not visible: its windows are parked.
    func isVisible(_ workspace: String) -> Bool { monitors.contains { activeWorkspace(of: $0) == workspace } }

    /// The workspace that is on screen on a monitor: its shown special workspace, else its normal one.
    func activeWorkspace(of monitor: Monitor) -> String { specials[monitor.id] ?? monitor.workspace }

    /// The monitor that has a workspace, as its normal or as its shown special workspace.
    func monitor(showing workspace: String) -> Monitor? {
        monitors.first { $0.workspace == workspace || specials[$0.id] == workspace }
    }

    // MARK: - Special workspaces

    /// `workspace special`: shows a special workspace on the focused monitor, or hides it.
    func toggleSpecial(_ name: String) {
        setSpecials(SpecialWorkspace.toggle(name, on: focusedMonitorID, shown: specials))
        if let monitor = focusedMonitor, let id = windowToFocus(in: workspace(activeWorkspace(of: monitor))) {
            focus(id)
        } else {
            focused = nil
            relayout()
        }
    }

    /// Changes which special workspace each monitor shows, and tells the listeners.
    private func setSpecials(_ next: [UInt32: String]) {
        let old = specials
        specials = next
        for (monitor, name) in old where next[monitor] != name {
            events.emit("special_changed", ["workspace": .string(name), "monitor": .number(Double(monitor)), "visible": .bool(false)])
        }
        for (monitor, name) in next where old[monitor] != name {
            _ = workspace(name)
            events.emit("special_changed", ["workspace": .string(name), "monitor": .number(Double(monitor)), "visible": .bool(true)])
        }
    }

    /// A shown special workspace that lost its last window hides.
    private func hideSpecialIfEmpty(_ name: String) {
        guard let monitor = specials.first(where: { $0.value == name })?.key,
              !windows.values.contains(where: { $0.workspace == name }) else { return }
        setSpecials(specials.filter { $0.key != monitor })
    }

    func showWorkspace(_ name: String, on requested: UInt32, focusWindow: Bool = true) {
        _ = workspace(name)
        // A workspace that a rule binds to a monitor is shown there, and the focus goes with it.
        let monitorID = boundMonitor(of: name)?.id ?? requested
        guard let index = monitors.firstIndex(where: { $0.id == monitorID }) else { return }
        setSpecials(specials.filter { $0.key != monitorID })
        if let other = monitors.firstIndex(where: { $0.workspace == name }), other != index {
            // Already shown on another monitor: swap the two, as AeroSpace does.
            monitors[other].workspace = monitors[index].workspace
        }
        let old = monitors[index].workspace
        monitors[index].workspace = name
        focusedMonitorID = monitorID
        if old != name {
            previousWorkspace = old
            events.emit("workspace_changed", ["workspace": .string(name), "previous": .string(old), "monitor": .number(Double(monitorID))])
        }
        if focusWindow {
            let target = workspace(name)
            if let id = windowToFocus(in: target) {
                focus(id)
                return
            }
            focused = nil
        }
        relayout()
    }

    func moveWindow(_ id: WindowID, to name: String) {
        guard var managed = windows[id], managed.workspace != name else { return }
        let source = workspace(managed.workspace)
        source.engine.remove(id)
        source.history.removeAll { $0 == id }
        if source.fullscreen == id { source.fullscreen = nil }
        source.maximized.remove(id)
        source.pseudo[id] = nil
        let destination = workspace(name)
        managed.workspace = name
        windows[id] = managed
        if !managed.floating, !managed.minimized {
            destination.engine.insert(id, after: destination.history.first)
        }
        if focused == id { focused = source.history.first }
        hideSpecialIfEmpty(source.name)
    }

    func setFloating(_ id: WindowID, _ floating: Bool) {
        guard var managed = windows[id], managed.floating != floating else { return }
        let workspace = workspace(managed.workspace)
        managed.floating = floating
        if floating {
            workspace.maximized.remove(id)
            workspace.pseudo[id] = nil
            workspace.engine.remove(id)
            managed.floatFrame = currentFrame(of: id) ?? managed.info.frame
        } else {
            workspace.engine.insert(id, after: workspace.history.first { $0 != id })
        }
        windows[id] = managed
    }

    /// The window that gets focus when a workspace is shown: the most recently focused one.
    private func windowToFocus(in workspace: Workspace) -> WindowID? {
        return workspace.history.first(where: { windows[$0] != nil }) ?? workspace.engine.windows.first
    }

    /// A window moved to another workspace: on an empty workspace it takes the whole work area (inside the gaps), because
    /// a lone window is not full size in every layout (a scrolling column is half the width). On a workspace that has
    /// windows it joins the layout and the layout is balanced, so all windows fit. With `tile` it only joins the layout.
    func arrive(_ id: WindowID, tile: Bool = false) {
        guard let managed = windows[id], !managed.floating, !managed.minimized else { return }
        let destination = workspace(managed.workspace)
        if tile { return }
        destination.fullscreen = nil
        if destination.engine.windows.contains(where: { $0 != id }) {
            destination.maximized = []
            _ = destination.engine.perform(.balance, focused: id, in: layoutContext(forWorkspace: destination.name))
        } else {
            destination.maximized.insert(id)
        }
        destination.history.removeAll { $0 == id }
        destination.history.insert(id, at: 0)
    }

    /// Moves a window to another workspace without following it: no focus change and no workspace switch. The overview
    /// uses it. Like `window send workspace`, the window arrives maximized on an empty workspace, else the layout is
    /// balanced.
    func sendQuietly(_ id: WindowID, to name: String) {
        guard windows[id] != nil else { return }
        moveWindow(id, to: name)
        arrive(id)
        relayout()
    }

    /// `next`, `prev` or `empty` as the name of a workspace (see `RelativeWorkspace`); any other name comes back as it is.
    func resolveWorkspaceName(_ name: String) -> String {
        guard RelativeWorkspace.words.contains(name), !isNative, let current = focusedMonitor?.workspace else { return name }
        let used = Set(windows.values.map(\.workspace)).union(monitors.map(\.workspace))
        return RelativeWorkspace.resolve(name, from: current, used: used) ?? name
    }

    /// Two tiled windows of one workspace exchange their slots (position, size, stack and strip). `false` when they are
    /// not both in the layout of one workspace.
    @discardableResult
    func swapWindows(_ a: WindowID, _ b: WindowID) -> Bool {
        guard a != b, let first = windows[a], let second = windows[b], first.workspace == second.workspace else { return false }
        let workspace = workspace(first.workspace)
        let tiled = workspace.engine.windows
        guard tiled.contains(a), tiled.contains(b) else { return false }
        workspace.engine.relabel([a: b, b: a])
        return true
    }

    /// A config reload: the workspace keeps its layout (strips, split tree, sizes) and gets the new settings.
    private func applySettings(to workspace: Workspace) {
        workspace.engine = makeEngine(restoring: workspace.engine.state, settings: settings(forWorkspace: workspace.name))
        events.emit("layout_changed", ["workspace": .string(workspace.name), "layout": .string(workspace.kind.rawValue)])
    }

    func rebuild(_ workspace: Workspace, as kind: LayoutKind) {
        // Applying new settings to a scrolling workspace keeps both strips, sizes and scroll positions.
        if kind == workspace.kind, let old = workspace.engine as? ScrollingEngine {
            workspace.engine = ScrollingEngine(settings: settings(forWorkspace: workspace.name), keeping: old)
            events.emit("layout_changed", ["workspace": .string(workspace.name), "layout": .string(kind.rawValue)])
            return
        }
        let order = workspace.engine.windows
        workspace.kind = kind
        var engine = makeEngine(kind, settings: settings(forWorkspace: workspace.name))
        var previous: WindowID?
        for id in order {
            engine.insert(id, after: previous)
            previous = id
        }
        workspace.engine = engine
        events.emit("layout_changed", ["workspace": .string(workspace.name), "layout": .string(kind.rawValue)])
    }

    func focusMonitor(_ id: UInt32) {
        guard let monitor = monitors.first(where: { $0.id == id }) else { return }
        focusedMonitorID = id
        let target = workspace(activeWorkspace(of: monitor))
        if let window = windowToFocus(in: target) {
            focus(window)
        } else {
            focused = nil
            relayout()
        }
        events.emit("monitor_changed", ["monitor": .number(Double(id))])
    }

    // MARK: - Layout

    func relayout(snapAll: Bool = false) {
        var targets: [WindowID: CGRect] = [:]
        var visible: Set<WindowID> = []
        for monitor in monitors {
            // wm cannot keep the windows of a special workspace above the windows of the normal one (macOS brings
            // every window of the active app forward), so only one of the two is laid out; the other is parked.
            let workspace = workspace(activeWorkspace(of: monitor))
            let context = layoutContext(forWorkspace: workspace.name)
            let focusHere = focused.flatMap { windows[$0]?.workspace == workspace.name ? $0 : nil }
            for (id, frame) in workspace.engine.frames(in: context, focused: focusHere) {
                let cell = workspace.pseudo[id].map { PixelFrame.centered($0, in: frame) } ?? frame
                targets[id] = workspace.fullscreen == id ? monitor.workArea : cell
                visible.insert(id)
            }
            if let full = workspace.fullscreen, windows[full] != nil { targets[full] = monitor.workArea }
            if workspace.fullscreen == nil {
                for maximized in workspace.maximized where windows[maximized] != nil {
                    targets[maximized] = context.gaps.outerArea(context.viewport)
                }
            }
            for (id, managed) in windows where managed.workspace == workspace.name && managed.floating && !managed.minimized {
                targets[id] = managed.floatFrame ?? managed.info.frame
                visible.insert(id)
            }
        }
        let corner = hiddenCorner()
        let shownDesktops = Set(monitors.map { NativeWorkspaceName.desktop(of: $0.workspace) })
        for (id, managed) in windows where !visible.contains(id) && !managed.minimized
            && (!isNative || shownDesktops.contains(NativeWorkspaceName.desktop(of: managed.workspace))) {
            let size = animator.frames[id]?.size ?? managed.info.frame.size
            targets[id] = CGRect(origin: corner, size: size)
        }
        let parkedNow = Set(visible.filter { targets[$0]?.origin == corner })
        let snap = visible.symmetricDifference(lastVisible)
            .union(targets.keys.filter { !visible.contains($0) })
            .union(parkedNow).union(lastParked)
        lastVisible = visible
        lastParked = parkedNow
        for id in visible where !parkedNow.contains(id) { lastShownFrame[id] = targets[id] }
        animator.setTargets(targets, snap: snapAll ? Set(targets.keys) : snap)
        applier.send(animator.frames, windows: windows)
        startClockIfNeeded()
        updateBorder()
        updateTabIndicator()
        let shown = focusedWorkspace
        onRelayout?(shown?.name, shown?.kind.rawValue)
        scheduleSave()
    }

    /// The context every layout call gets: the work area, the gaps, where a window that must disappear is parked, and the
    /// screen edges where a window may stick out as a sliver. An edge with a neighbouring monitor is left out, because
    /// the sliver would show on that monitor; the top edge is always left out, because macOS keeps title bars below the
    /// menu bar.
    func layoutContext(for monitor: Monitor, gaps: Gaps? = nil) -> LayoutContext {
        let frames = monitors.map { MonitorFrame(id: $0.id, frame: $0.frame) }
        var edges: Set<Direction> = [.left, .right, .down]
        for direction in [Direction.left, .right, .down] where MonitorGeometry.adjacent(to: monitor.id, direction, in: frames) != nil {
            edges.remove(direction)
        }
        return LayoutContext(viewport: monitor.workArea, gaps: gaps ?? settings.gaps, hiddenCorner: hiddenCorner(), sliverEdges: edges)
    }

    /// The context of the monitor that has `workspace` (the focused monitor if none has). A shown special workspace
    /// gets a smaller area and no slivers, so it does not look like a normal workspace.
    func layoutContext(forWorkspace name: String) -> LayoutContext {
        guard let monitor = monitor(showing: name) ?? focusedMonitor else { return LayoutContext(viewport: .zero, gaps: settings(forWorkspace: name).gaps) }
        var context = layoutContext(for: monitor, gaps: settings(forWorkspace: name).gaps)
        if specials[monitor.id] == name {
            context.viewport = SpecialWorkspace.viewport(in: monitor.workArea)
            context.sliverEdges = []
        }
        return context
    }

    /// Where windows of hidden workspaces are parked.
    private func hiddenCorner() -> CGPoint {
        MonitorGeometry.hiddenCorner(of: monitors.map(\.frame))
    }

    /// The counters of the last animation, for `wm daemon status` with `WM_DEBUG`.
    var animationSummary: String { applier.stats.summary }

    private func startClockIfNeeded() {
        guard !animator.isSettled, clock == nil else { return }
        applier.stats.reset()
        lastTick = CACurrentMediaTime()
        clock = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let changed = animator.step(dt: now - lastTick)
        applier.stats.tick(interval: now - lastTick)
        lastTick = now
        applier.send(changed.filter { windows[$0.key] != nil }, windows: windows)
        updateBorder()
        updateTabIndicator()
        if animator.isSettled {
            clock?.invalidate()
            clock = nil
        }
    }

    /// The tabs of the focused window's column, when it shows tabs: a bar of one segment per window.
    private func updateTabIndicator() {
        guard settings.tabIndicator.enabled, let focused, let managed = windows[focused], !managed.minimized, !managed.floating,
              isVisible(managed.workspace), workspace(managed.workspace).fullscreen == nil,
              let scrolling = workspace(managed.workspace).engine as? ScrollingEngine,
              let tabs = scrolling.tabs(of: focused), let index = tabs.firstIndex(of: focused),
              let frame = currentFrame(of: focused) else {
            tabIndicator.hide()
            return
        }
        tabIndicator.show(on: frame, count: tabs.count, selected: index, settings.tabIndicator)
    }

    private func updateBorder() {
        guard let focused, let managed = windows[focused], !managed.minimized, settings(forWorkspace: managed.workspace).border.enabled,
              let frame = currentFrame(of: focused), isVisible(managed.workspace) else {
            border.hide()
            return
        }
        border.show(around: frame, settings(forWorkspace: managed.workspace).border)
    }

    /// Brings every parked window back on screen. Runs when the daemon quits, so no window stays hidden.
    func restoreAll() {
        let group = DispatchGroup()
        for (id, managed) in windows where (!lastVisible.contains(id) || lastParked.contains(id)) && !managed.minimized {
            let size = lastShownFrame[id]?.size ?? managed.info.frame.size
            let area = (monitors.first { $0.id == focusedMonitorID } ?? monitors.first)?.workArea ?? .zero
            let frame = lastShownFrame[id] ?? CGRect(
                x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height
            )
            // A window that was parked as a sliver at the screen edge comes back fully on screen.
            let inside = CGRect(
                x: min(max(frame.minX, area.minX), max(area.minX, area.maxX - frame.width)),
                y: min(max(frame.minY, area.minY), max(area.minY, area.maxY - frame.height)),
                width: frame.width, height: frame.height
            )
            group.enter()
            watcher(for: managed.info.pid)?.setFrame(id, inside.integral) { _ in group.leave() }
        }
        _ = group.wait(timeout: .now() + 3)
    }

    /// Native mode: shows virtual row `row` of `desktop` on its display. Rows are extra workspaces inside one desktop;
    /// the windows of the other rows are parked like windows of a hidden emulated workspace.
    @discardableResult
    func setRow(_ row: Int, desktop: String, focusWindow: Bool = true) -> Bool {
        guard isNative, row >= 1, let index = monitors.firstIndex(where: { NativeWorkspaceName.desktop(of: $0.workspace) == desktop }) else { return false }
        let name = NativeWorkspaceName.row(of: desktop, row)
        guard monitors[index].workspace != name else { return true }
        let previous = monitors[index].workspace
        activeRow[desktop] = row
        monitors[index].workspace = name
        previousWorkspace = previous
        focusedMonitorID = monitors[index].id
        _ = workspace(name)
        events.emit("workspace_changed", ["workspace": .string(name), "previous": .string(previous), "monitor": .number(Double(monitors[index].id))])
        if focusWindow {
            let target = workspace(name)
            if let id = windowToFocus(in: target) {
                focus(id)
                return true
            }
            focused = nil
        }
        relayout()
        return true
    }

    /// `up` / `down` / a number, relative to the row shown on the focused display.
    func rowNumber(for spec: String?) -> Int? {
        guard let current = focusedMonitor.map({ NativeWorkspaceName.rowNumber(of: $0.workspace) }), let spec else { return nil }
        switch spec {
        case "up": return max(current - 1, 1)
        case "down": return current + 1
        default: return Int(spec).flatMap { $0 >= 1 ? $0 : nil }
        }
    }

    var focusedDesktop: String? { focusedMonitor.map { NativeWorkspaceName.desktop(of: $0.workspace) } }

    /// Native mode: switches the focused display to another desktop with the Mission Control shortcut
    /// (Control-1 ... Control-9, Control-0). macOS must have "Switch to Desktop N" enabled in Keyboard Shortcuts.
    func switchSpace(to name: String) -> Bool {
        guard let names = nativeSpaces[focusedMonitorID] else { return false }
        guard let index = names.firstIndex(of: name) ?? Int(name).map({ $0 - 1 }),
              names.indices.contains(index), index < 10,
              let code = KeyCodes.code(for: String((index + 1) % 10)) else { return false }
        EventTap.post(keyCode: code, flags: .maskControl)
        return true
    }

    func setMode(_ name: String) -> Bool {
        guard modeNames.contains(name) else { return false }
        mode = name
        events.emit("mode_changed", ["mode": .string(name)])
        onModeChange?(name)
        return true
    }

    func watcher(for pid: pid_t) -> AppWatcher? { tracker?.watcher(for: pid) }

    // MARK: - Mouse resize

    private var mouseIsDown = false
    private var gestureCounter = 0
    /// Where the tiled windows really were when the mouse button went down. Compared with where they are after the
    /// button is released: a window whose size changed was resized by the user.
    private var gestureBaseline: [WindowID: CGRect]?

    func mouseButton(isDown: Bool) {
        mouseIsDown = isDown
        if isDown { beginGesture() } else { endGesture() }
    }

    private func beginGesture() {
        gestureBaseline = nil
        gestureCounter += 1
        guard let tracker, animator.isSettled else { return }
        let gesture = gestureCounter
        Task { @MainActor in
            let frames = await tracker.frameSnapshot()
            // A click that ended before the snapshot came back moved nothing.
            guard mouseIsDown, gesture == gestureCounter else { return }
            gestureBaseline = frames.filter { isTiledAndShown($0.key) }
        }
    }

    private func endGesture() {
        guard let baseline = gestureBaseline, let tracker else {
            gestureBaseline = nil
            return
        }
        gestureBaseline = nil
        Task { @MainActor in applyMouseResize(await tracker.frameSnapshot(), baseline) }
    }

    private func isTiledAndShown(_ id: WindowID) -> Bool {
        guard let managed = windows[id] else { return false }
        return !managed.floating && !managed.minimized && isVisible(managed.workspace)
            && workspace(managed.workspace).fullscreen == nil && !workspace(managed.workspace).maximized.contains(id)
    }

    /// A window that the user dragged by an edge or corner changes the layout: the dividers on the sides that moved
    /// follow the mouse, so the neighbours resize with it and the tiles stay aligned. A window that was only moved
    /// swaps places with the tiled window under the pointer, or goes back to its tile.
    private func applyMouseResize(_ frames: [WindowID: CGRect], _ baseline: [WindowID: CGRect]) {
        let tolerance: CGFloat = 3
        var changed = false
        for (id, after) in frames {
            guard let before = baseline[id], isTiledAndShown(id), let managed = windows[id] else { continue }
            let resized = abs(after.width - before.width) > tolerance || abs(after.height - before.height) > tolerance
            let moved = hypot(after.minX - before.minX, after.minY - before.minY) > tolerance
            guard resized || moved else { continue }
            changed = true
            // Put the window back into its slot even if the layout ends up unchanged, and animate from where it is.
            applier.forget(id)
            animator.place(id, at: after)
            guard resized else {
                // A window dropped with the pointer on the tile of another window of its workspace swaps places with it.
                // Otherwise it goes back to its tile.
                if moved, let pointer = CGEvent(source: nil)?.location,
                   let other = baseline.first(where: { $0.key != id && windows[$0.key]?.workspace == managed.workspace && $0.value.contains(pointer) })?.key {
                    swapWindows(id, other)
                }
                continue
            }
            let workspace = workspace(managed.workspace)
            let context = layoutContext(forWorkspace: managed.workspace)
            let edges: [(Direction, CGFloat)] = [
                (.left, before.minX - after.minX), (.right, after.maxX - before.maxX),
                (.up, before.minY - after.minY), (.down, after.maxY - before.maxY),
            ]
            for (direction, delta) in edges where abs(delta) > tolerance {
                _ = workspace.engine.perform(.resizeEdge(direction, delta), focused: id, in: context)
            }
        }
        if changed { relayout() }
    }

    // MARK: - Lookups

    /// The window that a selector names: `focused`, `app:<name>` (bundle id or app name, exact, ignoring case),
    /// `title:<regex>` (matched anywhere in the title) or `pid:<n>`. With several matches the focused window wins when
    /// it is one, then the most recently used one on the focused workspace, then the lowest id.
    func window(matching selector: String) -> WindowID? {
        if selector == "focused" { return focused }
        let matches: [WindowID]
        if selector.hasPrefix("app:") {
            let name = String(selector.dropFirst(4))
            matches = windows.filter {
                $0.value.info.bundleID.caseInsensitiveCompare(name) == .orderedSame
                    || $0.value.info.appName.caseInsensitiveCompare(name) == .orderedSame
            }.map(\.key)
        } else if selector.hasPrefix("title:") {
            let pattern = String(selector.dropFirst(6))
            matches = windows.filter { $0.value.info.title.range(of: pattern, options: .regularExpression) != nil }.map(\.key)
        } else if selector.hasPrefix("pid:"), let pid = Int32(selector.dropFirst(4)) {
            matches = windows.filter { $0.value.info.pid == pid }.map(\.key)
        } else {
            return nil
        }
        let recent = focusedWorkspace?.history ?? []
        func rank(_ id: WindowID) -> (Int, Int, WindowID) {
            (id == focused ? 0 : 1, recent.firstIndex(of: id) ?? Int.max, id)
        }
        return matches.min { rank($0) < rank($1) }
    }

    func window(at point: CGPoint) -> WindowID? {
        for monitor in monitors {
            let name = activeWorkspace(of: monitor)
            for (id, managed) in windows where managed.workspace == name && !managed.minimized {
                if currentFrame(of: id)?.contains(point) == true { return id }
            }
        }
        return nil
    }

    func monitor(containing point: CGPoint) -> Monitor? {
        monitors.first { $0.frame.contains(point) }
    }

    func tiledIDs(of workspace: Workspace) -> [WindowID] {
        workspace.engine.windows
    }
}

private extension ManagedWindow {
    @MainActor func workspaceVisible(_ manager: WindowManager) -> Bool {
        manager.isVisible(workspace)
    }
}
