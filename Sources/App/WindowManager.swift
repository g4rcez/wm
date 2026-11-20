import AppKit
import Common
import Core
import Platform
import Scripting

struct ManagedWindow {
    var info: WindowInfo
    var workspace: String
    var floating: Bool
    var minimized = false
    /// The window is in macOS fullscreen, in a Space of its own: wm leaves it alone until it comes back.
    var nativeFullscreen = false
    /// The window that took the place of this one (window swallowing): this window is parked until that one closes.
    var swallowedBy: WindowID?
    /// The terminal window that this window took the place of.
    var swallows: WindowID?
    /// Minimized, fullscreen and swallowed windows have no place in the layout.
    var isOutOfLayout: Bool { minimized || nativeFullscreen || swallowedBy != nil }
    /// Where a floating window lives; restored when its workspace is shown again.
    var floatFrame: CGRect?
    /// The frame that a maximized floating window had; `window maximize` again puts it back.
    var floatRestore: CGRect?
    /// The window shows on every workspace that its monitor shows (`window sticky`). Only a floating window is sticky.
    var sticky = false
    /// The monitor that a sticky window follows.
    var stickyMonitor: UInt32?
    /// The color of the focus border of this window, from a rule: one color, or two or more for a gradient. `nil`: the config's.
    var borderColors: [Color]?
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
    /// The zen mode: only one window shows, centered. The layout itself is not changed. Not saved.
    var zen = false

    /// The state to save: a `floating` workspace keeps a tiling engine for the windows that were tiled by hand.
    var savedLayout: LayoutState {
        if kind == .floating, case .tiling(let state) = engine.state { return .floating(state) }
        return engine.state
    }

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
    /// The display with the menu bar.
    var isMain = false
}

/// What a restore after a reboot still waits for. The ids of the saved state are old, so every saved window stands in the
/// layouts under a placeholder id until its app opens a window that takes its place.
private struct RebootRestore {
    /// The saved windows that no open window has taken, by their place in the saved list.
    var waiting: [Int: SavedWindow]
}

/// All window state and the layout pipeline. Everything here runs on the main actor.
@MainActor
final class WindowManager {
    var settings = Settings()
    /// The frames drawn on the picker grid. They are tiling templates and live beside the config ones.
    var customTemplates = CustomTemplates.load(from: StateStore.templatesURL)
    var rules: [WindowRule] = []
    /// Layout per workspace from `wm.workspace`; other workspaces use `settings.layout`.
    private(set) var workspaceLayouts: [String: LayoutKind] = [:]
    /// What `wm.workspace` set per workspace: monitor binding, default, and the settings it changes.
    private(set) var workspaceRules: [String: WorkspaceRule] = [:]

    private(set) var windows: [WindowID: ManagedWindow] = [:]
    private(set) var workspaces: [String: Workspace] = [:]
    private(set) var monitors: [Monitor] = []
    private var displayMemory = DisplayMemory()
    /// The displays that the last `displays_changed` was for, and the pending announcement of a newer set.
    private var announcedDisplays: Set<UInt32>?
    private var displayAnnouncement: DispatchWorkItem?
    private(set) var focused: WindowID?
    private(set) var focusedMonitorID: UInt32 = 0 {
        didSet { if oldValue != focusedMonitorID, oldValue != 0 { previousMonitorID = oldValue } }
    }
    /// The monitor that had the focus before the current one (`focus monitor last`).
    private(set) var previousMonitorID: UInt32?
    private(set) var previousWorkspace: String?
    /// Every window that had the focus, the most recent first (`switcher --all`).
    private(set) var recent: [WindowID] = []
    /// Window marks, by name. They are saved with the layout, and go when the window closes.
    private(set) var marks: [String: WindowID] = [:]
    /// The special workspace shown in place of the normal workspace, per monitor id. The normal workspace stays the
    /// monitor's workspace and comes back when the special one hides.
    private(set) var specials: [UInt32: String] = [:]
    /// The active binding mode ("main" by default).
    private var modes = ModeStack()
    var mode: String { modes.current }
    var modeNames: Set<String> = ["main"]

    let events = EventHub()
    /// Called after every layout pass with the workspace and layout shown on the focused monitor.
    /// Tells the menu bar the workspace in focus, its layout, and the text of the icon.
    var onRelayout: ((_ workspace: String?, _ layout: LayoutKind?, _ label: [StatusSegment]) -> Void)?
    /// The text that `wm menubar set` put in the icon in place of the automatic one. `nil`: the automatic text.
    private(set) var menuLabelOverride: String?
    var runRuleCommand: ((_ command: [String], _ window: WindowID) -> Void)?
    /// Called after the binding mode is set (also to the mode it already was), for the menu bar icon and the label.
    var onModeChange: ((_ mode: String) -> Void)?

    private var tracker: AppTracker?
    let applier = FrameApplier()
    var animator = Animator()
    private let border = BorderOverlay()
    private let backdrop = SpecialBackdrop()
    private let tabIndicator = TabIndicatorOverlay()
    private var clock: DisplayClock?
    private var lastTick = CACurrentMediaTime()
    private var refreshing = false
    private var refreshAgain = false
    private var lastVisible: Set<WindowID> = []
    /// Windows of a shown workspace that a layout parked at the hidden corner (a scrolling strip does that at the
    /// boundary to the other strip). They jump to and from the corner instead of sweeping across the screen.
    private var lastParked: Set<WindowID> = []
    /// Where each window last was while its workspace was shown; used to bring parked windows back on quit.
    private var lastShownFrame: [WindowID: CGRect] = [:]

    /// The state of the previous daemon, until the windows that are still open took their places.
    private var pendingRestore: SavedState?
    /// Windows that `detect` took from `pendingRestore`; `finishRestore` builds their layouts.
    private var adopted: Set<WindowID> = []
    /// After a reboot: the saved windows whose apps have not opened them yet (see `beginRebootRestore`).
    private var reboot: RebootRestore?
    private var rebootStarted = false
    private var spawnClaims = SpawnClaims<WindowRule>()
    /// Which dynamic rules (indices in `rules`) matched each window at the last look, and how the window was before they applied.
    /// When a terminal window was swallowed (`systemUptime`). The focus that macOS still reports on it for a moment is not a request to bring it back.
    private var swallowedAt: [WindowID: TimeInterval] = [:]
    /// A workspace switch or a special workspace toggle that the next layout pass slides in (`animations.workspaces.style`).
    private var pendingSlide: (kind: SlideKind, workspace: String, forward: Bool)?
    private enum SlideKind { case workspace, special }
    private var dynamicTracker = DynamicRuleTracker()
    private var dynamicSaved: [WindowID: (floating: Bool, floatFrame: CGRect?, border: [Color]?)] = [:]
    /// The window that had the focus when a window with `focus = false` opened: it gets the focus back.
    private var refocusAfterOpen: WindowID?
    private var saveTimer: Timer?
    private var lastSaved: Data?
    /// What `wm window remember` keeps. A window that opens after the first scan gets the entry that matches it.
    private(set) var memory = MemoryStore.load()
    /// Where the floating windows were when they closed (see `FloatMemory`).
    private var floatMemory = FloatMemoryStore.load()
    /// The windows that were open when the daemon started are not moved by the memory.
    private var didFirstScan = false
    /// New windows that `detect` left alone, so that the log says it once for each of them.
    private var skippedWindows: Set<WindowID> = []

    init() {
        pendingRestore = StateStore.load()
        // The config layouts of the last run are what "changed" is measured against when the config loads.
        workspaceLayouts = pendingRestore?.configLayouts ?? [:]
    }

    // MARK: - Start

    func start() {
        tracker = AppTracker { [weak self] in self?.scheduleRefresh() }
        updateTitleWatching()
        applier.watcher = { [weak self] pid in self?.tracker?.watcher(for: pid) }
        scheduleRefresh()
    }

    func apply(
        settings new: Settings, rules: [WindowRule], workspaceLayouts newLayouts: [String: LayoutKind] = [:],
        workspaceRules newRules: [String: WorkspaceRule] = [:]
    ) {
        let layoutChanged = new.layout != settings.layout
        settings = new
        if let saved = pendingRestore, saved.mode != SavedState.workspaceMode { pendingRestore = nil }
        self.rules = rules
        updateTitleWatching()
        animator.enabled = new.animations.enabled
        animator.rate = new.animations.windows.rate ?? new.animations.rate
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
        updateBackdrop()
        scheduleRefresh()
    }

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
        return monitor(matching: spec)
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
        // Asleep or locked: displays and apps are not stable. Nothing is read or moved until the tracker says so.
        guard let tracker, !tracker.isPaused else { return }
        tracker.syncWatchers()
        let (infos, unread) = await tracker.snapshot()
        let focusedID = await tracker.focusedWindow()
        // The system can fall asleep while the apps are read: the answers are then not trustworthy.
        guard !tracker.isPaused else { return }
        updateMonitors()
        beginRebootRestore()
        reconcile(infos, unread: unread)
        finishRestore()
        if let previous = refocusAfterOpen {
            refocusAfterOpen = nil
            if windows[previous] != nil { focus(previous) }
        } else if let focusedID, windows[focusedID] != nil, focusedID != focused {
            didFocus(focusedID)
        }
        relayout()
        didFirstScan = true
    }

    private func updateMonitors() {
        let displays = Displays.all().sorted { $0.frame.minX < $1.frame.minX }
        // No display at all (the system is waking up): keep what is known.
        guard !displays.isEmpty else { return }
        let mainIndex = displays.firstIndex(where: \.isMain) ?? 0
        var next: [Monitor] = []
        for (displayIndex, display) in displays.enumerated() {
            let existing = monitors.first { $0.id == display.id }
            let taken = next.map(\.workspace)
            let stays = Set(taken).union(monitors.filter { old in displays.contains { $0.id == old.id } }.map(\.workspace))
            let workspace = existing?.workspace ?? displayMemory.returning(display.id, shown: stays)
                ?? restoredWorkspace(of: display.id, name: display.name, taken: taken)
                ?? defaultWorkspace(display: displayIndex, name: display.name, main: mainIndex, taken: taken)
                ?? unusedWorkspaceName(taken: taken, display: displayIndex, name: display.name, main: mainIndex)
            next.append(Monitor(id: display.id, name: display.name, frame: display.frame, workArea: display.workArea, workspace: workspace, isMain: display.isMain))
            _ = self.workspace(workspace)
        }
        // A monitor that went away (lid closed, display asleep, unplugged) takes nothing with it: its workspace keeps its
        // windows, and the display shows it again when it comes back. A window moves only when the user asks.
        for old in monitors where !next.contains(where: { $0.id == old.id }) {
            displayMemory.lost(old.id, workspace: old.workspace)
        }
        monitors = next
        announceDisplays(next)
        setSpecials(specials.filter { shown in next.contains { $0.id == shown.key } })
        if !monitors.contains(where: { $0.id == focusedMonitorID }) {
            focusedMonitorID = monitors.first(where: { $0.frame.origin == .zero })?.id ?? monitors.first?.id ?? 0
        }
    }

    /// `displays_changed` says that the set of displays is not the one that it announced last (the first scan counts). A dock or
    /// an undock changes the set more than once in a short time, so the event waits 0.5 s and only the last set goes out.
    private func announceDisplays(_ monitors: [Monitor]) {
        let ids = Set(monitors.map(\.id))
        guard ids != announcedDisplays else { return }
        announcedDisplays = ids
        displayAnnouncement?.cancel()
        let names = monitors.map { LuaValue.string($0.name) }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.events.emit("displays_changed", ["count": .number(Double(names.count)), "monitors": .array(names)])
            }
        }
        displayAnnouncement = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// The workspace that a rule makes the default of this display (`default = true` with a matching `monitor`).
    private func defaultWorkspace(display index: Int, name: String, main: Int, taken: [String]) -> String? {
        workspaceRules.sorted { $0.key < $1.key }.first { entry in
            entry.value.isDefault && !taken.contains(entry.key)
                && entry.value.monitor.map { MonitorSelector.matches($0, index: index, name: name, mainIndex: main) } == true
        }?.key
    }

    /// First numeric name (1, 2, ...) that no monitor shows, and that no rule binds to another monitor.
    private func unusedWorkspaceName(taken: [String], display index: Int, name: String, main: Int) -> String {
        let used = Set(monitors.map(\.workspace)).union(taken)
        return (1...).lazy.map(String.init).first { candidate in
            !used.contains(candidate)
                && (workspaceRules[candidate]?.monitor.map { MonitorSelector.matches($0, index: index, name: name, mainIndex: main) } ?? true)
        }!
    }

    func workspace(_ name: String) -> Workspace {
        if let existing = workspaces[name] { return existing }
        let created = Workspace(name: name, kind: workspaceLayouts[name] ?? settings.layout, settings: settings(forWorkspace: name))
        workspaces[name] = created
        return created
    }

    private func reconcile(_ infos: [WindowInfo], unread: Set<pid_t>) {
        var seen: Set<WindowID> = []
        for info in infos {
            seen.insert(info.id)
            if var managed = windows[info.id] {
                let titleChanged = info.title != managed.info.title
                if titleChanged {
                    events.emit("window_title", ["id": .number(Double(info.id)), "app": .string(info.bundleID), "title": .string(info.title)])
                }
                managed.info = info
                if info.isMinimized != managed.minimized { setMinimized(info.id, info.isMinimized) }
                if info.isFullscreen != managed.nativeFullscreen { setNativeFullscreen(info.id, info.isFullscreen) }
                windows[info.id]?.info = managed.info
                // A snapshot can be older than a workspace switch: never save a parked frame as the home frame.
                let parked = info.frame.minX >= hiddenCorner().x - 1 && info.frame.minY >= hiddenCorner().y - 1
                // A floating window in fullscreen keeps the frame it will go back to, not the one that fills the screen.
                if managed.floating, !managed.isOutOfLayout, !parked, managed.workspaceVisible(self),
                   workspace(managed.workspace).fullscreen != info.id {
                    windows[info.id]?.floatFrame = info.frame
                }
                // Last, because it can change what `managed` says (floating, workspace).
                if titleChanged { reevaluateDynamicRules(info.id) }
                continue
            }
            detect(info)
        }
        skippedWindows.formIntersection(seen)
        // A window that is not listed is not always gone: an app that could not be read says nothing about its windows, and the
        // Accessibility API lists only the windows of the active Space (so every other window is missing while one is in native
        // fullscreen). Only forget those that are gone.
        let missing = windows.keys.filter { !seen.contains($0) }
        let system = missing.isEmpty ? [] : Self.systemWindowIDs()
        for id in missing {
            let forgotten = shouldForgetMissingWindow(
                appUnreadable: windows[id].map { unread.contains($0.info.pid) } ?? false,
                inSystemList: system.contains(id), place: WindowSpace.place(of: id))
            if forgotten { forget(id) }
        }
    }

    private static func systemWindowIDs() -> Set<WindowID> {
        let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(list.compactMap { ($0[kCGWindowNumber as String] as? Int).map { WindowID($0) } })
    }

    private func detect(_ info: WindowInfo) {
        guard info.kind != .ignored, !info.isFullscreen else {
            // The window is not managed, so no rule and no memory reaches it. The log has to say why.
            if didFirstScan, skippedWindows.insert(info.id).inserted {
                let app = info.bundleID.isEmpty ? "(no bundle id)" : info.bundleID
                Log.write(
                    .debug,
                    "window skipped: id=\(info.id) app=\(app) name=\(info.appName) title=\(info.title.debugDescription) role=\(info.role) subrole=\(info.subrole.isEmpty ? "(none)" : info.subrole) identifier=\(info.identifier.isEmpty ? "(none)" : info.identifier) fullscreen=\(info.isFullscreen)",
                    source: "window")
            }
            return
        }
        if let saved = rebootMatch(for: info) {
            adoptAfterReboot(info, as: saved)
            return
        }
        if let saved = activeRestore?.windows.first(where: { $0.id == info.id && $0.bundleID == info.bundleID }) {
            adopt(info, as: saved)
            return
        }
        var rule = matchingRule(info)
        // A window that a `wm exec` command opened gets the options of that command on top of the rules.
        if let spawn = takeSpawnRule(for: info) { rule = rule.map { $0.merging(spawn) } ?? spawn }
        // What `wm window remember` kept for this window wins over the rules.
        let remembered = didFirstScan ? memory.match(app: info.bundleID, title: info.title) : nil
        // A program that was started in a terminal takes the place of that terminal window. A rule that names the workspace says
        // where the window goes, so it does not swallow.
        let host = didFirstScan && remembered == nil && rule?.workspace == nil && rule?.monitor == nil ? swallowHost(for: info) : nil
        // A window that a rule floats opens where the last one of its app closed. Windows that were open when the daemon started
        // are not moved, and a window that `window remember` knows keeps what was remembered.
        let last = didFirstScan && remembered == nil && settings.floating.rememberPosition && rule?.float == true
            ? floatMemory.last(app: info.bundleID, title: info.title) : nil
        let home = monitor(containing: CGPoint(x: info.frame.midX, y: info.frame.midY)) ?? focusedMonitor
        let ruleMonitor = rule?.monitor.flatMap(monitor(matching:))
        let lastMonitor = last?.monitor.flatMap(monitor(matching:))
        let workspaceName = host.flatMap { windows[$0]?.workspace } ?? remembered?.workspace ?? rule?.workspace ?? ruleMonitor.map(activeWorkspace(of:)) ?? lastMonitor.map(activeWorkspace(of:))
            ?? home.map(activeWorkspace(of:)) ?? "1"
        let rememberedMonitor = remembered?.monitor.flatMap(monitor(matching:))
        let monitor = monitor(showing: workspaceName) ?? rememberedMonitor ?? focusedMonitor
        // On a `floating` workspace every window floats, unless a rule says `float = false`.
        let opening = workspace(workspaceName)
        let layout = rule?.layout.flatMap { opening.engine.windows.isEmpty ? $0 : nil } ?? opening.kind
        let floatsByDefault = layout == .floating
        var floating = remembered?.floating ?? host.flatMap { windows[$0]?.floating } ?? (info.kind == .floating || (rule?.float ?? floatsByDefault))
        var floatFrame: CGRect?
        if let remembered {
            if floating, let frame = remembered.frame, let area = monitor?.workArea { floatFrame = WindowMemory.absolute(frame, in: area) }
        } else if let host, floating, let frame = windows[host]?.floatFrame {
            floatFrame = frame
        } else if let last, let area = monitor?.workArea {
            floatFrame = WindowMemory.absolute(last.frame, in: area)
        } else if let area = monitor?.workArea, rule?.size != nil || rule?.center == true {
            floating = rule?.float != false
            floatFrame = Self.ruleFloatFrame(size: rule?.size, center: rule?.center == true, from: info.frame, in: area)
        } else if floating, floatsByDefault, didFirstScan {
            // Where the tiling layout would put it. The windows that are open already stay where they are.
            let others = windows.filter { $0.value.workspace == workspaceName && $0.value.floating && !$0.value.isOutOfLayout }.keys.sorted()
            var context = layoutContext(forWorkspace: workspaceName)
            context.gaps = settings(forWorkspace: workspaceName).gaps.effective(tiledCount: others.count + 1)
            floatFrame = tilingFrame(
                for: info.id, among: others, after: opening.history.first(where: others.contains),
                settings: settings(forWorkspace: workspaceName), context: context)
        }
        windows[info.id] = ManagedWindow(info: info, workspace: workspaceName, floating: floating, minimized: info.isMinimized, floatFrame: floatFrame ?? (floating ? info.frame : nil))
        // The dynamic rules that apply now are part of how the window opens; the window goes back to how it would be without them
        // when it stops matching.
        let dynamic = dynamicRuleIndices(for: info)
        if !dynamic.isEmpty {
            _ = dynamicTracker.update(window: info.id, matching: dynamic, now: ProcessInfo.processInfo.systemUptime)
            dynamicSaved[info.id] = (floating: info.kind == .floating || floatsByDefault, floatFrame: nil, border: nil)
        }
        windows[info.id]?.borderColors = rule?.border
        // A window that opens after the start: what `wm logs` needs to say why it was floated, tiled or moved. The first scan
        // reads every window that is open already, and says nothing.
        if didFirstScan {
            let app = info.bundleID.isEmpty ? "(no bundle id)" : info.bundleID
            Log.write(
                .debug,
                "window opened: id=\(info.id) app=\(app) name=\(info.appName) title=\(info.title.debugDescription) workspace=\(workspaceName) floating=\(floating) rule=\(Self.describe(rule))\(remembered == nil ? "" : " remembered=yes")",
                source: "window")
        }
        let target = workspace(workspaceName)
        if let layout = rule?.layout, target.engine.windows.isEmpty { target.kind = layout; target.engine = makeEngine(layout, settings: settings(forWorkspace: workspaceName)) }
        if let host {
            swallow(host, by: info.id, in: target)
        } else if !floating, !info.isMinimized {
            let anchor = target.history.first { windows[$0]?.workspace == workspaceName && !(windows[$0]?.floating ?? true) }
            let split = presplit(target, anchor: anchor, new: info.id)
            target.engine.insert(info.id, after: split)
            if let width = remembered?.columnWidth ?? rule?.width {
                _ = target.engine.perform(.columnWidth(.fraction(width)), focused: info.id, in: layoutContext(forWorkspace: workspaceName))
            }
            if let size = remembered?.pseudo, target.kind == .tiling { target.pseudo[info.id] = size }
            if remembered?.maximized ?? (rule?.maximize == true) { maximizeOnOpen(info.id, in: target) }
        }
        if remembered == nil, rule?.focus == false, let previous = focused, previous != info.id { refocusAfterOpen = previous }
        animator.seed(info.id, at: info.frame)
        events.emit("window_open", ["id": .number(Double(info.id)), "app": .string(info.bundleID), "title": .string(info.title), "workspace": .string(workspaceName)])
        var commands = rule?.commands ?? []
        if remembered?.strip == .vertical, !floating, target.kind == .scrolling { commands.append("window send strip vertical") }
        for command in commands { runRuleCommand?(command.split(separator: " ").map(String.init), info.id) }
        if let remembered {
            if remembered.sticky == true, floating {
                windows[info.id]?.sticky = true
                windows[info.id]?.stickyMonitor = monitor?.id
            }
            for name in remembered.marks { setMark(name, on: info.id) }
            // The window that comes back gets the focus, and its workspace is shown.
            focus(info.id)
        }
    }

    // MARK: - Memory

    /// `window remember`: keeps how the window is now, for the next window of this app (and, with `withTitle`, this title).
    /// `nil` when the window has no place in the layout (minimized or in native fullscreen).
    func rememberWindow(_ id: WindowID, withTitle: Bool) -> MemorizedWindow? {
        guard let managed = windows[id], !managed.isOutOfLayout else { return nil }
        let space = workspace(managed.workspace)
        let shown = monitor(showing: managed.workspace)
        var frame: RelativeFrame?
        if managed.floating, let area = (shown ?? focusedMonitor)?.workArea, let current = managed.floatFrame ?? currentFrame(of: id) {
            frame = WindowMemory.relative(current, in: area)
        }
        let scrolling = managed.floating ? nil : space.engine as? ScrollingEngine
        let strip = scrolling?.strip(of: id)
        let entry = MemorizedWindow(
            app: managed.info.bundleID, appName: managed.info.appName, title: withTitle ? managed.info.title : nil,
            workspace: managed.workspace, monitor: shown?.name, floating: managed.floating, frame: frame, maximized: isMaximized(id),
            pseudo: space.pseudo[id], columnWidth: strip == .horizontal ? scrolling?.columnSize(of: id) : nil, strip: strip,
            marks: marks(of: id), sticky: managed.sticky ? true : nil)
        memory.remember(entry)
        saveMemory()
        return entry
    }

    /// `window forget`: removes the entry of the window's app (or of its app and title). `false` when there was none.
    func forgetWindow(_ id: WindowID, withTitle: Bool) -> Bool {
        guard let info = windows[id]?.info else { return false }
        let removed = memory.forget(app: info.bundleID, title: withTitle ? info.title : nil)
        if removed { saveMemory() }
        return removed
    }

    /// `memory forget`: removes the entries of the app that `name` is the bundle id or the name of; no window is needed.
    func forgetMemory(appNamed name: String, title: String?, allTitles: Bool) -> [MemorizedWindow] {
        let removed = memory.forget(appNamed: name, title: title, allTitles: allTitles)
        if !removed.isEmpty { saveMemory() }
        return removed
    }

    /// `memory clear`: removes every entry. Returns how many there were.
    func clearMemory() -> Int {
        let count = memory.clear()
        if count > 0 { saveMemory() }
        return count
    }

    private func saveMemory() {
        do { try MemoryStore.write(memory) } catch { Log.write(.error, "cannot save \(MemoryStore.url.path): \(error)", source: "memory", prefix: "wmd") }
    }

    /// `smart_split` and `split_under_pointer`: the new window opens on the side of a tile that the pointer is nearest to. With
    /// `split_under_pointer` that tile is the one under the pointer; else it is the anchor (the focused tile), and only
    /// when the pointer is over it. A side that `layout preselect` set wins. Returns the tile that the window splits.
    private func presplit(_ space: Workspace, anchor: WindowID?, new id: WindowID) -> WindowID? {
        let tiling = settings(forWorkspace: space.name).tiling
        guard space.kind == .tiling, tiling.smartSplit || tiling.splitUnderPointer,
              let engine = space.engine as? DwindleEngine, engine.preselection == nil,
              let pointer = CGEvent(source: nil)?.location else { return anchor }
        var chosen = anchor
        if tiling.splitUnderPointer {
            var frames: [WindowID: CGRect] = [:]
            for other in engine.windows where other != id { frames[other] = currentFrame(of: other) }
            chosen = windowUnder(pointer, in: frames) ?? anchor
        }
        guard let chosen, let frame = currentFrame(of: chosen), frame.contains(pointer) else { return anchor }
        _ = space.engine.perform(.preselect(smartSplitSide(of: frame, at: pointer)), focused: chosen, in: layoutContext(forWorkspace: space.name))
        return chosen
    }

    // MARK: - Saved state

    /// The previous state, unless it comes from the removed native mode.
    private var activeRestore: SavedState? {
        pendingRestore.flatMap { $0.mode == SavedState.workspaceMode ? $0 : nil }
    }

    private func restoredWorkspace(of display: UInt32, name: String, taken: [String]) -> String? {
        guard let saved = activeRestore else { return nil }
        // After a reboot the ids of the displays can change, so a display that is the only one with its name is known by
        // the name.
        if !StateStore.isSameBoot(saved.bootTime) {
            let named = (saved.monitorNames ?? [:]).filter { $0.value == name }
            if named.count == 1, let key = named.keys.first, let workspace = saved.monitors[key], !taken.contains(workspace) { return workspace }
        }
        guard let workspace = saved.monitors[String(display)], !taken.contains(workspace) else { return nil }
        return workspace
    }

    // MARK: - Restore after a reboot

    /// After a reboot the window ids of the saved state are not the ids of the windows that open, and the apps open one by
    /// one over the next minute. So the saved layouts come back at once, every saved window under a placeholder id
    /// (`Placeholder`), and each window that opens takes the place of the saved window of its app with the same title
    /// (see `bestRestoreMatch`). Windows that never come back leave their place after `rebootPatience`. Nothing is saved
    /// until then, so the good state is not replaced by the half-empty one of a start in progress.
    private func beginRebootRestore() {
        guard !rebootStarted, let saved = activeRestore, !StateStore.isSameBoot(saved.bootTime) else { return }
        rebootStarted = true
        pendingRestore = nil
        var mapping: [WindowID: WindowID] = [:]
        for entry in saved.windows { mapping[entry.id] = Placeholder.id(for: entry.id) }
        for (name, savedSpace) in saved.workspaces {
            let space = workspace(name)
            space.kind = savedSpace.layout.kind
            var engine = makeEngine(restoring: savedSpace.layout, settings: settings(forWorkspace: name))
            engine.relabel(mapping)
            space.engine = engine
            space.history = savedSpace.history.compactMap { mapping[$0] }
            space.maximized = Set(savedSpace.maximized.compactMap { mapping[$0] })
            space.fullscreen = savedSpace.fullscreen.flatMap { mapping[$0] }
            // A layout that the config changed since the save wins over the saved one.
            if let kind = workspaceLayouts[name], saved.configLayouts[name] != kind, kind != space.kind { rebuild(space, as: kind) }
        }
        reboot = RebootRestore(waiting: Dictionary(uniqueKeysWithValues: saved.windows.enumerated().map { ($0.offset, $0.element) }))
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.rebootPatience * 1_000_000_000))
            finishRebootRestore()
        }
    }

    private static let rebootPatience: TimeInterval = 120

    /// The saved window that a new window takes the place of, and the end of its wait.
    private func rebootMatch(for info: WindowInfo) -> SavedWindow? {
        guard let waiting = reboot?.waiting else { return nil }
        let candidates = waiting.map {
            RestoreCandidate(key: $0.key, bundleID: $0.value.bundleID, title: $0.value.title ?? "", order: $0.value.order ?? $0.key)
        }
        guard let best = bestRestoreMatch(bundleID: info.bundleID, title: info.title, among: candidates) else { return nil }
        let saved = waiting[best.key]
        reboot?.waiting[best.key] = nil
        return saved
    }

    /// The window keeps the workspace, the floating state, the marks and the place in the layout of the saved window. No rule
    /// or `window_open` hook runs for it.
    private func adoptAfterReboot(_ info: WindowInfo, as saved: SavedWindow) {
        let placeholder = Placeholder.id(for: saved.id)
        windows[info.id] = ManagedWindow(
            info: info, workspace: saved.workspace, floating: saved.floating, minimized: info.isMinimized,
            floatFrame: saved.floatFrame ?? (saved.floating ? info.frame : nil), sticky: saved.sticky == true, stickyMonitor: saved.stickyMonitor)
        for name in saved.marks ?? [] { marks[name] = info.id }
        let space = workspace(saved.workspace)
        space.engine.relabel([placeholder: info.id])
        space.history = space.history.map { $0 == placeholder ? info.id : $0 }
        if space.maximized.remove(placeholder) != nil { space.maximized.insert(info.id) }
        if space.fullscreen == placeholder { space.fullscreen = info.id }
        if saved.floating || info.isMinimized {
            space.engine.remove(info.id)
        } else if !space.engine.windows.contains(info.id) {
            // The saved layout had no place for it (the layout changed): it joins like a new window.
            space.engine.insert(info.id, after: space.history.first { $0 != info.id && windows[$0] != nil })
        }
        animator.seed(info.id, at: info.frame)
        if reboot?.waiting.isEmpty == true { finishRebootRestore() }
    }

    /// The saved windows that did not come back give up their places, and saving starts again.
    private func finishRebootRestore() {
        guard reboot != nil else { return }
        reboot = nil
        for space in workspaces.values {
            for id in space.engine.windows where Placeholder.isPlaceholder(id) { space.engine.remove(id) }
            space.history.removeAll { Placeholder.isPlaceholder($0) }
            space.maximized = space.maximized.filter { !Placeholder.isPlaceholder($0) }
            if let full = space.fullscreen, Placeholder.isPlaceholder(full) { space.fullscreen = nil }
        }
        relayout()
        saveState()
    }

    /// A window of the previous run is not new: it keeps its workspace and floating state, and no rule or `window_open`
    /// hook runs for it. Its place in the layout comes with `finishRestore`.
    private func adopt(_ info: WindowInfo, as saved: SavedWindow) {
        windows[info.id] = ManagedWindow(
            info: info, workspace: saved.workspace, floating: saved.floating, minimized: info.isMinimized,
            floatFrame: saved.floatFrame ?? (saved.floating ? info.frame : nil), sticky: saved.sticky == true, stickyMonitor: saved.stickyMonitor)
        for name in saved.marks ?? [] { marks[name] = info.id }
        _ = workspace(saved.workspace)
        adopted.insert(info.id)
        animator.seed(info.id, at: info.frame)
    }

    /// Gives each workspace that got windows back the layout it had. A saved layout holds windows that are gone, and
    /// misses windows that are new: the first are removed (the engine closes the gap), the second are inserted.
    private func finishRestore() {
        guard let saved = pendingRestore else { return }
        // A state of the removed native mode is dropped when the config loads (`apply`).
        guard saved.mode == SavedState.workspaceMode else { return }
        pendingRestore = nil
        for name in Set(adopted.compactMap { windows[$0]?.workspace }) {
            guard let savedSpace = saved.workspaces[name] else { continue }
            let space = workspace(name)
            space.kind = savedSpace.layout.kind
            space.engine = makeEngine(restoring: savedSpace.layout, settings: settings(forWorkspace: name))
            let tiled = Set(windows.filter { $0.value.workspace == name && !$0.value.floating && !$0.value.isOutOfLayout }.keys)
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
        // The place of each window in the layout, to put it back after a reboot.
        var order: [WindowID: Int] = [:]
        for name in workspaces.keys.sorted() {
            for id in workspaces[name]!.engine.windows where order[id] == nil { order[id] = order.count }
        }
        for id in windows.keys.sorted() where order[id] == nil { order[id] = order.count }
        return SavedState(
            mode: SavedState.workspaceMode,
            windows: windows.sorted { $0.key < $1.key }.map {
                SavedWindow(
                    id: $0.key, bundleID: $0.value.info.bundleID, workspace: $0.value.workspace, floating: $0.value.floating,
                    floatFrame: $0.value.floatFrame, marks: marks(of: $0.key), title: $0.value.info.title, order: order[$0.key],
                    sticky: $0.value.sticky ? true : nil, stickyMonitor: $0.value.sticky ? $0.value.stickyMonitor : nil)
            },
            workspaces: workspaces.mapValues {
                SavedWorkspace(layout: $0.savedLayout, history: $0.history, maximized: $0.maximized.sorted(), fullscreen: $0.fullscreen)
            },
            monitors: Dictionary(uniqueKeysWithValues: monitors.map { (String($0.id), $0.workspace) }),
            configLayouts: workspaceLayouts,
            bootTime: StateStore.bootTime(),
            monitorNames: Dictionary(uniqueKeysWithValues: monitors.map { (String($0.id), $0.name) }))
    }

    /// Writes the state at once. Not while the previous state waits to be used, and not with no windows: both would
    /// replace a good file with an empty one.
    func saveState() {
        saveTimer?.invalidate()
        saveTimer = nil
        guard pendingRestore == nil, reboot == nil, !windows.isEmpty else { return }
        do {
            let data = try StateStore.encode(snapshot())
            guard data != lastSaved else { return }
            try StateStore.write(data)
            lastSaved = data
        } catch {
            Log.write(.error, "cannot save state: \(error)", source: "state", prefix: "wmd")
        }
    }

    /// Layout changes come in bursts (a key held down, an animation): one write per half second at most.
    private func scheduleSave() {
        guard saveTimer == nil else { return }
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveState() }
        }
    }

    /// Options of `wm exec` for the window that the command opens: the process that was started, and the rule. A window of
    /// `options.app` may take them too. They are dropped, and logged, when no window took them within `options.timeout`.
    func expectWindow(from pid: Int32, options: ExecOptions) {
        let id = spawnClaims.add(
            pid: pid, app: options.app, value: options.rule, timeout: options.timeout, now: ProcessInfo.processInfo.systemUptime)
        DispatchQueue.main.asyncAfter(deadline: .now() + options.timeout + 0.1) { [weak self] in
            MainActor.assumeIsolated {
                guard self?.spawnClaims.expire(id: id) == true else { return }
                Log.write(.debug, "exec options expired: no window of pid \(pid) opened in \(options.timeout) s", source: "exec")
            }
        }
    }

    private func takeSpawnRule(for info: WindowInfo) -> WindowRule? {
        spawnClaims.take(
            pid: info.pid, bundleID: info.bundleID, appName: info.appName, now: ProcessInfo.processInfo.systemUptime,
            isDescendant: ProcessTree.isDescendant)
    }

    /// The monitor that a rule names: its number (1 is the leftmost) or part of its name, ignoring case.
    /// A sticky window moves to the workspace that its monitor shows now. The workspace name really changes, so every rule for
    /// floating windows (focus, raise, the switcher, the border, `wm list`) keeps working as it is.
    private func followSticky() {
        for id in windows.filter({ $0.value.sticky && !$0.value.isOutOfLayout }).keys {
            guard let managed = windows[id],
                  let monitor = monitors.first(where: { $0.id == managed.stickyMonitor }) ?? focusedMonitor else { continue }
            windows[id]?.stickyMonitor = monitor.id
            let active = activeWorkspace(of: monitor)
            guard managed.workspace != active else { continue }
            workspace(managed.workspace).history.removeAll { $0 == id }
            windows[id]?.workspace = active
        }
    }

    /// The window that the zen mode shows: the focused one of the workspace, else the most recent, else any.
    private func zenWindow(in workspace: Workspace, focused: WindowID?) -> WindowID? {
        func usable(_ id: WindowID) -> Bool { windows[id].map { $0.workspace == workspace.name && !$0.isOutOfLayout } ?? false }
        if let focused, usable(focused) { return focused }
        return workspace.history.first(where: usable) ?? workspace.engine.windows.first(where: usable)
            ?? windows.keys.sorted().first(where: usable)
    }

    /// `zen`: turns the zen mode of the focused workspace on or off (`nil`: the other one).
    func setZen(_ on: Bool?) -> Bool {
        guard let space = focusedWorkspace else { return false }
        space.zen = on ?? !space.zen
        relayout()
        return space.zen
    }

    /// A monitor named by a role, a number or part of its name (see `MonitorSelector`).
    func monitor(matching spec: String) -> Monitor? {
        let mainIndex = monitors.firstIndex(where: \.isMain) ?? 0
        return monitors.enumerated().first { MonitorSelector.matches(spec, index: $0.offset, name: $0.element.name, mainIndex: mainIndex) }?.element
    }

    /// A window that a rule opens maximized: a scrolling column fills its zone, any other layout uses the overlay.
    private func maximizeOnOpen(_ id: WindowID, in workspace: Workspace) {
        if workspace.engine is ScrollingEngine,
           workspace.engine.perform(.maximize, focused: id, in: layoutContext(forWorkspace: workspace.name)) { return }
        workspace.maximized.insert(id)
    }

    /// The settings of a rule in a few words, for the log.
    private static func describe(_ rule: WindowRule?) -> String {
        guard let rule else { return "none" }
        var parts: [String] = []
        if let name = rule.name { parts.append("name \(name)") }
        if let float = rule.float { parts.append(float ? "float" : "tile") }
        if let size = rule.size { parts.append("size \(size.width)x\(size.height)") }
        if rule.center { parts.append("center") }
        if let workspace = rule.workspace { parts.append("workspace \(workspace)") }
        if let layout = rule.layout { parts.append("layout \(layout.rawValue)") }
        if rule.maximize == true { parts.append("maximize") }
        if let width = rule.width { parts.append("width \(width)") }
        if let monitor = rule.monitor { parts.append("monitor \(monitor)") }
        if rule.focus == false { parts.append("no-focus") }
        if let border = rule.border { parts.append("border \(border.count == 1 ? "color" : "gradient")") }
        return parts.isEmpty ? "matched (no options)" : parts.joined(separator: ",")
    }

    /// Rules apply in order. A matching rule with `stop = false` lets later rules add to it; later values win.
    /// The frame of a floating window that a rule sizes and centers: `size` is a fraction of the area (or points above 1), and
    /// the window keeps its own size and place for what the rule leaves out.
    static func ruleFloatFrame(size wanted: RuleSize?, center: Bool, from frame: CGRect, in area: CGRect) -> CGRect {
        var size = frame.size
        if let wanted {
            size.width = wanted.width <= 1 ? area.width * wanted.width : wanted.width
            size.height = wanted.height <= 1 ? area.height * wanted.height : wanted.height
        }
        var origin = frame.origin
        if center { origin = CGPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2) }
        return CGRect(origin: origin, size: size)
    }

    // MARK: - Swallowing

    /// The terminal window that a new window takes the place of, if `swallow` is on and the window was started from a terminal.
    private func swallowHost(for info: WindowInfo) -> WindowID? {
        guard settings.swallow.enabled, info.kind == .standard, !info.isMinimized, !info.isFullscreen else { return nil }
        let order = recent + windows.keys.sorted().filter { !recent.contains($0) }
        let candidates = order.compactMap { id -> Swallow.Candidate? in
            guard let window = windows[id], !window.isOutOfLayout else { return nil }
            return Swallow.Candidate(id: id, pid: window.info.pid, bundleID: window.info.bundleID, appName: window.info.appName)
        }
        return Swallow.host(
            bundleID: info.bundleID, appName: info.appName, ancestors: { ProcessTree.ancestors(of: info.pid) },
            candidates: candidates, focused: focused, settings: settings.swallow)
    }

    /// `child` takes the slot of `host` in the layout and `host` is parked until `child` closes.
    private func swallow(_ host: WindowID, by child: WindowID, in workspace: Workspace) {
        guard windows[host] != nil, let opened = windows[child] else { return }
        windows[host]?.swallowedBy = child
        windows[child]?.swallows = host
        swallowedAt[host] = ProcessInfo.processInfo.systemUptime
        if !opened.floating {
            workspace.engine.relabel([host: child])
            if let size = workspace.pseudo.removeValue(forKey: host) { workspace.pseudo[child] = size }
            if workspace.maximized.remove(host) != nil { workspace.maximized.insert(child) }
            if workspace.fullscreen == host { workspace.fullscreen = child }
        }
        workspace.history.removeAll { $0 == host }
        recent.removeAll { $0 == host }
        if focused == host { focused = child }
        Log.write(.debug, "window swallowed: id=\(child) took the place of terminal id=\(host)", source: "window")
        events.emit("window_swallow", ["id": .number(Double(child)), "terminal": .number(Double(host)), "workspace": .string(workspace.name)])
    }

    /// The window that `child` swallowed comes back in the place of `child`, which is closing. `nil` when it swallowed none, or the
    /// terminal is gone.
    private func giveBackTerminal(of id: WindowID, _ child: ManagedWindow) -> WindowID? {
        guard let host = child.swallows, var terminal = windows[host], terminal.swallowedBy == id else { return nil }
        swallowedAt[host] = nil
        terminal.swallowedBy = nil
        terminal.workspace = child.workspace
        let workspace = workspace(child.workspace)
        if child.floating {
            terminal.floating = true
            terminal.floatFrame = child.floatFrame ?? terminal.floatFrame
        } else {
            terminal.floating = false
            if workspace.engine.windows.contains(id) {
                workspace.engine.relabel([id: host])
            } else {
                workspace.engine.insert(host, after: workspace.history.first { $0 != id })
            }
            if let size = workspace.pseudo[id] { workspace.pseudo[host] = size }
            if workspace.maximized.contains(id) { workspace.maximized.insert(host) }
            if workspace.fullscreen == id { workspace.fullscreen = host }
        }
        windows[host] = terminal
        Log.write(.debug, "window unswallowed: terminal id=\(host) is back, program id=\(id) closed", source: "window")
        events.emit("window_unswallow", ["id": .number(Double(host)), "program": .number(Double(id)), "workspace": .string(child.workspace)])
        return host
    }

    /// The user went to the terminal window while it was swallowed: it comes back and the program's window stays beside it.
    private func unswallow(_ host: WindowID) {
        guard var terminal = windows[host], let childID = terminal.swallowedBy else { return }
        swallowedAt[host] = nil
        terminal.swallowedBy = nil
        guard var child = windows[childID] else {
            windows[host] = terminal
            return
        }
        child.swallows = nil
        terminal.workspace = child.workspace
        let workspace = workspace(child.workspace)
        if child.floating {
            terminal.floating = true
            terminal.floatFrame = child.floatFrame.map { $0.offsetBy(dx: 40, dy: 40) }
        } else {
            terminal.floating = false
            workspace.engine.relabel([childID: host])
            workspace.engine.insert(childID, after: host)
        }
        windows[host] = terminal
        windows[childID] = child
        events.emit("window_unswallow", ["id": .number(Double(host)), "program": .number(Double(childID)), "workspace": .string(child.workspace)])
    }

    // MARK: - Dynamic rules

    /// Reports the title changes of the apps that a dynamic rule can match, as they happen. A rule without `app` can match any app.
    private func updateTitleWatching() {
        let dynamic = rules.filter(\.dynamic)
        tracker?.watchesTitles = { bundleID, name in
            dynamic.contains { rule in
                rule.app.map { $0.caseInsensitiveCompare(bundleID) == .orderedSame || $0.caseInsensitiveCompare(name) == .orderedSame } ?? true
            }
        }
        tracker?.updateTitleWatching()
    }

    /// The dynamic rules that apply to this window, as indices in `rules`. Rules are read in order and the first one with
    /// `stop` ends the search, as for a window that opens; a rule that is not dynamic can end it too.
    private func dynamicRuleIndices(for info: WindowInfo) -> [Int] {
        var found: [Int] = []
        for (index, rule) in rules.enumerated() {
            guard rule.matches(
                bundleID: info.bundleID, appName: info.appName, title: info.title,
                role: info.role, subrole: info.subrole, identifier: info.identifier) else { continue }
            if rule.dynamic { found.append(index) }
            if rule.stop { break }
        }
        return found
    }

    /// A window changed its title: the dynamic rules that match it now are applied, and the ones that stopped matching are undone.
    private func reevaluateDynamicRules(_ id: WindowID) {
        guard let managed = windows[id], !managed.isOutOfLayout else { return }
        let indices = dynamicRuleIndices(for: managed.info)
        switch dynamicTracker.update(window: id, matching: indices, now: ProcessInfo.processInfo.systemUptime) {
        case .none:
            return
        case .applied:
            let rule = indices.map { rules[$0] }.reduce(nil) { (merged: WindowRule?, next) in merged.map { $0.merging(next) } ?? next }
            if let rule { applyDynamic(rule, to: id) }
        case .reverted:
            revertDynamic(id)
        }
    }

    /// The actions of a rule that can change a window that is open: `float`, `size`, `center`, `workspace` and `monitor`. `run`,
    /// `layout`, `width`, `maximize` and `focus` are for the moment a window opens and are not repeated.
    private func applyDynamic(_ rule: WindowRule, to id: WindowID) {
        guard let managed = windows[id] else { return }
        if dynamicSaved[id] == nil { dynamicSaved[id] = (floating: managed.floating, floatFrame: managed.floatFrame, border: managed.borderColors) }
        // The rules that apply now set the color; without one, the window has the color it had before the rules.
        windows[id]?.borderColors = rule.border ?? dynamicSaved[id]?.border
        Log.write(.debug, "dynamic rule applied: id=\(id) title=\(managed.info.title.debugDescription) rule=\(Self.describe(rule))", source: "window")
        let destination = rule.workspace ?? rule.monitor.flatMap(monitor(matching:)).map(activeWorkspace(of:))
        if let destination, destination != managed.workspace {
            moveWindow(id, to: destination)
            arrive(id)
        }
        let resizes = rule.size != nil || rule.center
        if let float = rule.float ?? (resizes ? true : nil) { setFloating(id, float) }
        if resizes, windows[id]?.floating == true, let current = windows[id],
           let area = (monitor(showing: current.workspace) ?? focusedMonitor)?.workArea {
            let frame = currentFrame(of: id) ?? current.info.frame
            setFloatFrame(id, Self.ruleFloatFrame(size: rule.size, center: rule.center, from: frame, in: area))
        }
        relayout()
    }

    /// The window stopped matching: it floats or tiles as it did before. It stays on the workspace it was sent to.
    private func revertDynamic(_ id: WindowID) {
        guard let saved = dynamicSaved.removeValue(forKey: id), let managed = windows[id] else { return }
        Log.write(.debug, "dynamic rule undone: id=\(id) title=\(managed.info.title.debugDescription)", source: "window")
        if managed.floating != saved.floating { setFloating(id, saved.floating) }
        if saved.floating, let frame = saved.floatFrame { setFloatFrame(id, frame) }
        windows[id]?.borderColors = saved.border
        relayout()
    }

    private func matchingRule(_ info: WindowInfo) -> WindowRule? {
        var merged: WindowRule?
        for rule in rules {
            guard rule.matches(
                bundleID: info.bundleID, appName: info.appName, title: info.title,
                role: info.role, subrole: info.subrole, identifier: info.identifier) else { continue }
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

    /// A floating window that closes leaves its place for the next window of the app (`floating.remember_position`).
    private func rememberFloatPlace(of managed: ManagedWindow) {
        guard settings.floating.rememberPosition, managed.floating, !managed.isOutOfLayout, let frame = managed.floatFrame,
              let monitor = monitor(showing: managed.workspace) else { return }
        floatMemory.record(LastFloatFrame(
            app: managed.info.bundleID, title: managed.info.title, frame: WindowMemory.relative(frame, in: monitor.workArea), monitor: monitor.name))
        do { try FloatMemoryStore.write(floatMemory) } catch {
            Log.write(.error, "cannot save \(FloatMemoryStore.url.path): \(error)", source: "memory", prefix: "wmd")
        }
    }

    private func forget(_ id: WindowID) {
        guard let managed = windows.removeValue(forKey: id) else { return }
        let wasFocused = focused == id
        let returning = giveBackTerminal(of: id, managed)
        swallowedAt[id] = nil
        dynamicTracker.forget(id)
        dynamicSaved[id] = nil
        rememberFloatPlace(of: managed)
        lastShownFrame[id] = nil
        let workspace = workspace(managed.workspace)
        workspace.engine.remove(id)
        workspace.history.removeAll { $0 == id }
        if workspace.fullscreen == id { workspace.fullscreen = nil }
        workspace.maximized.remove(id)
        workspace.pseudo[id] = nil
        marks = marks.filter { $0.value != id }
        recent.removeAll { $0 == id }
        if focused == id { focused = workspace.history.first }
        hideSpecialIfEmpty(workspace.name)
        applier.forget(id)
        events.emit("window_close", ["id": .number(Double(id))])
        if let returning, wasFocused { focus(returning) }
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

    private func setNativeFullscreen(_ id: WindowID, _ on: Bool) {
        guard var managed = windows[id] else { return }
        managed.nativeFullscreen = on
        windows[id] = managed
        events.emit("window_fullscreen", ["id": .number(Double(id)), "fullscreen": .bool(on), "native": .bool(true)])
        let workspace = workspace(managed.workspace)
        if on {
            workspace.maximized.remove(id)
            if workspace.fullscreen == id { workspace.fullscreen = nil }
            workspace.engine.remove(id)
        } else if !managed.floating, !managed.minimized {
            workspace.engine.insert(id, after: workspace.history.first { $0 != id })
        }
    }

    // MARK: - Marks

    /// A mark names one window. Marking another window with the same name takes it away from the first.
    func setMark(_ name: String, on id: WindowID) { marks[name] = id }

    /// Removes the mark `name` (from whichever window has it), or every mark of window `id` when there is no name.
    func removeMarks(named name: String?, of id: WindowID) {
        if let name { marks[name] = nil } else { marks = marks.filter { $0.value != id } }
    }

    func marks(of id: WindowID) -> [String] { marks.filter { $0.value == id }.keys.sorted() }

    // MARK: - Focus

    var focusedMonitor: Monitor? { monitors.first { $0.id == focusedMonitorID } }

    var focusedWorkspace: Workspace? {
        focusedMonitor.map { workspace(activeWorkspace(of: $0)) }
    }

    /// Records a focus change that happened in macOS (click, Cmd-Tab) and follows it with the workspace view.
    private func didFocus(_ id: WindowID) {
        if windows[id]?.swallowedBy != nil {
            // macOS may still report the focus on the terminal for a moment after the program's window opened.
            if let at = swallowedAt[id], ProcessInfo.processInfo.systemUptime - at < 1.5 { return }
            unswallow(id)
        }
        guard let managed = windows[id] else { return }
        focused = id
        let workspace = workspace(managed.workspace)
        workspace.history.removeAll { $0 == id }
        workspace.history.insert(id, at: 0)
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
        if SpecialWorkspace.isSpecial(managed.workspace) {
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
            let hiding = SpecialWorkspace.monitorsHiding(
                onFocusOf: monitor.id, shown: specials, otherMonitors: settings.special.hideOnOtherMonitor
            ) { name in windows.values.contains { $0.workspace == name } }
            if !hiding.isEmpty { setSpecials(specials.filter { !hiding.contains($0.key) }) }
        } else if let monitor = focusedMonitor {
            // The window belongs to a hidden workspace: show that workspace where the user is looking.
            showWorkspace(managed.workspace, on: monitor.id, focusWindow: false)
        }
        publishStatus()
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
            pendingSlide = (.special, name, true)
            events.emit("special_changed", ["workspace": .string(name), "monitor": .number(Double(monitor)), "visible": .bool(true)])
        }
        updateBackdrop()
    }

    /// The dim layer behind each shown special workspace (`special.backdrop`).
    func updateBackdrop() {
        let shown = monitors.filter { specials[$0.id] != nil }.map(\.frame)
        backdrop.show(on: shown, settings.special.backdrop)
    }

    /// A shown special workspace that lost its last window hides.
    private func hideSpecialIfEmpty(_ name: String) {
        guard let monitor = specials.first(where: { $0.value == name })?.key,
              !windows.values.contains(where: { $0.workspace == name }) else { return }
        setSpecials(specials.filter { $0.key != monitor })
    }

    /// The floating windows of a workspace follow it to another monitor.
    private func relocateFloats(of name: String, from old: CGRect, to new: CGRect) {
        for (id, managed) in windows where managed.workspace == name && managed.floating {
            guard let frame = managed.floatFrame ?? currentFrame(of: id) else { continue }
            windows[id]?.floatFrame = MonitorGeometry.translated(frame, from: old, to: new)
        }
    }

    /// `workspace move monitor`: the workspace of the focused monitor goes to `target`, which shows it from now on. The
    /// focused monitor shows the lowest free workspace number instead. Returns the reason when it cannot be done.
    func moveWorkspace(to target: Monitor) -> String? {
        guard let source = focusedMonitor, source.id != target.id,
              let from = monitors.firstIndex(where: { $0.id == source.id }),
              let to = monitors.firstIndex(where: { $0.id == target.id }) else { return nil }
        let moving = monitors[from].workspace
        if let bound = boundMonitor(of: moving), bound.id != target.id {
            return "workspace \(moving) is bound to the monitor '\(bound.name)' by a wm.workspace rule"
        }
        let mainIndex = monitors.firstIndex(where: \.isMain) ?? 0
        let replacement = unusedWorkspaceName(taken: [], display: from, name: source.name, main: mainIndex)
        setSpecials(specials.filter { $0.key != source.id && $0.key != target.id })
        relocateFloats(of: moving, from: source.workArea, to: target.workArea)
        let displaced = monitors[to].workspace
        monitors[to].workspace = moving
        monitors[from].workspace = replacement
        _ = workspace(replacement)
        previousWorkspace = displaced
        events.emit("workspace_changed", ["workspace": .string(moving), "previous": .string(displaced), "monitor": .number(Double(target.id))])
        events.emit("workspace_changed", ["workspace": .string(replacement), "previous": .string(moving), "monitor": .number(Double(source.id))])
        focusMonitor(target.id)
        return nil
    }

    func showWorkspace(_ name: String, on requested: UInt32, focusWindow: Bool = true) {
        _ = workspace(name)
        // A workspace that a rule binds to a monitor is shown there, and the focus goes with it.
        let monitorID = boundMonitor(of: name)?.id ?? requested
        guard let index = monitors.firstIndex(where: { $0.id == monitorID }) else { return }
        setSpecials(specials.filter { $0.key != monitorID })
        if let other = monitors.firstIndex(where: { $0.workspace == name }), other != index {
            // Already shown on another monitor: swap the two, as AeroSpace does. Floating windows go along.
            relocateFloats(of: name, from: monitors[other].workArea, to: monitors[index].workArea)
            relocateFloats(of: monitors[index].workspace, from: monitors[index].workArea, to: monitors[other].workArea)
            monitors[other].workspace = monitors[index].workspace
        }
        let old = monitors[index].workspace
        monitors[index].workspace = name
        focusedMonitorID = monitorID
        if old != name {
            previousWorkspace = old
            pendingSlide = (.workspace, name, WorkspaceSlide.isForward(from: old, to: name))
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

    /// `anchor` is the window that the moved window opens beside in the layout; the default is the one that had the
    /// focus last on the destination.
    func moveWindow(_ id: WindowID, to name: String, after anchor: WindowID? = nil) {
        guard var managed = windows[id], managed.workspace != name else { return }
        let source = workspace(managed.workspace)
        source.engine.remove(id)
        source.history.removeAll { $0 == id }
        if source.fullscreen == id { source.fullscreen = nil }
        source.maximized.remove(id)
        source.pseudo[id] = nil
        let destination = workspace(name)
        let previous = managed.workspace
        managed.workspace = name
        windows[id] = managed
        events.emit("window_moved", ["id": .number(Double(id)), "workspace": .string(name), "previous": .string(previous)])
        if !managed.floating, !managed.isOutOfLayout {
            destination.engine.insert(id, after: anchor ?? destination.history.first)
        }
        if focused == id { focused = source.history.first }
        hideSpecialIfEmpty(source.name)
    }

    /// Where a floating window goes at the next layout pass.
    func setFloatFrame(_ id: WindowID, _ frame: CGRect) { windows[id]?.floatFrame = frame }

    /// The frame that `window maximize` puts back for a floating window (`nil`: none).
    func setFloatRestore(_ id: WindowID, _ frame: CGRect?) { windows[id]?.floatRestore = frame }

    func setFloating(_ id: WindowID, _ floating: Bool) {
        guard var managed = windows[id], managed.floating != floating else { return }
        let workspace = workspace(managed.workspace)
        managed.floating = floating
        if floating {
            workspace.maximized.remove(id)
            workspace.pseudo[id] = nil
            workspace.engine.remove(id)
            // A window that floats goes to the middle of its screen.
            let frame = currentFrame(of: id) ?? managed.info.frame
            if let area = (monitor(showing: managed.workspace) ?? focusedMonitor)?.workArea {
                managed.floatFrame = floatFrame(current: frame, in: area)
            } else {
                managed.floatFrame = frame
            }
        } else {
            workspace.engine.insert(id, after: workspace.history.first { $0 != id })
        }
        windows[id] = managed
        events.emit("window_floating", ["id": .number(Double(id)), "floating": .bool(floating)])
    }

    /// Turns `sticky` on or off. A sticky window follows the monitor that shows its workspace now.
    func setSticky(_ id: WindowID, _ on: Bool) {
        guard let managed = windows[id] else { return }
        windows[id]?.sticky = on
        windows[id]?.stickyMonitor = on ? (monitor(showing: managed.workspace) ?? focusedMonitor)?.id : nil
    }

    /// The window that gets focus when a workspace is shown: the most recently focused one.
    private func windowToFocus(in workspace: Workspace) -> WindowID? {
        return workspace.history.first(where: { windows[$0] != nil }) ?? workspace.engine.windows.first
    }

    /// A window moved to another workspace: on an empty workspace it takes the whole work area (inside the gaps), because
    /// a lone window is not full size in every layout (a scrolling column is half the width). On a workspace that has
    /// windows it joins the layout and the layout is balanced, so all windows fit. With `tile` it only joins the layout.
    func arrive(_ id: WindowID, tile: Bool = false) {
        guard let managed = windows[id], !managed.floating, !managed.isOutOfLayout else { return }
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
        guard RelativeWorkspace.words.contains(name), let current = focusedMonitor?.workspace else { return name }
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
        // A master workspace keeps its live ratio, count and orientation (unless the config changed) and the order of its windows.
        if kind == workspace.kind, let old = workspace.engine as? MasterEngine {
            workspace.engine = makeEngine(restoring: old.state, settings: settings(forWorkspace: workspace.name))
            events.emit("layout_changed", ["workspace": .string(workspace.name), "layout": .string(kind.rawValue)])
            return
        }
        let order = workspace.engine.windows
        workspace.kind = kind
        if kind == .master {
            // Not one `insert` after the other: a new window goes to the top of the stack, which would reverse the stack.
            workspace.engine = MasterEngine(settings: settings(forWorkspace: workspace.name), windows: order)
            events.emit("layout_changed", ["workspace": .string(workspace.name), "layout": .string(kind.rawValue)])
            return
        }
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
        events.emit("monitor_changed", ["monitor": .number(Double(id)), "name": .string(monitor.name), "workspace": .string(monitor.workspace)])
    }

    // MARK: - Layout

    func relayout(snapAll: Bool = false) {
        followSticky()
        var targets: [WindowID: CGRect] = [:]
        var visible: Set<WindowID> = []
        for monitor in monitors {
            // wm cannot keep the windows of a special workspace above the windows of the normal one (macOS brings
            // every window of the active app forward), so only one of the two is laid out; the other is parked.
            let workspace = workspace(activeWorkspace(of: monitor))
            let context = layoutContext(forWorkspace: workspace.name)
            let focusHere = focused.flatMap { windows[$0]?.workspace == workspace.name ? $0 : nil }
            // Zen: one window shows in the middle. The others are not visible, so they are parked like the windows of a hidden
            // workspace. A fullscreen window wins.
            if workspace.zen, workspace.fullscreen == nil, let shown = zenWindow(in: workspace, focused: focusHere) {
                targets[shown] = zenFrame(in: context.gaps.outerArea(context.viewport), width: settings.zen.width)
                visible.insert(shown)
                continue
            }
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
            for (id, managed) in windows where managed.workspace == workspace.name && managed.floating && !managed.isOutOfLayout {
                // A floating window in fullscreen keeps its own place for when it leaves fullscreen.
                targets[id] = workspace.fullscreen == id ? monitor.workArea : (managed.floatFrame ?? managed.info.frame)
                visible.insert(id)
            }
        }
        // The window under a modifier drag stays under the pointer, whatever the layout says.
        if let drag = modifierDrag, drag.followsPointer { targets[drag.window] = drag.frame }
        let corner = hiddenCorner()
        for (id, managed) in windows where !visible.contains(id) && !managed.isOutOfLayout {
            let size = animator.frames[id]?.size ?? managed.info.frame.size
            targets[id] = CGRect(origin: corner, size: size)
        }
        // A terminal window that a program swallowed waits in the corner until that program closes.
        for (id, managed) in windows where managed.swallowedBy != nil {
            let size = animator.frames[id]?.size ?? managed.info.frame.size
            targets[id] = CGRect(origin: corner, size: size)
        }
        let parkedNow = Set(visible.filter { targets[$0]?.origin == corner })
        // The windows that a workspace switch shows slide in from the side, if the config says so; the others jump.
        let slides = slideStarts(targets: targets, visible: visible, corner: corner)
        var snap = visible.symmetricDifference(lastVisible)
            .union(targets.keys.filter { !visible.contains($0) })
            .union(parkedNow).union(lastParked)
        // `animations.windows.enabled = false`: the moves inside a layout jump too.
        if !settings.animations.windows.enabled { snap.formUnion(targets.keys) }
        snap.subtract(slides.keys)
        lastVisible = visible
        lastParked = parkedNow
        for id in visible where !parkedNow.contains(id) { lastShownFrame[id] = targets[id] }
        animator.setTargets(targets, snap: snapAll ? Set(targets.keys) : snap)
        if !snapAll { for (id, slide) in slides { animator.start(id, from: slide.from, rate: slide.rate) } }
        applier.send(animator.frames, windows: windows)
        startClockIfNeeded()
        updateBorder()
        updateTabIndicator()
        publishStatus()
        scheduleSave()
    }

    /// Where the windows that a workspace switch (or a special workspace toggle) shows start their slide. Empty when the style is `none`,
    /// when animations are off, or when no free side is left (another monitor is there): those windows jump. Uses the switch once.
    private func slideStarts(
        targets: [WindowID: CGRect], visible: Set<WindowID>, corner: CGPoint
    ) -> [WindowID: (from: CGRect, rate: Double)] {
        guard let request = pendingSlide else { return [:] }
        pendingSlide = nil
        let animations = settings.animations
        let kind = request.kind == .workspace ? animations.workspaces : animations.special
        guard animations.enabled, kind.enabled, kind.style != .none,
              let monitor = monitor(showing: request.workspace) else { return [:] }
        // A special workspace has a smaller area; the slide runs along the edge of the monitor.
        let edges = layoutContext(for: monitor).sliverEdges
        var starts: [WindowID: (from: CGRect, rate: Double)] = [:]
        for id in visible where !lastVisible.contains(id) {
            guard let managed = windows[id], managed.workspace == request.workspace, let target = targets[id],
                  target.origin != corner,
                  let from = WorkspaceSlide.start(
                    of: target, viewport: monitor.workArea, style: kind.style, forward: request.forward, freeEdges: edges)
            else { continue }
            starts[id] = (from, kind.rate ?? animations.rate)
        }
        return starts
    }

    /// Tells the menu bar icon the workspace in focus, its layout, and what to write: every workspace that has windows and the
    /// one in focus (`menubar` in the config), or the text that `wm menubar set` gave.
    func publishStatus() {
        let shown = focusedWorkspace
        let floating = focused.flatMap { windows[$0] }.map { $0.floating && !$0.isOutOfLayout && ($0.sticky || $0.workspace == shown?.name) } ?? false
        var label = menuLabelOverride.map { [StatusSegment($0)] }
        if label == nil, let shown {
            // A sticky window shows on every workspace and a special workspace is not a place to go to: neither makes a workspace busy.
            var counts: [String: Int] = [:]
            for managed in windows.values where !managed.sticky && !SpecialWorkspace.isSpecial(managed.workspace) {
                counts[managed.workspace, default: 0] += 1
            }
            let all = counts.map { WorkspaceStatus(name: $0.key, layout: workspaces[$0.key]?.kind, count: $0.value) }
            let current = WorkspaceStatus(name: shown.name, layout: shown.kind, count: counts[shown.name] ?? 0)
            label = StatusLabel.segments(workspaces: all, current: current, floating: floating, settings: settings.menuBar)
        }
        onRelayout?(shown?.name, shown?.kind, label ?? [])
    }

    /// `menubar set <text>` puts the text in the icon until `menubar reset`; `nil` goes back to the automatic text.
    func setMenuLabel(_ text: String?) {
        menuLabelOverride = text
        publishStatus()
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
        // Monocle shows one window whatever the count, so smart gaps apply to it as to a lone window.
        let count = workspaces[name].map { $0.kind == .monocle ? min($0.engine.windows.count, 1) : $0.engine.windows.count } ?? 0
        let gaps = settings(forWorkspace: name).gaps.effective(tiledCount: count)
        guard let monitor = monitor(showing: name) ?? focusedMonitor else { return LayoutContext(viewport: .zero, gaps: gaps) }
        var context = layoutContext(for: monitor, gaps: gaps)
        if specials[monitor.id] == name {
            context.viewport = SpecialWorkspace.viewport(in: monitor.workArea, size: settings.special.size)
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
        clock = DisplayClock(fps: settings.animations.fps) { [weak self] in self?.tick() }
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
            clock?.stop()
            clock = nil
        }
    }

    /// The tabs of the focused window's column, when it shows tabs: a bar of one segment per window.
    /// Where `window` is among the tabs of its column (scrolling), or among the windows of the workspace (monocle). Alone, there is
    /// nothing to show.
    private func tabPosition(of window: WindowID, in engine: any LayoutEngine) -> (index: Int, count: Int)? {
        if let scrolling = engine as? ScrollingEngine {
            return scrolling.tabs(of: window).flatMap { tabs in tabs.firstIndex(of: window).map { ($0, tabs.count) } }
        }
        if let monocle = engine as? MonocleEngine, let position = monocle.position(of: window), position.count > 1 { return position }
        return nil
    }

    private func updateTabIndicator() {
        guard settings.tabIndicator.enabled, let focused, let managed = windows[focused], !managed.isOutOfLayout, !managed.floating,
              isVisible(managed.workspace), workspace(managed.workspace).fullscreen == nil,
              let (index, count) = tabPosition(of: focused, in: workspace(managed.workspace).engine),
              let frame = currentFrame(of: focused) else {
            tabIndicator.hide()
            return
        }
        tabIndicator.show(on: frame, count: count, selected: index, settings.tabIndicator)
    }

    func updateBorder() {
        guard let focused, let managed = windows[focused], !managed.isOutOfLayout, settings(forWorkspace: managed.workspace).border.enabled,
              let frame = currentFrame(of: focused), isVisible(managed.workspace) else {
            border.hide()
            return
        }
        var style = settings(forWorkspace: managed.workspace).border
        // A rule can give this window its own color: one color, or two or more for a gradient.
        if let colors = managed.borderColors, let first = colors.first {
            style.active = first
            style.gradient = colors.count >= 2 ? colors : []
        }
        border.show(around: frame, style)
    }

    /// Brings every parked window back on screen. Runs when the daemon quits, so no window stays hidden.
    func restoreAll() {
        let group = DispatchGroup()
        for (id, managed) in windows where (!lastVisible.contains(id) || lastParked.contains(id)) && (!managed.isOutOfLayout || managed.swallowedBy != nil) {
            let size = lastShownFrame[id]?.size ?? managed.info.frame.size
            let area = (monitors.first { $0.id == focusedMonitorID } ?? monitors.first)?.workArea ?? .zero
            let frame = lastShownFrame[id] ?? CGRect(
                x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height
            )
            // A window that was parked as a sliver at the screen edge comes back fully on screen.
            let inside = MonitorGeometry.clamped(frame, in: area)
            group.enter()
            watcher(for: managed.info.pid)?.setFrame(id, inside.integral) { _ in group.leave() }
        }
        _ = group.wait(timeout: .now() + 3)
    }

    func setMode(_ name: String) -> Bool {
        guard modeNames.contains(name) else { return false }
        if modes.enter(name) { modeChanged() }
        return true
    }

    /// `mode back`: the mode before this one, or `main`. Returns `false` when the mode is `main` already.
    @discardableResult
    func modeBack() -> Bool {
        guard modes.back() else { return false }
        modeChanged()
        return true
    }

    private func modeChanged() {
        events.emit("mode_changed", ["mode": .string(mode)])
        onModeChange?(mode)
    }

    func watcher(for pid: pid_t) -> AppWatcher? { tracker?.watcher(for: pid) }

    // MARK: - Mouse resize

    /// A drag with the mouse modifier: the window follows the pointer (see MouseDrag.swift).
    var modifierDrag: ModifierDrag?
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
        return !managed.floating && !managed.isOutOfLayout && isVisible(managed.workspace)
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
    /// `title:<regex>` (matched anywhere in the title), `pid:<n>` or `mark:<name>`. With several matches the focused window wins when
    /// it is one, then the most recently used one on the focused workspace, then the lowest id.
    func window(matching selector: String) -> WindowID? {
        if selector == "focused" { return focused }
        if selector.hasPrefix("mark:") { return marks[String(selector.dropFirst(5))].flatMap { windows[$0] == nil ? nil : $0 } }
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

    /// The window whose title bar (the top `trackpad.title_bar_height` points) is under `point`, when it is in front there.
    func titleBarWindow(at point: CGPoint) -> WindowID? {
        let candidates = Set(windows.filter { !$0.value.isOutOfLayout && isVisible($0.value.workspace) }.keys)
        guard let id = WindowList.topmost(at: point, among: candidates), let frame = currentFrame(of: id),
              titleBarContains(point, frame: frame, height: CGFloat(settings.trackpad.titleBarHeight)) else { return nil }
        return id
    }

    func window(at point: CGPoint) -> WindowID? {
        for monitor in monitors {
            let name = activeWorkspace(of: monitor)
            for (id, managed) in windows where managed.workspace == name && !managed.isOutOfLayout {
                if currentFrame(of: id)?.contains(point) == true { return id }
            }
        }
        return nil
    }

    /// A window that wm may not manage (a dialog, a popup, an ignored window), read from its app. `nil` when the app has no
    /// watcher (it is not a regular app) or no longer has this window.
    func readWindow(_ id: WindowID, pid: pid_t) async -> WindowInfo? {
        await tracker?.watcher(for: pid)?.snapshot()?.first { $0.id == id }
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
