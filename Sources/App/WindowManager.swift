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
    var nativeFullscreen = false
    /// Its app is hidden (Cmd-H).
    var appHidden = false
    var swallowedBy: WindowID?
    var swallows: WindowID?
    var isOutOfLayout: Bool { minimized || nativeFullscreen || appHidden || swallowedBy != nil }
    var floatFrame: CGRect?
    var floatRestore: CGRect?
    var sticky = false
    var stickyMonitor: UInt32?
    var borderColors: [Color]?
    /// Set by a rule; `nil` follows `dim.enabled`.
    var dim: Bool?
}

/// A drag of a tiled window while its neighbours make room. `original` is the layout from before the drag: every zone is tried
/// on it, so a drag that ends nowhere puts it back as it was.
struct DragDrop {
    var workspace: String
    var dragged: WindowID
    var original: any LayoutEngine
    /// The tiles of `original`: the zones are measured on them, so the windows that move aside do not move the zones.
    var tiles: [WindowID: CGRect]
    var zone: DropZone = .none
    /// macOS moves the window (a drag by its title bar): wm leaves the window alone until the drop.
    var native: Bool
}

final class Workspace {
    let name: String
    var kind: LayoutKind
    var engine: any LayoutEngine
    var history: [WindowID] = []
    var fullscreen: WindowID?
    var maximized: Set<WindowID> = []
    var pseudo: [WindowID: CGSize] = [:]
    var zen = false
    /// The work area of the monitor that showed the workspace last: its floating windows are placed in it. When the workspace
    /// shows on another monitor, they move along.
    var shownArea: CGRect?

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
    var isMain = false
}

/// Saved windows that wait for their windows to open, after a reboot or a `session open`.
private struct PendingWindows {
    var waiting: [Int: SavedWindow]
    /// The session that is opening, or `nil` after a reboot.
    var session: String?
    /// Tells a timeout whether this is still the restore that it was started for.
    var serial: Int
}

@MainActor
final class WindowManager {
    var settings = Settings() {
        didSet {
            workspaceSettingsCache.removeAll()
            // With native workspaces macOS plays the slide: no animation for workspaces asks for a swipe that jumps.
            NativeSpaces.setInstantSwitch(!(settings.animations.enabled && settings.animations.workspaces.enabled))
        }
    }
    private var workspaceSettingsCache: [String: Settings] = [:]
    var customTemplates = CustomTemplates.load(from: StateStore.templatesURL)
    var rules: [WindowRule] = []
    private(set) var workspaceLayouts: [String: LayoutKind] = [:]
    private(set) var workspaceRules: [String: WorkspaceRule] = [:] { didSet { workspaceSettingsCache.removeAll() } }

    private(set) var windows: [WindowID: ManagedWindow] = [:]
    private(set) var workspaces: [String: Workspace] = [:]
    private(set) var monitors: [Monitor] = []
    private var displayMemory = DisplayMemory()
    private var announcedDisplays: Set<UInt32>?
    private var displayAnnouncement: DispatchWorkItem?
    private(set) var focused: WindowID?
    private(set) var focusedMonitorID: UInt32 = 0 {
        didSet { if oldValue != focusedMonitorID, oldValue != 0 { previousMonitorID = oldValue } }
    }
    private(set) var previousMonitorID: UInt32?
    private(set) var previousWorkspace: String?
    private(set) var recent: [WindowID] = []
    private(set) var marks: [String: WindowID] = [:]

    private(set) var nativeBinding = NativeSpaceBinding(displays: [])
    private var nativeListings: [NativeSpaces.Listing] = []
    private var placedSpace: [WindowID: UInt64] = [:]
    private var movingUntil: [WindowID: TimeInterval] = [:]
    private lazy var switcher: SpaceSwitcher = {
        let switcher = NativeSpaces.makeSwitcher()
        switcher.log = { Log.write(.debug, $0, source: "spaces") }
        switcher.onSettled = { [weak self] _ in self?.scheduleRefresh() }
        return switcher
    }()
    var isNative: Bool { settings.workspaceMode == .native }

    private(set) var specials: [UInt32: String] = [:]
    private var modes = ModeStack()
    var mode: String { modes.current }
    var modeNames: Set<String> = ["main"]

    let events = EventHub()
    var onRelayout: ((_ workspace: String?, _ layout: LayoutKind?, _ label: [StatusSegment]) -> Void)?
    var onWorkspacesShown: ((_ shown: [UInt32: (workspace: String, special: String?)]) -> Void)?
    private(set) var menuLabelOverride: String?
    var runRuleCommand: ((_ command: [String], _ window: WindowID) -> Void)?
    var runOnEmpty: ((_ request: ExecRequest) -> Void)?
    private var pendingOnEmpty: Set<String> = []
    var onModeChange: ((_ mode: String) -> Void)?

    private var tracker: AppTracker?
    var isPaused: Bool { tracker?.isPaused == true }
    let applier = FrameApplier()
    var animator = Animator()
    private var drift = FrameDrift()
    private let border = BorderOverlay()
    private let backdrop = SpecialBackdrop()
    private let dimOverlay = DimOverlay()
    private var dimSettle: DispatchWorkItem?
    lazy var pip = PipController(manager: self)
    /// Whether the window shows on a monitor now: not on a hidden workspace, parked, minimized, hidden with its app or swallowed.
    func isOnScreen(_ id: WindowID) -> Bool { lastVisible.contains(id) && !lastParked.contains(id) }
    private let tabIndicator = TabIndicatorOverlay()
    private var clock: DisplayClock?
    private var lastTick = CACurrentMediaTime()
    private var refreshing = false
    private var refreshAgain = false
    private(set) var lastVisible: Set<WindowID> = []
    private(set) var lastParked: Set<WindowID> = []
    private var lastShownFrame: [WindowID: CGRect] = [:]

    private var pendingRestore: SavedState?
    private var adopted: Set<WindowID> = []
    private var restoring: PendingWindows?
    private var restoreSerial = 0
    var isRestoring: Bool { restoring != nil }
    var layoutHistory = LayoutHistory()
    private var rebootStarted = false
    private var spawnClaims = SpawnClaims<WindowRule>()
    private var swallowedAt: [WindowID: TimeInterval] = [:]
    private var pendingSlide: (kind: SlideKind, workspace: String, forward: Bool)?
    private enum SlideKind { case workspace, special }
    private var urgent = UrgentTracker()
    private var badgeTimer: Timer?
    private var badgeInterval: Double = 0
    private var dynamicTracker = DynamicRuleTracker()
    private var dynamicSaved: [WindowID: (floating: Bool, floatFrame: CGRect?, border: [Color]?, dim: Bool?)] = [:]
    private var refocusAfterOpen: WindowID?
    private var saveTimer: Timer?
    private var lastSaved: Data?
    private(set) var memory = MemoryStore.load()
    private var floatMemory = FloatMemoryStore.load()
    private var didFirstScan = false
    var openingHold: [WindowID: TimeInterval] = [:]
    private static let openingHoldSeconds: TimeInterval = 1.5
    private var skippedWindows: Set<WindowID> = []
    /// Since when a managed window that the scan does not list has been on no Space.
    private var goneSince: [WindowID: TimeInterval] = [:]
    /// Where the windows of apps that quit were: an app that comes back gets its windows back on their workspaces.
    private var recentlyClosed = RecentlyClosed()
    /// A refresh whose read of the windows takes longer than this is logged.
    private static let slowSnapshot: TimeInterval = 0.05

    init() {
        pendingRestore = StateStore.load()
        workspaceLayouts = pendingRestore?.configLayouts ?? [:]
    }

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
        let leavesNative = isNative && new.workspaceMode != .native
        let previousKinds = workspaces.mapValues(\.kind)
        if leavesNative { gatherWindows() }
        settings = new
        if let saved = pendingRestore, saved.mode != new.workspaceMode.rawValue { pendingRestore = nil }
        self.rules = rules
        updateTitleWatching()
        updateBadgeWatching()
        animator.enabled = new.animations.enabled
        animator.rate = new.animations.windows.rate ?? new.animations.rate
        let previousLayouts = workspaceLayouts
        workspaceLayouts = newLayouts
        workspaceRules = newRules
        for name in newRules.filter(\.value.persistent).keys { _ = workspace(name) }
        if layoutChanged || workspaces.isEmpty {
            for workspace in workspaces.values where workspace.engine.windows.isEmpty && newLayouts[workspace.name] == nil {
                workspace.kind = new.layout
                workspace.engine = makeEngine(new.layout, settings: settings(forWorkspace: workspace.name))
            }
        }
        for workspace in workspaces.values where workspace.engine.windows.isEmpty {
            workspace.engine = makeEngine(workspace.kind, settings: settings(forWorkspace: workspace.name))
        }
        for workspace in workspaces.values where !workspace.engine.windows.isEmpty {
            applySettings(to: workspace)
        }
        for (name, kind) in newLayouts where previousLayouts[name] != kind {
            let target = workspace(name)
            if target.kind != kind { rebuild(target, as: kind) }
        }
        // A layout that the config changed is not one to undo back to.
        for (name, kind) in previousKinds where workspaces[name]?.kind != kind { layoutHistory.forget(name) }
        updateBackdrop()
        scheduleRefresh()
    }

    func settings(forWorkspace name: String) -> Settings {
        guard let overrides = workspaceRules[name]?.overrides else { return settings }
        if let cached = workspaceSettingsCache[name] { return cached }
        var copy = settings
        try? applyWorkspaceOverrides(overrides, to: &copy)
        workspaceSettingsCache[name] = copy
        return copy
    }

    func boundMonitor(of name: String) -> Monitor? {
        guard let spec = workspaceRules[name]?.monitor else { return nil }
        return monitor(matching: spec)
    }

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
        guard let tracker, !tracker.isPaused else { return }
        tracker.syncWatchers()
        let started = ProcessInfo.processInfo.systemUptime
        let (infos, unread, hidden) = await tracker.snapshot()
        // Every change reads the windows of every app: a slow read says how much that costs here, before it is made smarter.
        let took = ProcessInfo.processInfo.systemUptime - started
        if took > Self.slowSnapshot {
            Log.write(
                .debug, "reading the windows took \(Int(took * 1000)) ms: \(infos.count) windows, \(unread.count) apps not readable",
                source: "refresh")
        }
        let focusedID = await tracker.focusedWindow()
        guard !tracker.isPaused else { return }
        updateMonitors()
        beginRebootRestore()
        reconcile(infos, unread: unread, hidden: hidden)
        finishRestore()
        #if DEBUG
        checkLayoutInvariants()
        #endif
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
        guard !displays.isEmpty else { return }
        let mainIndex = displays.firstIndex(where: \.isMain) ?? 0
        var next: [Monitor] = []
        refreshNative()
        for (displayIndex, display) in displays.enumerated() {
            let existing = monitors.first { $0.id == display.id }
            let taken = next.map(\.workspace)
            let stays = Set(taken).union(monitors.filter { old in displays.contains { $0.id == old.id } }.map(\.workspace))
            let workspace = nativeWorkspace(onDisplay: display.id) ?? existing?.workspace ?? displayMemory.returning(display.id, shown: stays)
                ?? restoredWorkspace(of: display.id, name: display.name, taken: taken)
                ?? defaultWorkspace(display: displayIndex, name: display.name, main: mainIndex, taken: taken)
                ?? unusedWorkspaceName(taken: taken, display: displayIndex, name: display.name, main: mainIndex)
            next.append(Monitor(id: display.id, name: display.name, frame: display.frame, workArea: display.workArea, workspace: workspace, isMain: display.isMain))
            _ = self.workspace(workspace)
        }
        for old in monitors where !next.contains(where: { $0.id == old.id }) {
            displayMemory.lost(old.id, workspace: old.workspace)
        }
        let before = monitors
        monitors = next
        if isNative { announceNativeChanges(from: before) }
        announceDisplays(next)
        setSpecials(specials.filter { shown in next.contains { $0.id == shown.key } })
        if !monitors.contains(where: { $0.id == focusedMonitorID }) {
            focusedMonitorID = monitors.first(where: { $0.frame.origin == .zero })?.id ?? monitors.first?.id ?? 0
        }
    }

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

    private func defaultWorkspace(display index: Int, name: String, main: Int, taken: [String]) -> String? {
        workspaceRules.sorted { $0.key < $1.key }.first { entry in
            entry.value.isDefault && !taken.contains(entry.key)
                && entry.value.monitor.map { MonitorSelector.matches($0, index: index, name: name, mainIndex: main) } == true
        }?.key
    }

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

    /// A tiled window that is not where wm put it (macOS shrank it after a display change or a wake, or the app restored its own
    /// size) gets its frame again: the applier and the watcher would otherwise skip it, as they think it is there.
    private func resendIfDrifted(_ info: WindowInfo, _ managed: ManagedWindow, parked: Bool) {
        guard !managed.floating, !managed.isOutOfLayout, !parked, !managed.minimized, !managed.nativeFullscreen,
              managed.workspaceVisible(self), modifierDrag?.window != info.id, !applier.isBusy(info.id),
              // A window that the user drags by its title bar is where the user puts it, until the drop.
              titleBarPress?.id != info.id, dragDrop?.dragged != info.id,
              animator.isSettled(info.id), let sent = applier.sentFrame(info.id),
              drift.shouldResend(info.id, actual: info.frame, sent: sent) else { return }
        Log.write(.debug, "window \(info.id) (\(info.appName)) is at \(info.frame), not \(sent): sending the frame again", source: "layout", prefix: "wmd")
        applier.resend(info.id, pid: info.pid)
    }

    /// Makes the next relayout write the size and the position of every tiled window of the workspace, also when wm thinks that
    /// the window is already there.
    func resendLaidOut(onWorkspace name: String) {
        for (id, managed) in windows where managed.workspace == name && !managed.floating && !managed.isOutOfLayout {
            applier.resend(id, pid: managed.info.pid)
        }
    }

    private func reconcile(_ infos: [WindowInfo], unread: Set<pid_t>, hidden: Set<pid_t>) {
        var seen: Set<WindowID> = []
        for info in infos {
            seen.insert(info.id)
            goneSince[info.id] = nil
            if var managed = windows[info.id] {
                let titleChanged = info.title != managed.info.title
                if titleChanged {
                    events.emit("window_title", ["id": .number(Double(info.id)), "app": .string(info.bundleID), "title": .string(info.title)])
                }
                managed.info = info
                if managed.appHidden { setAppHidden(info.id, false) }
                if isNative { nativeObserve(info.id) }
                if info.isMinimized != managed.minimized { setMinimized(info.id, info.isMinimized) }
                let fullscreenChanged = info.isFullscreen != managed.nativeFullscreen
                if fullscreenChanged { setNativeFullscreen(info.id, info.isFullscreen) }
                windows[info.id]?.info = managed.info
                let parked = info.frame.minX >= hiddenCorner().x - 1 && info.frame.minY >= hiddenCorner().y - 1
                if managed.floating, !fullscreenChanged, !managed.isOutOfLayout, !parked, managed.workspaceVisible(self),
                   workspace(managed.workspace).fullscreen != info.id {
                    if let until = openingHold[info.id], ProcessInfo.processInfo.systemUptime < until {
                        if let chosen = managed.floatFrame, !sameFrame(info.frame, chosen) { applier.forget(info.id) }
                    } else {
                        openingHold[info.id] = nil
                        windows[info.id]?.floatFrame = info.frame
                    }
                }
                resendIfDrifted(info, managed, parked: parked)
                if titleChanged { reevaluateDynamicRules(info.id) }
                continue
            }
            detect(info)
        }
        skippedWindows.formIntersection(seen)
        let missing = windows.keys.filter { !seen.contains($0) }
        let system = missing.isEmpty ? [] : Self.systemWindowIDs()
        for id in missing { reconcileMissing(id, unread: unread, hidden: hidden, inSystemList: system.contains(id)) }
    }

    /// A debug build says when a window's record and the layouts disagree, which shows as a window on the wrong workspace or a
    /// hole in a layout. It only logs: the user's windows stay where they are.
    private func checkLayoutInvariants() {
        let records = windows.mapValues {
            LayoutInvariants.Window(workspace: $0.workspace, tiled: !$0.floating && !$0.isOutOfLayout)
        }
        let spaces = workspaces.mapValues {
            LayoutInvariants.Workspace(engine: $0.engine.windows, fullscreen: $0.fullscreen, maximized: $0.maximized)
        }
        for problem in LayoutInvariants.problems(windows: records, workspaces: spaces) {
            Log.write(.warn, "layout out of step: \(problem)", source: "invariants")
        }
    }

    private func reconcileMissing(_ id: WindowID, unread: Set<pid_t>, hidden: Set<pid_t>, inSystemList: Bool) {
        let place = WindowSpace.place(of: id)
        let now = ProcessInfo.processInfo.systemUptime
        let started = place == .gone && goneSince[id] == nil
        goneSince[id] = place == .gone ? goneSince[id] ?? now : nil
        let appHidden = windows[id].map { hidden.contains($0.info.pid) } ?? false
        let forgotten = shouldForgetMissingWindow(
            appUnreadable: windows[id].map { unread.contains($0.info.pid) } ?? false,
            appHidden: appHidden, inSystemList: inSystemList, place: place, goneFor: goneSince[id].map { now - $0 } ?? 0)
        if forgotten {
            Log.write(.debug, "window closed: id=\(id) place=\(place) inSystemList=\(inSystemList)", source: "window")
            forget(id)
            return
        }
        if appHidden { setAppHidden(id, true) }
        if started {
            // No event may follow a real close, so look again when the grace is over.
            DispatchQueue.main.asyncAfter(deadline: .now() + spaceTransitionGrace + 0.05) { [weak self] in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            }
        }
    }

    private static func systemWindowIDs() -> Set<WindowID> {
        let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(list.compactMap { ($0[kCGWindowNumber as String] as? Int).map { WindowID($0) } })
    }

    private func detect(_ info: WindowInfo) {
        guard info.kind != .ignored else {
            if didFirstScan, skippedWindows.insert(info.id).inserted {
                let app = info.bundleID.isEmpty ? "(no bundle id)" : info.bundleID
                Log.write(
                    .debug,
                    "window skipped: id=\(info.id) app=\(app) name=\(info.appName) title=\(Log.title(info.title)) role=\(info.role) subrole=\(info.subrole.isEmpty ? "(none)" : info.subrole) identifier=\(info.identifier.isEmpty ? "(none)" : info.identifier) fullscreen=\(info.isFullscreen)",
                    source: "window")
            }
            return
        }
        if let saved = restoreMatch(for: info) {
            adoptRestored(info, as: saved)
            return
        }
        if let saved = activeRestore?.windows.first(where: { $0.id == info.id && $0.bundleID == info.bundleID }) {
            adopt(info, as: saved)
            return
        }
        var rule = matchingRule(info)
        if let spawn = takeSpawnRule(for: info) { rule = rule.map { $0.merging(spawn) } ?? spawn }
        // An app that quit and came back (an update, a crash) restores its windows as new ones: each takes the place of a
        // window that the app had before, not the workspace that shows now.
        let reopened = didFirstScan
            ? recentlyClosed.take(bundleID: info.bundleID, pid: info.pid, title: info.title, now: ProcessInfo.processInfo.systemUptime) : nil
        let remembered = didFirstScan ? memory.match(app: info.bundleID, title: info.title) : nil
        let host = didFirstScan && remembered == nil && rule?.workspace == nil && rule?.monitor == nil ? swallowHost(for: info) : nil
        let last = didFirstScan && remembered == nil && settings.floating.rememberPosition && rule?.float == true && rule?.size == nil
            ? floatMemory.last(app: info.bundleID, title: info.title) : nil
        let home = monitor(containing: CGPoint(x: info.frame.midX, y: info.frame.midY)) ?? focusedMonitor
        let ruleMonitor = rule?.monitor.flatMap(monitor(matching:))
        let lastMonitor = last?.monitor.flatMap(monitor(matching:))
        let fromHost: String? = host.flatMap { windows[$0]?.workspace }
        let fromRules: String? = rule?.workspace ?? ruleMonitor.map(activeWorkspace(of:)) ?? lastMonitor.map(activeWorkspace(of:))
        let fromPlace: String? = nativeWorkspace(ofWindow: info.id) ?? home.map(activeWorkspace(of:))
        let workspaceName: String = fromHost ?? reopened?.workspace ?? remembered?.workspace ?? fromRules ?? fromPlace ?? "1"
        let rememberedMonitor = remembered?.monitor.flatMap(monitor(matching:))
        let monitor = monitor(showing: workspaceName) ?? rememberedMonitor ?? focusedMonitor
        let opening = workspace(workspaceName)
        let layout = rule?.layout.flatMap { opening.engine.windows.isEmpty ? $0 : nil } ?? opening.kind
        let floatsByDefault = layout == .floating
        var floating = reopened?.floating ?? remembered?.floating ?? host.flatMap { windows[$0]?.floating } ?? (info.kind == .floating || (rule?.float ?? floatsByDefault))
        var floatFrame: CGRect?
        if let reopened, floating, let frame = reopened.floatFrame {
            floatFrame = frame
        } else if let remembered {
            if floating, let frame = remembered.frame, let area = monitor?.workArea { floatFrame = WindowMemory.absolute(frame, in: area) }
        } else if let host, floating, let frame = windows[host]?.floatFrame {
            floatFrame = frame
        } else if let last, let area = monitor?.workArea {
            floatFrame = WindowMemory.absolute(last.frame, in: area)
        } else if let area = monitor?.workArea, rule?.size != nil || rule?.center == true {
            floating = rule?.float != false
            floatFrame = Self.ruleFloatFrame(size: rule?.size, center: rule?.center == true, from: info.frame, in: area)
        } else if floating, floatsByDefault, didFirstScan {
            let others = windows.filter { $0.value.workspace == workspaceName && $0.value.floating && !$0.value.isOutOfLayout }.keys.sorted()
            var context = layoutContext(forWorkspace: workspaceName)
            context.gaps = settings(forWorkspace: workspaceName).gaps.effective(tiledCount: others.count + 1)
            floatFrame = tilingFrame(
                for: info.id, among: others, after: opening.history.first(where: others.contains),
                settings: settings(forWorkspace: workspaceName), context: context)
        }
        var placed = floatFrame ?? (floating ? info.frame : nil)
        if didFirstScan, floating, let frame = placed, let area = monitor?.workArea, let fitted = fittedFrame(frame, in: area) {
            placed = fitted
        }
        windows[info.id] = ManagedWindow(
            info: info, workspace: workspaceName, floating: floating, minimized: info.isMinimized, nativeFullscreen: info.isFullscreen,
            floatFrame: info.isFullscreen ? nil : placed)
        if isNative { placedSpace[info.id] = NativeSpaces.space(of: info.id) }
        if didFirstScan, floating, !info.isMinimized, !info.isFullscreen, let placed, !sameFrame(placed, info.frame) { holdOpeningPlace(of: info.id) }
        let dynamic = dynamicRuleIndices(for: info)
        if !dynamic.isEmpty {
            _ = dynamicTracker.update(window: info.id, matching: dynamic, now: ProcessInfo.processInfo.systemUptime)
            dynamicSaved[info.id] = (floating: info.kind == .floating || floatsByDefault, floatFrame: nil, border: nil, dim: nil)
        }
        windows[info.id]?.borderColors = rule?.border
        windows[info.id]?.dim = rule?.dim
        pendingOnEmpty.remove(workspaceName)
        if didFirstScan {
            let app = info.bundleID.isEmpty ? "(no bundle id)" : info.bundleID
            Log.write(
                .debug,
                "window opened: id=\(info.id) app=\(app) name=\(info.appName) title=\(Log.title(info.title)) workspace=\(workspaceName) floating=\(floating) rule=\(Self.describe(rule))\(remembered == nil ? "" : " remembered=yes")\(reopened == nil ? "" : " reopened=yes")",
                source: "window")
        }
        let target = workspace(workspaceName)
        if let layout = rule?.layout, target.engine.windows.isEmpty { target.kind = layout; target.engine = makeEngine(layout, settings: settings(forWorkspace: workspaceName)) }
        if let host {
            swallow(host, by: info.id, in: target)
        } else if !floating, !info.isMinimized, !info.isFullscreen {
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
        if info.isFullscreen { setNativeFullscreen(info.id, true) }
        var commands = rule?.commands ?? []
        if remembered?.strip == .vertical, !floating, target.kind == .scrolling { commands.append("window send strip vertical") }
        withoutLayoutHistory {
            for command in commands { runRuleCommand?(command.split(separator: " ").map(String.init), info.id) }
        }
        if let remembered {
            if remembered.sticky == true, floating {
                windows[info.id]?.sticky = true
                windows[info.id]?.stickyMonitor = monitor?.id
            }
            for name in remembered.marks { setMark(name, on: info.id) }
            focus(info.id)
        }
    }

    private func holdOpeningPlace(of id: WindowID) {
        openingHold[id] = ProcessInfo.processInfo.systemUptime + Self.openingHoldSeconds
        for delay in [0.25, 0.7, 1.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.openingHold[id] != nil else { return }
                    self.scheduleRefresh()
                }
            }
        }
    }

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

    func forgetWindow(_ id: WindowID, withTitle: Bool) -> Bool {
        guard let info = windows[id]?.info else { return false }
        let removed = memory.forget(app: info.bundleID, title: withTitle ? info.title : nil)
        if removed { saveMemory() }
        return removed
    }

    func forgetMemory(appNamed name: String, title: String?, allTitles: Bool) -> [MemorizedWindow] {
        let removed = memory.forget(appNamed: name, title: title, allTitles: allTitles)
        if !removed.isEmpty { saveMemory() }
        return removed
    }

    func clearMemory() -> Int {
        let count = memory.clear()
        if count > 0 { saveMemory() }
        return count
    }

    private func saveMemory() {
        do { try MemoryStore.write(memory) } catch { Log.write(.error, "cannot save \(MemoryStore.url.path): \(error)", source: "memory", prefix: "wmd") }
    }

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

    private var activeRestore: SavedState? {
        pendingRestore.flatMap { $0.mode == settings.workspaceMode.rawValue ? $0 : nil }
    }

    private func restoredWorkspace(of display: UInt32, name: String, taken: [String]) -> String? {
        guard let saved = activeRestore else { return nil }
        if !StateStore.isSameBoot(saved.bootTime) {
            let named = (saved.monitorNames ?? [:]).filter { $0.value == name }
            if named.count == 1, let key = named.keys.first, let workspace = saved.monitors[key], !taken.contains(workspace) { return workspace }
        }
        guard let workspace = saved.monitors[String(display)], !taken.contains(workspace) else { return nil }
        return workspace
    }

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
            if let kind = workspaceLayouts[name], saved.configLayouts[name] != kind, kind != space.kind { rebuild(space, as: kind) }
        }
        waitFor(saved.windows, session: nil, patience: Self.rebootPatience)
    }

    private static let rebootPatience: TimeInterval = 120
    private static let sessionPatience: TimeInterval = 60

    /// The windows of a session that are not open yet. Their layouts must hold a placeholder for each of them.
    func beginSessionRestore(_ name: String, waiting: [SavedWindow]) {
        waitFor(waiting, session: name, patience: Self.sessionPatience)
        if waiting.isEmpty { finishRestoring() }
    }

    private func waitFor(_ saved: [SavedWindow], session: String?, patience: TimeInterval) {
        restoreSerial += 1
        let serial = restoreSerial
        restoring = PendingWindows(
            waiting: Dictionary(uniqueKeysWithValues: saved.enumerated().map { ($0.offset, $0.element) }), session: session, serial: serial)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(patience * 1_000_000_000))
            if restoring?.serial == serial { finishRestoring() }
        }
    }

    private func restoreMatch(for info: WindowInfo) -> SavedWindow? {
        guard let waiting = restoring?.waiting else { return nil }
        let candidates = waiting.map {
            RestoreCandidate(key: $0.key, bundleID: $0.value.bundleID, title: $0.value.title ?? "", order: $0.value.order ?? $0.key)
        }
        guard let best = bestRestoreMatch(bundleID: info.bundleID, title: info.title, among: candidates) else { return nil }
        let saved = waiting[best.key]
        restoring?.waiting[best.key] = nil
        return saved
    }

    private func adoptRestored(_ info: WindowInfo, as saved: SavedWindow) {
        let placeholder = Placeholder.id(for: saved.id)
        windows[info.id] = ManagedWindow(
            info: info, workspace: saved.workspace, floating: saved.floating, minimized: info.isMinimized,
            nativeFullscreen: info.isFullscreen,
            floatFrame: saved.floatFrame ?? (saved.floating && !info.isFullscreen ? info.frame : nil), sticky: saved.floating && saved.sticky == true, stickyMonitor: saved.stickyMonitor)
        for name in saved.marks ?? [] { marks[name] = info.id }
        let space = workspace(saved.workspace)
        space.engine.relabel([placeholder: info.id])
        space.history = space.history.map { $0 == placeholder ? info.id : $0 }
        if space.maximized.remove(placeholder) != nil { space.maximized.insert(info.id) }
        if space.fullscreen == placeholder { space.fullscreen = info.id }
        if saved.floating || info.isMinimized || info.isFullscreen {
            space.engine.remove(info.id)
        } else if !space.engine.windows.contains(info.id) {
            space.engine.insert(info.id, after: space.history.first { $0 != info.id && windows[$0] != nil })
        }
        animator.seed(info.id, at: info.frame)
        if restoring?.waiting.isEmpty == true { finishRestoring() }
    }

    private func finishRestoring() {
        guard let finished = restoring else { return }
        restoring = nil
        if let session = finished.session {
            let missing = Set(finished.waiting.values.map(\.bundleID)).sorted()
            events.emit("session_done", ["name": .string(session), "missing": .string(missing.joined(separator: " "))])
        }
        for space in workspaces.values {
            for id in space.engine.windows where Placeholder.isPlaceholder(id) { space.engine.remove(id) }
            space.history.removeAll { Placeholder.isPlaceholder($0) }
            space.maximized = space.maximized.filter { !Placeholder.isPlaceholder($0) }
            if let full = space.fullscreen, Placeholder.isPlaceholder(full) { space.fullscreen = nil }
        }
        relayout()
        saveState()
    }

    private func adopt(_ info: WindowInfo, as saved: SavedWindow) {
        windows[info.id] = ManagedWindow(
            info: info, workspace: saved.workspace, floating: saved.floating, minimized: info.isMinimized,
            nativeFullscreen: info.isFullscreen,
            floatFrame: saved.floatFrame ?? (saved.floating && !info.isFullscreen ? info.frame : nil), sticky: saved.floating && saved.sticky == true, stickyMonitor: saved.stickyMonitor)
        for name in saved.marks ?? [] { marks[name] = info.id }
        windows[info.id]?.swallowedBy = saved.swallowedBy
        _ = workspace(saved.workspace)
        adopted.insert(info.id)
        animator.seed(info.id, at: info.frame)
    }

    private func finishRestore() {
        guard let saved = pendingRestore else { return }
        guard saved.mode == settings.workspaceMode.rawValue else { return }
        pendingRestore = nil
        // A swallowed terminal stays parked behind its program, when both came back; else it is a window like any other.
        for id in adopted {
            guard let child = windows[id]?.swallowedBy else { continue }
            if windows[child] != nil, adopted.contains(child) {
                windows[child]?.swallows = id
                swallowedAt[child] = ProcessInfo.processInfo.systemUptime
            } else {
                windows[id]?.swallowedBy = nil
            }
        }
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
            if let kind = workspaceLayouts[name], saved.configLayouts[name] != kind, kind != space.kind { rebuild(space, as: kind) }
        }
        adopted = []
    }

    func snapshot() -> SavedState {
        var order: [WindowID: Int] = [:]
        for name in workspaces.keys.sorted() {
            for id in workspaces[name]!.engine.windows where order[id] == nil { order[id] = order.count }
        }
        for id in windows.keys.sorted() where order[id] == nil { order[id] = order.count }
        return SavedState(
            mode: settings.workspaceMode.rawValue,
            windows: windows.sorted { $0.key < $1.key }.map {
                SavedWindow(
                    id: $0.key, bundleID: $0.value.info.bundleID, workspace: $0.value.workspace, floating: $0.value.floating,
                    floatFrame: $0.value.floatFrame, marks: marks(of: $0.key), title: $0.value.info.title, order: order[$0.key],
                    sticky: $0.value.sticky ? true : nil, stickyMonitor: $0.value.sticky ? $0.value.stickyMonitor : nil,
                    swallowedBy: $0.value.swallowedBy)
            },
            workspaces: workspaces.mapValues {
                SavedWorkspace(layout: $0.savedLayout, history: $0.history, maximized: $0.maximized.sorted(), fullscreen: $0.fullscreen)
            },
            monitors: Dictionary(uniqueKeysWithValues: monitors.map { (String($0.id), $0.workspace) }),
            configLayouts: workspaceLayouts,
            bootTime: StateStore.bootTime(),
            monitorNames: Dictionary(uniqueKeysWithValues: monitors.map { (String($0.id), $0.name) }))
    }

    func saveState() {
        saveTimer?.invalidate()
        saveTimer = nil
        guard pendingRestore == nil, restoring == nil, !windows.isEmpty else { return }
        do {
            let data = try StateStore.encode(snapshot())
            guard data != lastSaved else { return }
            try StateStore.write(data)
            lastSaved = data
        } catch {
            Log.write(.error, "cannot save state: \(error)", source: "state", prefix: "wmd")
        }
    }

    private func scheduleSave() {
        guard saveTimer == nil else { return }
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveState() }
        }
    }

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

    private func followSticky() {
        for id in windows.filter({ $0.value.sticky && !$0.value.isOutOfLayout }).keys {
            guard let managed = windows[id],
                  let monitor = monitors.first(where: { $0.id == managed.stickyMonitor }) ?? focusedMonitor else { continue }
            windows[id]?.stickyMonitor = monitor.id
            let active = activeWorkspace(of: monitor)
            guard managed.workspace != active else { continue }
            let left = workspace(managed.workspace)
            left.history.removeAll { $0 == id }
            if left.fullscreen == id { left.fullscreen = nil }
            windows[id]?.workspace = active
        }
    }

    private func zenWindow(in workspace: Workspace, focused: WindowID?) -> WindowID? {
        func usable(_ id: WindowID) -> Bool { windows[id].map { $0.workspace == workspace.name && !$0.isOutOfLayout } ?? false }
        if let focused, usable(focused) { return focused }
        return workspace.history.first(where: usable) ?? workspace.engine.windows.first(where: usable)
            ?? windows.keys.sorted().first(where: usable)
    }

    func setZen(_ on: Bool?) -> Bool {
        guard let space = focusedWorkspace else { return false }
        space.zen = on ?? !space.zen
        relayout()
        return space.zen
    }

    func monitor(matching spec: String) -> Monitor? {
        let mainIndex = monitors.firstIndex(where: \.isMain) ?? 0
        return monitors.enumerated().first { MonitorSelector.matches(spec, index: $0.offset, name: $0.element.name, mainIndex: mainIndex) }?.element
    }

    private func maximizeOnOpen(_ id: WindowID, in workspace: Workspace) {
        if workspace.engine is ScrollingEngine,
           workspace.engine.perform(.maximize, focused: id, in: layoutContext(forWorkspace: workspace.name)) { return }
        workspace.maximized.insert(id)
    }

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

    /// Whether the workspace has a window of an app that is not hidden. A workspace with only hidden apps counts as empty.
    private func hasShownApp(_ name: String) -> Bool {
        windows.values.contains { $0.workspace == name && !$0.appHidden }
    }

    private func runOnEmptyIfEmpty(_ name: String) {
        guard let request = workspaceRules[name]?.onEmpty, !pendingOnEmpty.contains(name),
              !hasShownApp(name) else { return }
        pendingOnEmpty.insert(name)
        let wait = (request.options?.timeout ?? ExecOptions.defaultTimeout) + 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            MainActor.assumeIsolated { _ = self?.pendingOnEmpty.remove(name) }
        }
        Log.write(.debug, "workspace \(name) is shown with no window: running on_empty", source: "workspace")
        runOnEmpty?(request)
    }

    private var persistentWorkspaces: Set<String> { Set(workspaceRules.filter(\.value.persistent).keys) }

    private func updateBadgeWatching() {
        let wanted = settings.urgent.enabled ? settings.urgent.interval : 0
        guard wanted != badgeInterval else { return }
        badgeTimer?.invalidate()
        badgeTimer = nil
        badgeInterval = wanted
        guard wanted > 0 else {
            urgent = UrgentTracker()
            return
        }
        badgeTimer = Timer.scheduledTimer(withTimeInterval: wanted, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async {
                let badges = DockBadges.read()
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.badgesRead(badges) } }
            }
        }
    }

    private func badgesRead(_ badges: [String: String]) {
        guard badgeInterval > 0, tracker?.isPaused != true else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        for alert in urgent.update(badges: badges, frontmost: frontmost) {
            guard let id = windowOf(app: alert.app) else { continue }
            events.emit("window_urgent", [
                "id": .number(Double(id)), "app": .string(windows[id]?.info.bundleID ?? alert.app), "badge": .string(alert.badge),
            ])
        }
    }

    private func windowOf(app: String) -> WindowID? {
        let isApp = { (id: WindowID) -> Bool in
            guard let window = self.windows[id], !window.minimized, !window.appHidden, window.swallowedBy == nil else { return false }
            return window.info.bundleID.caseInsensitiveCompare(app) == .orderedSame || window.info.appName.caseInsensitiveCompare(app) == .orderedSame
        }
        return recent.first(where: isApp) ?? windows.keys.sorted().first(where: isApp)
    }

    func urgentWindow() -> WindowID? {
        urgent.urgentApps.lazy.compactMap { self.windowOf(app: $0) }.first
    }

    func previousWindowAnywhere() -> WindowID? {
        recent.first { $0 != focused && windows[$0].map { !$0.isOutOfLayout } == true }
    }

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

    private func updateTitleWatching() {
        let dynamic = rules.filter(\.dynamic)
        tracker?.watchesTitles = { bundleID, name in
            dynamic.contains { rule in
                rule.app.map { $0.caseInsensitiveCompare(bundleID) == .orderedSame || $0.caseInsensitiveCompare(name) == .orderedSame } ?? true
            }
        }
        tracker?.updateTitleWatching()
    }

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

    private func applyDynamic(_ rule: WindowRule, to id: WindowID) {
        guard let managed = windows[id] else { return }
        if dynamicSaved[id] == nil { dynamicSaved[id] = (floating: managed.floating, floatFrame: managed.floatFrame, border: managed.borderColors, dim: managed.dim) }
        windows[id]?.borderColors = rule.border ?? dynamicSaved[id]?.border
        windows[id]?.dim = rule.dim ?? dynamicSaved[id]?.dim
        Log.write(.debug, "dynamic rule applied: id=\(id) title=\(Log.title(managed.info.title)) rule=\(Self.describe(rule))", source: "window")
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

    private func revertDynamic(_ id: WindowID) {
        guard let saved = dynamicSaved.removeValue(forKey: id), let managed = windows[id] else { return }
        Log.write(.debug, "dynamic rule undone: id=\(id) title=\(Log.title(managed.info.title))", source: "window")
        if managed.floating != saved.floating { setFloating(id, saved.floating) }
        if saved.floating, let frame = saved.floatFrame { setFloatFrame(id, frame) }
        windows[id]?.borderColors = saved.border
        windows[id]?.dim = saved.dim
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
        // Kept for a while: if the app quits and comes back, its new window goes where this one was.
        if managed.swallowedBy == nil {
            recentlyClosed.add(
                RecentlyClosed.Place(
                    bundleID: managed.info.bundleID, pid: managed.info.pid, title: managed.info.title, workspace: managed.workspace,
                    floating: managed.floating, floatFrame: managed.floatFrame),
                now: ProcessInfo.processInfo.systemUptime)
        }
        let wasFocused = focused == id
        let returning = giveBackTerminal(of: id, managed)
        swallowedAt[id] = nil
        goneSince[id] = nil
        placedSpace[id] = nil
        movingUntil[id] = nil
        lastVisible.remove(id)
        lastParked.remove(id)
        dynamicTracker.forget(id)
        dynamicSaved[id] = nil
        leaveGroup(id, frame: managed.floatFrame)
        openingHold[id] = nil
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
        drift.forget(id)
        events.emit("window_close", ["id": .number(Double(id))])
        if let returning, wasFocused { focus(returning) }
    }

    private func setMinimized(_ id: WindowID, _ minimized: Bool) {
        guard var managed = windows[id] else { return }
        managed.minimized = minimized
        windows[id] = managed
        let workspace = workspace(managed.workspace)
        if minimized {
            // Out of the layout like a hidden window: no fullscreen that hides the others, no focus that lands on it.
            workspace.maximized.remove(id)
            if workspace.fullscreen == id { workspace.fullscreen = nil }
            workspace.history.removeAll { $0 == id }
            workspace.engine.remove(id)
            if focused == id { focused = workspace.history.first }
        } else if !managed.floating, !managed.isOutOfLayout {
            workspace.engine.insert(id, after: workspace.history.first)
        }
    }

    /// The windows of a hidden app keep their workspace. They leave the layout and the focus history until the app shows again.
    private func setAppHidden(_ id: WindowID, _ hidden: Bool) {
        guard var managed = windows[id], managed.appHidden != hidden else { return }
        managed.appHidden = hidden
        windows[id] = managed
        let workspace = workspace(managed.workspace)
        let what = hidden ? "hidden with its app" : "shown again"
        Log.write(.debug, "window \(what): id=\(id) app=\(managed.info.bundleID) workspace=\(workspace.name)", source: "window")
        if hidden {
            openingHold[id] = nil
            workspace.maximized.remove(id)
            if workspace.fullscreen == id { workspace.fullscreen = nil }
            workspace.history.removeAll { $0 == id }
            workspace.engine.remove(id)
            if focused == id { focused = workspace.history.first }
            hideSpecialIfEmpty(workspace.name)
        } else {
            // The app may have moved it while wm did not look.
            applier.resend(id, pid: managed.info.pid)
            if !managed.floating, !managed.isOutOfLayout {
                workspace.engine.insert(id, after: workspace.history.first { $0 != id })
            }
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
        } else if !managed.floating, !managed.isOutOfLayout {
            workspace.engine.insert(id, after: workspace.history.first { $0 != id })
        }
    }

    func setMark(_ name: String, on id: WindowID) { marks[name] = id }

    func removeMarks(named name: String?, of id: WindowID) {
        if let name { marks[name] = nil } else { marks = marks.filter { $0.value != id } }
    }

    func marks(of id: WindowID) -> [String] { marks.filter { $0.value == id }.keys.sorted() }

    var focusedMonitor: Monitor? { monitors.first { $0.id == focusedMonitorID } }

    var focusedWorkspace: Workspace? {
        focusedMonitor.map { workspace(activeWorkspace(of: $0)) }
    }

    private func didFocus(_ id: WindowID) {
        if windows[id]?.swallowedBy != nil {
            if let at = swallowedAt[id], ProcessInfo.processInfo.systemUptime - at < 1.5 { return }
            unswallow(id)
        }
        guard let managed = windows[id] else { return }
        // A tab of a group that got the focus another way (the switcher, a command) shows, in the frame of the group.
        if let front = floatGroups.shownMember(of: id), front != id {
            if let frame = windows[front]?.floatFrame { windows[id]?.floatFrame = frame }
            floatGroups.show(id)
        }
        focused = id
        urgent.focused(managed.info.bundleID, managed.info.appName)
        let workspace = workspace(managed.workspace)
        workspace.history.removeAll { $0 == id }
        workspace.history.insert(id, at: 0)
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
        if SpecialWorkspace.isSpecial(managed.workspace) {
            let monitorID = monitor(showing: managed.workspace)?.id ?? focusedMonitorID
            if specials[monitorID] != managed.workspace {
                setSpecials(SpecialWorkspace.toggle(managed.workspace, on: monitorID, shown: specials))
            }
            focusedMonitorID = monitorID
        } else if let monitor = monitors.first(where: { $0.workspace == managed.workspace }) {
            focusedMonitorID = monitor.id
            let hiding = SpecialWorkspace.monitorsHiding(
                onFocusOf: monitor.id, shown: specials, otherMonitors: settings.special.hideOnOtherMonitor
            ) { name in hasShownApp(name) }
            if !hiding.isEmpty { setSpecials(specials.filter { !hiding.contains($0.key) }) }
        } else if !isNative, let monitor = focusedMonitor {
            showWorkspace(managed.workspace, on: monitor.id, focusWindow: false)
        }
        publishStatus()
        events.emit("window_focus", ["id": .number(Double(id)), "app": .string(managed.info.bundleID), "title": .string(managed.info.title)])
    }

    func focus(_ id: WindowID, warpMouse: Bool = true) {
        guard let managed = windows[id] else { return }
        if isNative, !SpecialWorkspace.isSpecial(managed.workspace), let desktop = nativeDesktop(of: managed.workspace),
           !nativeIsCurrent(desktop) {
            showNativeWorkspace(managed.workspace, then: { [weak self] in self?.focus(id, warpMouse: warpMouse) })
            return
        }
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

    func isVisible(_ workspace: String) -> Bool { monitors.contains { activeWorkspace(of: $0) == workspace } }

    func activeWorkspace(of monitor: Monitor) -> String { specials[monitor.id] ?? monitor.workspace }

    func monitor(showing workspace: String) -> Monitor? {
        monitors.first { $0.workspace == workspace || specials[$0.id] == workspace }
    }

    func toggleSpecial(_ name: String) {
        setSpecials(SpecialWorkspace.toggle(name, on: focusedMonitorID, shown: specials))
        if let monitor = focusedMonitor, let id = windowToFocus(in: workspace(activeWorkspace(of: monitor))) {
            focus(id)
        } else {
            focused = nil
            relayout()
        }
    }

    private func setSpecials(_ next: [UInt32: String]) {
        let old = specials
        specials = next
        for (monitor, name) in old where next[monitor] != name {
            events.emit("special_changed", ["workspace": .string(name), "monitor": .number(Double(monitor)), "visible": .bool(false)])
        }
        for (monitor, name) in next where old[monitor] != name {
            _ = workspace(name)
            pendingSlide = (.special, name, true)
            runOnEmptyIfEmpty(name)
            events.emit("special_changed", ["workspace": .string(name), "monitor": .number(Double(monitor)), "visible": .bool(true)])
        }
        updateBackdrop()
    }

    func updateBackdrop() {
        let shown = monitors.filter { specials[$0.id] != nil }.map(\.frame)
        backdrop.show(on: shown, settings.special.backdrop)
    }

    private func hideSpecialIfEmpty(_ name: String) {
        guard let monitor = specials.first(where: { $0.value == name })?.key,
              !hasShownApp(name) else { return }
        setSpecials(specials.filter { $0.key != monitor })
    }

    private func relocateFloats(of name: String, from old: CGRect, to new: CGRect) {
        guard old != new else { return }
        for (id, managed) in windows where managed.workspace == name && managed.floating {
            guard let frame = managed.floatFrame ?? currentFrame(of: id) else { continue }
            windows[id]?.floatFrame = MonitorGeometry.translated(frame, from: old, to: new)
        }
        layoutHistory.moveFloating(of: name) { MonitorGeometry.translated($0, from: old, to: new) }
        workspace(name).shownArea = new
    }

    func moveWorkspace(to target: Monitor) -> String? {
        if isNative { return "with workspaces = \"native\" a workspace is a desktop: it stays on its display" }
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
        if isNative, !SpecialWorkspace.isSpecial(name) {
            showNativeWorkspace(name, focusWindow: focusWindow)
            return
        }
        _ = workspace(name)
        let monitorID = boundMonitor(of: name)?.id ?? requested
        guard let index = monitors.firstIndex(where: { $0.id == monitorID }) else { return }
        setSpecials(specials.filter { $0.key != monitorID })
        if let other = monitors.firstIndex(where: { $0.workspace == name }), other != index {
            relocateFloats(of: name, from: monitors[other].workArea, to: monitors[index].workArea)
            relocateFloats(of: monitors[index].workspace, from: monitors[index].workArea, to: monitors[other].workArea)
            monitors[other].workspace = monitors[index].workspace
        } else if let last = workspace(name).shownArea {
            // A hidden workspace keeps the places of the monitor that showed it last; on another monitor they move along.
            relocateFloats(of: name, from: last, to: monitors[index].workArea)
        }
        let old = monitors[index].workspace
        monitors[index].workspace = name
        focusedMonitorID = monitorID
        if old != name {
            previousWorkspace = old
            pendingSlide = (.workspace, name, WorkspaceSlide.isForward(from: old, to: name))
            runOnEmptyIfEmpty(name)
            events.emit("workspace_changed", ["workspace": .string(name), "previous": .string(old), "monitor": .number(Double(monitorID))])
        }
        if focusWindow {
            let target = workspace(name)
            if let id = windowToFocus(in: target) {
                focus(id, warpMouse: false)
                return
            }
            focused = nil
        }
        relayout()
    }

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

    func setFloatFrame(_ id: WindowID, _ frame: CGRect) {
        guard frame.isFinite else { return }
        openingHold[id] = nil
        windows[id]?.floatFrame = frame
    }

    func setFloatRestore(_ id: WindowID, _ frame: CGRect?) { windows[id]?.floatRestore = frame }

    func setFloating(_ id: WindowID, _ floating: Bool) {
        guard var managed = windows[id], managed.floating != floating else { return }
        openingHold[id] = nil
        let workspace = workspace(managed.workspace)
        managed.floating = floating
        if floating {
            workspace.maximized.remove(id)
            workspace.pseudo[id] = nil
            workspace.engine.remove(id)
            let frame = currentFrame(of: id) ?? managed.info.frame
            if let area = (monitor(showing: managed.workspace) ?? focusedMonitor)?.workArea {
                managed.floatFrame = floatFrame(current: frame, in: area)
            } else {
                managed.floatFrame = frame
            }
        } else {
            // Only a floating window can be sticky, or a tab of a float group.
            leaveGroup(id, frame: managed.floatFrame)
            managed.sticky = false
            managed.stickyMonitor = nil
            if !managed.isOutOfLayout { workspace.engine.insert(id, after: workspace.history.first { $0 != id }) }
        }
        windows[id] = managed
        events.emit("window_floating", ["id": .number(Double(id)), "floating": .bool(floating)])
    }

    func setSticky(_ id: WindowID, _ on: Bool) {
        guard let managed = windows[id] else { return }
        windows[id]?.sticky = on
        windows[id]?.stickyMonitor = on ? (monitor(showing: managed.workspace) ?? focusedMonitor)?.id : nil
    }

    /// The window that gets the focus when the workspace shows: the last one used that can take it, else the first of the
    /// layout. A minimized or hidden window, or the place of a window that a restore still waits for, cannot.
    private func windowToFocus(in workspace: Workspace) -> WindowID? {
        func usable(_ id: WindowID) -> Bool { windows[id].map { !$0.isOutOfLayout } ?? false }
        return workspace.history.first(where: usable) ?? workspace.engine.windows.first(where: usable)
    }

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

    func sendQuietly(_ id: WindowID, to name: String) {
        guard windows[id] != nil else { return }
        moveWindow(id, to: name)
        arrive(id)
        relayout()
    }

    func resolveWorkspaceName(_ name: String) -> String {
        if isNative, RelativeWorkspace.words.contains(name), let resolved = resolveNativeName(name) { return resolved }
        guard RelativeWorkspace.words.contains(name), let current = focusedMonitor?.workspace else { return name }
        let used = Set(windows.values.map(\.workspace)).union(monitors.map(\.workspace)).union(persistentWorkspaces)
        return RelativeWorkspace.resolve(name, from: current, used: used) ?? name
    }

    @discardableResult
    func swapWindows(_ a: WindowID, _ b: WindowID) -> Bool {
        guard a != b, let first = windows[a], let second = windows[b], first.workspace == second.workspace else { return false }
        let workspace = workspace(first.workspace)
        let tiled = workspace.engine.windows
        guard tiled.contains(a), tiled.contains(b) else { return false }
        workspace.engine.relabel([a: b, b: a])
        // A swap from the keyboard, the mouse or jump mode rearranges the layout: maximize and fullscreen end, so it shows.
        endMaximize(in: workspace)
        return true
    }

    private func applySettings(to workspace: Workspace) {
        workspace.engine = makeEngine(restoring: workspace.engine.state, settings: settings(forWorkspace: workspace.name))
        events.emit("layout_changed", ["workspace": .string(workspace.name), "layout": .string(workspace.kind.rawValue)])
    }

    func rebuild(_ workspace: Workspace, as kind: LayoutKind) {
        if kind == workspace.kind, let old = workspace.engine as? ScrollingEngine {
            workspace.engine = ScrollingEngine(settings: settings(forWorkspace: workspace.name), keeping: old)
            events.emit("layout_changed", ["workspace": .string(workspace.name), "layout": .string(kind.rawValue)])
            return
        }
        if kind == workspace.kind, let old = workspace.engine as? MasterEngine {
            workspace.engine = makeEngine(restoring: old.state, settings: settings(forWorkspace: workspace.name))
            events.emit("layout_changed", ["workspace": .string(workspace.name), "layout": .string(kind.rawValue)])
            return
        }
        let order = workspace.engine.windows
        workspace.kind = kind
        // `window pseudo` belongs to tiling: another layout gives the window its whole cell.
        if kind != .tiling { workspace.pseudo = [:] }
        if kind == .master {
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

    private func refreshNative() {
        guard isNative else { return }
        let listings = NativeSpaces.listings()
        nativeListings = listings
        nativeBinding = NativeSpaceBinding(displays: listings.map(\.display), rules: workspaceRules.compactMapValues(\.space))
    }

    private func nativeWorkspace(onDisplay id: UInt32) -> String? {
        guard isNative, let listing = nativeListings.first(where: { $0.display.displayID == id }) else { return nil }
        let space = switcher.destination(on: listing.display.uuid) ?? listing.display.current
        return nativeBinding.workspace(of: space) ?? "space:\(space)"
    }

    private func nativeWorkspace(ofWindow id: WindowID) -> String? {
        guard isNative, let space = NativeSpaces.space(of: id) else { return nil }
        return nativeBinding.workspace(of: space)
    }

    func nativeDesktop(of name: String, create: Bool = false) -> NativeSpaceBinding.Desktop? {
        refreshNative()
        if nativeBinding.desktop(of: name) == nil, create, let needed = desktopNumber(of: name) { ensureDesktops(upTo: needed) }
        return nativeBinding.desktop(of: name)
    }

    private func desktopNumber(of name: String) -> Int? {
        if let space = workspaceRules[name]?.space { return space }
        return Int(name).flatMap { $0 >= 1 ? $0 : nil }
    }

    @discardableResult
    private func ensureDesktops(upTo count: Int) -> Bool {
        guard isNative, NativeSpaces.canCreate else { return false }
        while nativeBinding.count < count {
            guard let last = nativeBinding.displays.last, let made = NativeSpaces.create(on: last.uuid) else { return false }
            let before = nativeBinding.count
            for _ in 0..<50 {
                refreshNative()
                if nativeBinding.count > before { break }
                usleep(20_000)
            }
            guard nativeBinding.count > before else {
                Log.write(.warn, "desktop \(made) was made, and macOS has not listed it", source: "spaces")
                return false
            }
            Log.write(.info, "made desktop \(nativeBinding.count) (Space \(made))", source: "spaces")
        }
        return true
    }

    func nativeProblem(for name: String) -> String? {
        guard isNative, !SpecialWorkspace.isSpecial(name) else { return nil }
        guard NativeSpaces.canList else { return "workspaces = \"native\" needs SkyLight, and this macOS does not give the desktops" }
        guard nativeDesktop(of: name, create: true) != nil else {
            if desktopNumber(of: name) == nil {
                return "workspace \(name) has no desktop: give it one with `wm.workspace(\"\(name)\", { space = N })`"
            }
            return NativeSpaces.canCreate
                ? "workspace \(name) has no desktop, and macOS did not make one: add it in Mission Control"
                : "workspace \(name) has no desktop: add one in Mission Control (macOS before 27 does not let wm make desktops)"
        }
        return nil
    }

    func balancePool(count: Int?) -> (pool: [String], problem: String?) {
        let limit = settings.workspaceLimit
        guard let size = count ?? limit else {
            return ([], "workspaces balance needs the number of workspaces: set `workspaces = <max>` in the config, or pass a count")
        }
        if let count, let limit, count > limit { return ([], "\(count) is above the limit of \(limit) workspaces (`workspaces` in the config)") }
        guard isNative else { return ((1...size).map(String.init), nil) }
        refreshNative()
        ensureDesktops(upTo: size)
        let desktops = nativeBinding.desktops.compactMap { nativeBinding.workspace(of: $0.space) }
        return (Array(desktops.prefix(size)), nil)
    }

    func workspaceProblem(for name: String) -> String? {
        if let problem = WorkspaceLimit.problem(name, limit: settings.workspaceLimit) { return problem }
        return nativeProblem(for: name)
    }

    func nativeFacts() -> NativeFacts? {
        guard isNative else { return nil }
        refreshNative()
        var wanted = Set(workspaceRules.filter { $0.value.space != nil || !SpecialWorkspace.isSpecial($0.key) }.keys)
        wanted.formUnion(windows.values.map(\.workspace))
        wanted = wanted.filter { !SpecialWorkspace.isSpecial($0) && !$0.hasPrefix("space:") }
        return NativeFacts(
            canList: NativeSpaces.canList, canMoveWindows: NativeSpaces.canMoveWindows, canCreate: NativeSpaces.canCreate, rearrangesSpaces: NativeSpaces.rearrangesSpaces,
            separateSpaces: NativeSpaces.displaysHaveSeparateSpaces, desktops: nativeBinding.count,
            missing: nativeBinding.missing(RelativeWorkspace.ordered(wanted)))
    }

    private func nativeIsCurrent(_ desktop: NativeSpaceBinding.Desktop) -> Bool {
        NativeSpaces.listings().first { $0.display.uuid == desktop.display }?.display.current == desktop.space
    }

    private func nativeIsSwitching(_ monitor: Monitor) -> Bool {
        guard let uuid = nativeListings.first(where: { $0.display.displayID == monitor.id })?.display.uuid else { return false }
        return switcher.destination(on: uuid) != nil
    }

    private func showNativeWorkspace(_ name: String, focusWindow: Bool = true, then: (() -> Void)? = nil) {
        _ = workspace(name)
        guard let desktop = nativeDesktop(of: name, create: true), let index = monitors.firstIndex(where: { $0.id == desktop.displayID }) else {
            Log.write(.warn, "workspace \(name) has no desktop", source: "spaces")
            return
        }
        let monitorID = monitors[index].id
        setSpecials(specials.filter { $0.key != monitorID })
        let old = monitors[index].workspace
        monitors[index].workspace = name
        focusedMonitorID = monitorID
        if old != name {
            previousWorkspace = old
            runOnEmptyIfEmpty(name)
            events.emit("workspace_changed", ["workspace": .string(name), "previous": .string(old), "monitor": .number(Double(monitorID))])
        }
        syncNativeWindows()
        let target = workspace(name)
        let arrived: () -> Void = { [weak self] in
            guard let self else { return }
            if let then { return then() }
            if focusWindow, let id = windowToFocus(in: target) {
                focus(id, warpMouse: false)
            } else {
                if focusWindow { focused = nil }
                relayout()
            }
        }
        if !switcher.request(desktop.space, on: desktop.display, landed: { [weak self] in
            MainActor.assumeIsolated {
                arrived()
                self?.scheduleRefresh()
            }
        }) {
            arrived()
        } else {
            publishStatus()
        }
    }

    private func resolveNativeName(_ word: String) -> String? {
        refreshNative()
        guard let monitor = focusedMonitor, let uuid = nativeListings.first(where: { $0.display.displayID == monitor.id })?.display.uuid
        else { return nil }
        let names = nativeBinding.workspaces(on: uuid)
        guard let index = names.firstIndex(of: monitor.workspace) else { return nil }
        switch word {
        case "next": return names[(index + 1) % names.count]
        case "prev": return names[(index + names.count - 1) % names.count]
        default:
            let taken = Set(windows.values.map(\.workspace)).union(monitors.map(\.workspace))
            return names.first { !taken.contains($0) }
        }
    }

    private func nativeObserve(_ id: WindowID) {
        let now = ProcessInfo.processInfo.systemUptime
        if let until = movingUntil[id] {
            if now < until { return }
            movingUntil[id] = nil
        }
        guard let space = NativeSpaces.space(of: id) else { return }
        defer { placedSpace[id] = space }
        guard let known = placedSpace[id], known != space, let managed = windows[id], !managed.sticky,
              !SpecialWorkspace.isSpecial(managed.workspace), let name = nativeBinding.workspace(of: space), name != managed.workspace
        else { return }
        moveWindow(id, to: name)
    }

    private func nativeSpace(for managed: ManagedWindow) -> UInt64? {
        guard SpecialWorkspace.isSpecial(managed.workspace) else { return nativeBinding.desktop(of: managed.workspace)?.space }
        guard let monitor = monitor(showing: managed.workspace),
              let listing = nativeListings.first(where: { $0.display.displayID == monitor.id }) else { return nil }
        return switcher.destination(on: listing.display.uuid) ?? listing.display.current
    }

    private func syncNativeWindows() {
        guard isNative, NativeSpaces.canMoveWindows else { return }
        let now = ProcessInfo.processInfo.systemUptime
        var batches: [UInt64: [WindowID]] = [:]
        for (id, managed) in windows where !managed.isOutOfLayout {
            guard let desired = nativeSpace(for: managed) else { continue }
            if let until = movingUntil[id], now < until { continue }
            if placedSpace[id] == nil { placedSpace[id] = NativeSpaces.space(of: id) }
            guard let current = placedSpace[id], current != desired else { continue }
            batches[desired, default: []].append(id)
        }
        for (space, ids) in batches where NativeSpaces.move(ids, to: space) {
            for id in ids {
                placedSpace[id] = space
                movingUntil[id] = now + 2
            }
        }
    }

    private func parksWhenHidden(_ managed: ManagedWindow) -> Bool {
        !isNative || SpecialWorkspace.isSpecial(managed.workspace) || isVisible(managed.workspace)
    }

    private func parkedForRestore(_ id: WindowID, _ managed: ManagedWindow) -> Bool {
        guard isNative else { return !lastVisible.contains(id) || lastParked.contains(id) }
        return lastParked.contains(id) || (!lastVisible.contains(id) && parksWhenHidden(managed))
    }

    private func gatherWindows() {
        refreshNative()
        var batches: [UInt64: [UInt32]] = [:]
        for (id, managed) in windows where !managed.isOutOfLayout {
            let display = (monitor(showing: managed.workspace) ?? focusedMonitor)?.id
            guard let space = nativeListings.first(where: { $0.display.displayID == display })?.display.current else { continue }
            batches[space, default: []].append(id)
        }
        for (space, ids) in batches { NativeSpaces.move(ids, to: space) }
        placedSpace = [:]
        movingUntil = [:]
    }

    private func announceNativeChanges(from before: [Monitor]) {
        for monitor in monitors {
            guard let old = before.first(where: { $0.id == monitor.id }), old.workspace != monitor.workspace else { continue }
            previousWorkspace = old.workspace
            runOnEmptyIfEmpty(monitor.workspace)
            events.emit(
                "workspace_changed",
                ["workspace": .string(monitor.workspace), "previous": .string(old.workspace), "monitor": .number(Double(monitor.id))])
        }
    }

    func relayout(snapAll: Bool = false) {
        let started = CACurrentMediaTime()
        // Counted only while an animation runs: that is when its time competes with the frames.
        defer { if clock != nil { applier.stats.relayout(seconds: CACurrentMediaTime() - started) } }
        followSticky()
        var targets: [WindowID: CGRect] = [:]
        var visible: Set<WindowID> = []
        syncNativeWindows()
        for monitor in monitors {
            if isNative, nativeIsSwitching(monitor) { continue }
            let workspace = workspace(activeWorkspace(of: monitor))
            if !SpecialWorkspace.isSpecial(workspace.name) { workspace.shownArea = monitor.workArea }
            let context = layoutContext(forWorkspace: workspace.name)
            let focusHere = focused.flatMap { windows[$0]?.workspace == workspace.name ? $0 : nil }
            if workspace.zen, workspace.fullscreen == nil, let shown = zenWindow(in: workspace, focused: focusHere) {
                targets[shown] = zenFrame(in: context.gaps.outerArea(context.viewport), width: settings.zen.width)
                visible.insert(shown)
                continue
            }
            for (id, frame) in workspace.engine.frames(in: context, focused: focusHere) {
                let pseudo = workspace.kind == .tiling ? workspace.pseudo[id] : nil
                let cell = pseudo.map { PixelFrame.centered($0, in: frame) } ?? frame
                targets[id] = workspace.fullscreen == id ? monitor.workArea : cell
                visible.insert(id)
            }
            if let full = workspace.fullscreen, windows[full] != nil { targets[full] = monitor.workArea }
            if workspace.fullscreen == nil {
                for maximized in workspace.maximized where windows[maximized] != nil {
                    targets[maximized] = context.gaps.outerArea(context.viewport)
                }
            }
            let waiting = floatGroups.waiting
            for (id, managed) in windows where managed.workspace == workspace.name && managed.floating && !managed.isOutOfLayout {
                // A tab of a group that does not show waits out of sight, like a window of a hidden workspace.
                if waiting.contains(id) { continue }
                targets[id] = workspace.fullscreen == id ? monitor.workArea : (managed.floatFrame ?? managed.info.frame)
                visible.insert(id)
            }
        }
        if let drag = modifierDrag, drag.followsPointer { targets[drag.window] = drag.frame }
        // macOS moves a window that is dragged by its title bar: wm gives it no frame until the drop.
        if let drop = dragDrop, drop.native { targets[drop.dragged] = nil }
        // The window of a drag with a picture waits out of sight; the picture is what moves.
        if let drag = modifierDrag, drag.picture, let size = currentFrame(of: drag.window)?.size {
            targets[drag.window] = CGRect(origin: hiddenCorner(), size: size)
        }
        let corner = hiddenCorner()
        for (id, managed) in windows where !visible.contains(id) && !managed.isOutOfLayout && parksWhenHidden(managed) {
            let size = animator.frames[id]?.size ?? managed.info.frame.size
            targets[id] = CGRect(origin: corner, size: size)
        }
        for (id, managed) in windows where managed.swallowedBy != nil {
            let size = animator.frames[id]?.size ?? managed.info.frame.size
            targets[id] = CGRect(origin: corner, size: size)
        }
        let parkedNow = Set(visible.filter { targets[$0]?.origin == corner })
        let slides = slideStarts(targets: targets, visible: visible, corner: corner)
        var snap = visible.symmetricDifference(lastVisible)
            .union(targets.keys.filter { !visible.contains($0) })
            .union(parkedNow).union(lastParked)
        if !settings.animations.windows.enabled { snap.formUnion(targets.keys) }
        if let drag = modifierDrag, drag.picture { snap.insert(drag.window) }
        snap.subtract(slides.keys)
        lastVisible = visible
        lastParked = parkedNow
        for id in visible where !parkedNow.contains(id) { lastShownFrame[id] = targets[id] }
        animator.setTargets(targets, snap: snapAll ? Set(targets.keys) : snap)
        if !snapAll { for (id, slide) in slides { animator.start(id, from: slide.from, rate: slide.rate) } }
        applier.send(animator.frames, windows: windows)
        startClockIfNeeded()
        updateBorder()
        updateDim()
        updateTabIndicator()
        publishStatus()
        onWorkspacesShown?(Dictionary(uniqueKeysWithValues: monitors.map { ($0.id, (workspace: $0.workspace, special: specials[$0.id])) }))
        scheduleSave()
    }

    private func slideStarts(
        targets: [WindowID: CGRect], visible: Set<WindowID>, corner: CGPoint
    ) -> [WindowID: (from: CGRect, rate: Double)] {
        guard let request = pendingSlide else { return [:] }
        pendingSlide = nil
        if isNative { return [:] }
        let animations = settings.animations
        let kind = request.kind == .workspace ? animations.workspaces : animations.special
        guard animations.enabled, kind.enabled, kind.style != .none,
              let monitor = monitor(showing: request.workspace) else { return [:] }
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

    func publishStatus() {
        let shown = focusedWorkspace
        let floating = focused.flatMap { windows[$0] }.map { $0.floating && !$0.isOutOfLayout && ($0.sticky || $0.workspace == shown?.name) } ?? false
        var label = menuLabelOverride.map { [StatusSegment($0)] }
        if label == nil, let shown {
            var counts: [String: Int] = [:]
            for managed in windows.values where !managed.sticky && !SpecialWorkspace.isSpecial(managed.workspace) {
                counts[managed.workspace, default: 0] += 1
            }
            let persistent = persistentWorkspaces.filter { !SpecialWorkspace.isSpecial($0) }
            var all = counts.map { WorkspaceStatus(name: $0.key, layout: workspaces[$0.key]?.kind, count: $0.value, persistent: persistent.contains($0.key)) }
            for name in persistent where counts[name] == nil {
                all.append(WorkspaceStatus(name: name, layout: workspaces[name]?.kind, count: 0, persistent: true))
            }
            let current = WorkspaceStatus(name: shown.name, layout: shown.kind, count: counts[shown.name] ?? 0)
            label = StatusLabel.segments(workspaces: all, current: current, floating: floating, settings: settings.menuBar)
        }
        onRelayout?(shown?.name, shown?.kind, label ?? [])
    }

    func setMenuLabel(_ text: String?) {
        menuLabelOverride = text
        publishStatus()
    }

    func layoutContext(for monitor: Monitor, gaps: Gaps? = nil) -> LayoutContext {
        let frames = monitors.map { MonitorFrame(id: $0.id, frame: $0.frame) }
        var edges: Set<Direction> = [.left, .right, .down]
        for direction in [Direction.left, .right, .down] where MonitorGeometry.adjacent(to: monitor.id, direction, in: frames) != nil {
            edges.remove(direction)
        }
        return LayoutContext(viewport: monitor.workArea, gaps: gaps ?? settings.gaps, hiddenCorner: hiddenCorner(), sliverEdges: edges)
    }

    func layoutContext(forWorkspace name: String) -> LayoutContext {
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

    private func hiddenCorner() -> CGPoint {
        MonitorGeometry.hiddenCorner(of: monitors.map(\.frame))
    }

    var animationSummary: String { applier.stats.summary }

    private func startClockIfNeeded() {
        guard !animator.isSettled, clock == nil else { return }
        applier.stats.reset()
        lastTick = CACurrentMediaTime()
        clock = DisplayClock(fps: settings.animations.fps) { [weak self] in self?.tick() }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        defer { applier.stats.work(seconds: CACurrentMediaTime() - now) }
        let changed = animator.step(dt: now - lastTick)
        applier.stats.tick(interval: now - lastTick)
        lastTick = now
        applier.send(changed.filter { windows[$0.key] != nil }, windows: windows)
        updateBorder()
        updateDim(reorder: false)
        updateTabIndicator()
        if animator.isSettled {
            clock?.stop()
            clock = nil
        }
    }

    private func tabPosition(of window: WindowID, in engine: any LayoutEngine) -> (index: Int, count: Int)? {
        if let scrolling = engine as? ScrollingEngine {
            return scrolling.tabs(of: window).flatMap { tabs in tabs.firstIndex(of: window).map { ($0, tabs.count) } }
        }
        if let monocle = engine as? MonocleEngine, let position = monocle.position(of: window), position.count > 1 { return position }
        return nil
    }

    private func updateTabIndicator() {
        // A float group shows its tabs like a tabbed column.
        if settings.tabIndicator.enabled, let focused, let managed = windows[focused], managed.floating, isVisible(managed.workspace),
           let members = floatGroups.group(of: focused), let index = members.firstIndex(of: focused), let frame = currentFrame(of: focused) {
            tabIndicator.show(on: frame, count: members.count, selected: index, settings.tabIndicator)
            return
        }
        guard settings.tabIndicator.enabled, let focused, let managed = windows[focused], !managed.isOutOfLayout, !managed.floating,
              isVisible(managed.workspace), workspace(managed.workspace).fullscreen == nil,
              let (index, count) = tabPosition(of: focused, in: workspace(managed.workspace).engine),
              let frame = currentFrame(of: focused) else {
            tabIndicator.hide()
            return
        }
        tabIndicator.show(on: frame, count: count, selected: index, settings.tabIndicator)
    }

    /// `reorder` is false for the frames of an animation: the layers only move. After a change they are ordered again
    /// a moment later, when the windows that were raised are in place.
    func updateDim(reorder: Bool = true) {
        dimOverlay.show(dimTargets(actual: false), reorder: reorder)
        if reorder { settleDim() }
    }

    private func settleDim() {
        dimSettle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.animator.isSettled else { return self.settleDim() }
                self.dimOverlay.show(self.dimTargets(actual: true), reorder: true)
            }
        }
        dimSettle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func updateBorder() {
        guard let focused, let managed = windows[focused], !managed.isOutOfLayout, settings(forWorkspace: managed.workspace).border.enabled,
              let frame = borderLiveFrame.flatMap({ $0.id == focused ? $0.frame : nil }) ?? currentFrame(of: focused),
              isVisible(managed.workspace) else {
            border.hide()
            return
        }
        var style = settings(forWorkspace: managed.workspace).border
        if let colors = managed.borderColors, let first = colors.first {
            style.active = first
            style.gradient = colors.count >= 2 ? colors : []
        }
        border.show(around: frame, style)
    }

    func restoreAll() {
        let group = DispatchGroup()
        for (id, managed) in windows where parkedForRestore(id, managed) && (!managed.isOutOfLayout || managed.swallowedBy != nil) {
            let size = lastShownFrame[id]?.size ?? managed.info.frame.size
            let area = (monitors.first { $0.id == focusedMonitorID } ?? monitors.first)?.workArea ?? .zero
            let frame = lastShownFrame[id] ?? CGRect(
                x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height
            )
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

    var modifierDrag: ModifierDrag?
    /// A tiled window that is being dragged with a space opened for it: the layout already shows the drop.
    private var dragDrop: DragDrop?
    /// A floating window that is dragged, and where it goes if it is dropped now (`nil`: where it is let go).
    private var floatDrag: (id: WindowID, target: FloatDrop?, native: Bool, start: CGRect)?
    /// Floating windows grouped as tabs.
    var floatGroups = FloatGroups()
    let movePreview = MovePreviewOverlay()
    let dragPicture = DragPicture()
    /// A tiled window whose title bar the button went down on: it may be dragged by macOS. `moving` once it has really moved.
    private var titleBarPress: (id: WindowID, start: CGRect, moving: Bool)?
    private var lastPreviewCheck: TimeInterval = 0
    private var mouseIsDown = false
    private var gestureCounter = 0
    private var gestureBaseline: [WindowID: CGRect]?
    private var borderLiveFrame: (id: WindowID, frame: CGRect)?
    private var borderClock: DisplayClock?
    private var borderStableTicks = 0
    private var borderSettleStart: TimeInterval = 0

    func mouseButton(isDown: Bool) {
        mouseIsDown = isDown
        if isDown { beginGesture() } else { endGesture() }
    }

    private func beginGesture() {
        gestureBaseline = nil
        gestureCounter += 1
        // Only a border has to follow the window while the button is down.
        let shown = windows.filter { !$0.value.isOutOfLayout && isVisible($0.value.workspace) }
        if shown.values.contains(where: { settings(forWorkspace: $0.workspace).border.enabled }) { followBorder() }
        let tiledFrames = shown.filter { !$0.value.floating }.keys.compactMap(currentFrame(of:))
        titleBarPress = nil
        if settings.mouse.movePreview, modifierDrag == nil, let pointer = CGEvent(source: nil)?.location {
            if let id = WindowList.topmost(at: pointer, among: Set(shown.keys)), let frame = currentFrame(of: id),
               pointer.y < frame.minY + MouseGesture.titleBar {
                titleBarPress = (id, frame, false)
            }
        }
        guard let tracker, animator.isSettled, let pointer = CGEvent(source: nil)?.location,
              MouseGesture.mayRearrange(at: pointer, frames: tiledFrames) else { return }
        let gesture = gestureCounter
        Task { @MainActor in
            let frames = await tracker.frameSnapshot()
            guard mouseIsDown, gesture == gestureCounter else { return }
            gestureBaseline = frames.filter { isLaidOutAndShown($0.key) }
        }
    }

    private func followBorder() {
        commitBorder()
        borderClock?.stop()
        borderClock = nil
        guard modifierDrag == nil else { return }
        borderClock = DisplayClock(fps: 120) { [weak self] in self?.tickBorder() }
    }

    private func tickBorder() {
        if mouseIsDown { refreshLiveBorder() } else { settleBorder() }
    }

    func refreshLiveBorder() {
        guard mouseIsDown, modifierDrag == nil, let id = borderLiveFrame?.id ?? focused, let managed = windows[id],
              settings(forWorkspace: managed.workspace).border.enabled, let frame = WindowList.bounds(of: id),
              frame != (borderLiveFrame?.frame ?? currentFrame(of: id)) else { return }
        borderLiveFrame = (id, frame)
        updateBorder()
    }

    private func settleBorder() {
        guard let live = borderLiveFrame else { return commitBorder() }
        if let frame = WindowList.bounds(of: live.id), frame != live.frame {
            borderLiveFrame = (live.id, frame)
            borderStableTicks = 0
            updateBorder()
        } else {
            borderStableTicks += 1
        }
        if borderStableTicks >= 3 || ProcessInfo.processInfo.systemUptime - borderSettleStart > 0.3 { commitBorder() }
    }

    private func commitBorder() {
        borderClock?.stop()
        borderClock = nil
        borderStableTicks = 0
        guard let live = borderLiveFrame else { return }
        borderLiveFrame = nil
        guard windows[live.id]?.floating == true else { return updateBorder() }
        setFloatFrame(live.id, live.frame)
        windows[live.id]?.info.frame = live.frame
        animator.place(live.id, at: live.frame)
        applier.forget(live.id)
        relayout()
    }

    private func endGesture() {
        titleBarPress = nil
        movePreview.hide()
        if let drag = floatDrag, drag.native {
            finishFloatDrop(from: WindowList.bounds(of: drag.id))
            gestureBaseline = nil
            updateBorder()
            return
        }
        if let drop = dragDrop, drop.native {
            // The drop is already in the layout: no swap, no resize to read back.
            finishDrop(from: WindowList.bounds(of: drop.dragged))
            gestureBaseline = nil
            borderClock?.stop()
            borderClock = nil
            borderLiveFrame = nil
            updateBorder()
            return
        }
        if let live = borderLiveFrame, windows[live.id]?.floating == true {
            borderSettleStart = ProcessInfo.processInfo.systemUptime
            borderStableTicks = 0
        } else {
            borderClock?.stop()
            borderClock = nil
        }
        guard let baseline = gestureBaseline, let tracker else {
            gestureBaseline = nil
            if borderClock == nil { borderLiveFrame = nil; updateBorder() }
            return
        }
        gestureBaseline = nil
        Task { @MainActor in
            let frames = await tracker.frameSnapshot()
            if borderClock == nil { borderLiveFrame = nil }
            applyMouseResize(frames, baseline)
            updateBorder()
        }
    }

    /// A drag event with no modifier drag: when the window pressed by its title bar has moved, the placeholder follows the pointer.
    func nativeDragMoved(to pointer: CGPoint) {
        guard let press = titleBarPress else { return }
        if !press.moving {
            // One look at the real frame per frame of the screen: a press on a title bar is not always a move.
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastPreviewCheck >= 1.0 / 60 else { return }
            lastPreviewCheck = now
            guard let frame = WindowList.bounds(of: press.id), MovePreview.isMoving(from: press.start, to: frame) else { return }
            titleBarPress?.moving = true
        }
        if windows[press.id]?.floating == true { return updateFloatDrop(of: press.id, pointer: pointer, native: true) }
        if !updateDrop(of: press.id, pointer: pointer, native: true) { showMovePreview(of: press.id, pointer: pointer) }
    }

    /// Shows where the dragged floating window goes if it is dropped now: an edge or a corner of the screen, against another
    /// floating window, or into a group with it (Cmd held over its middle).
    func updateFloatDrop(of id: WindowID, pointer: CGPoint, native: Bool) {
        guard settings.mouse.movePreview, let managed = windows[id], managed.floating, isVisible(managed.workspace),
              let frame = currentFrame(of: id) else { return }
        if floatDrag == nil, native { beginLayoutChange() }
        let context = layoutContext(forWorkspace: managed.workspace)
        let others = Dictionary(uniqueKeysWithValues: windows.compactMap { other, window -> (WindowID, CGRect)? in
            guard other != id, window.workspace == managed.workspace, window.floating, !window.isOutOfLayout,
                  !floatGroups.waiting.contains(other), let frame = currentFrame(of: other) else { return nil }
            return (other, frame)
        })
        // A drag by the title bar reaches macOS too: when macOS tiles at the edges, wm leaves them to it.
        let target = FloatDrop.target(
            pointer: pointer, dragged: id, size: frame.size, others: others, area: context.gaps.outerArea(context.viewport),
            edges: !native || !SystemGestures.tilesByEdgeDrag, grouping: EventTap.currentFlags().contains(.maskCommand))
        floatDrag = (id, target, native, floatDrag?.start ?? frame)
        let radius = settings(forWorkspace: managed.workspace).border.radius
        switch target {
        case .frame(let slot)?: movePreview.show(slot, radius: radius, below: id)
        case .group(let other)?: if let slot = others[other] { movePreview.show(slot, radius: radius, below: id) }
        case nil: movePreview.hide()
        }
    }

    /// Ends the drag of a floating window: it springs from `frame` to the place that the drop chose, or joins a group. `false` when
    /// no floating window was dragged.
    @discardableResult
    func finishFloatDrop(from frame: CGRect?) -> Bool {
        guard let drag = floatDrag else { return false }
        floatDrag = nil
        movePreview.hide()
        if drag.native, drag.target == nil {
            // A plain move by the title bar: the window is where macOS left it (maybe tiled by macOS at an edge), and the next
            // refresh reads that place. Writing the frame of the release back would undo macOS's tile.
            if floatGroups.group(of: drag.id) != nil { leaveGroup(drag.id, frame: drag.start) }
            endLayoutChange()
            return true
        }
        if let frame { animator.place(drag.id, at: frame) }
        if case .group = drag.target {} else if floatGroups.group(of: drag.id) != nil {
            // Dragged out of its group: the next tab stays where the group was.
            leaveGroup(drag.id, frame: drag.start)
        }
        switch drag.target {
        case .frame(let slot)?:
            setFloatFrame(drag.id, slot)
        case .group(let other)?:
            if let place = windows[other]?.floatFrame ?? currentFrame(of: other) { setFloatFrame(drag.id, place) }
            floatGroups.join(drag.id, with: other)
        case nil:
            if let frame { setFloatFrame(drag.id, frame) }
        }
        // The border must not write the frame of the drag back over the drop.
        borderClock?.stop()
        borderClock = nil
        borderLiveFrame = nil
        relayout()
        if drag.native { endLayoutChange() }
        return true
    }

    /// `id` leaves its float group. When it was the tab that showed, the next tab shows in `frame`, where the group was.
    func leaveGroup(_ id: WindowID, frame: CGRect?) {
        guard let members = floatGroups.group(of: id) else { return }
        let wasFront = floatGroups.shownMember(of: id) == id
        floatGroups.leave(id)
        guard wasFront, let frame, let rest = members.first(where: { $0 != id }) else { return }
        // A group of one ends: its last window is then a plain floating window, in the frame of the group.
        let next = floatGroups.shownMember(of: rest) ?? rest
        windows[next]?.floatFrame = frame
    }

    /// The window `step` tabs away in the group of `id` shows, in the same frame. `false` when `id` is in no group.
    func cycleGroup(of id: WindowID, by step: Int) -> Bool {
        guard let front = floatGroups.shownMember(of: id), let next = floatGroups.cycle(id, by: step), next != front else {
            return floatGroups.group(of: id) != nil
        }
        if let frame = windows[front]?.floatFrame { setFloatFrame(next, frame) }
        focus(next)
        return true
    }

    /// Opens a space for the dragged tiled window at the zone under `pointer`: its neighbours move aside and the placeholder shows
    /// the slot. The layout changes only when the zone does. `false` when this layout has no live drop (monocle, floating,
    /// maximize, fullscreen); the caller then shows the plain placeholder.
    func updateDrop(of id: WindowID, pointer: CGPoint, native: Bool) -> Bool {
        guard settings.mouse.movePreview, let managed = windows[id], !managed.floating, !managed.isOutOfLayout,
              isVisible(managed.workspace) else { return false }
        let space = workspace(managed.workspace)
        guard [.tiling, .scrolling, .master].contains(space.kind), space.fullscreen == nil, !space.maximized.contains(id) else { return false }
        let context = layoutContext(forWorkspace: space.name)
        if dragDrop == nil {
            // A drag by the title bar is one step of `layout undo`; a modifier drag is one already.
            if native { beginLayoutChange() }
            let tiles = space.engine.frames(in: context, focused: id)
            dragDrop = DragDrop(workspace: space.name, dragged: id, original: space.engine, tiles: tiles, native: native)
        }
        guard var drop = dragDrop, drop.dragged == id else { return true }
        let zone = DropZone.find(pointer: pointer, dragged: id, tiles: drop.tiles, area: context.gaps.outerArea(context.viewport))
        guard zone != drop.zone else { return true }
        drop.zone = zone
        dragDrop = drop
        space.engine = DropPlan.apply(zone, dragged: id, to: drop.original, in: context) ?? drop.original
        relayout()
        if zone != .none, let slot = space.engine.frames(in: context, focused: id)[id] {
            movePreview.show(slot, radius: settings(forWorkspace: space.name).border.radius, below: id)
        } else {
            movePreview.hide()
        }
        return true
    }

    /// A window that waited out of sight during a drag with a picture animates to its tile at the drop, instead of jumping there
    /// as a window that comes back from a hidden workspace does.
    func springBack(_ id: WindowID) {
        lastParked.remove(id)
    }

    /// Ends a drag that opened a space. The layout keeps the drop, or goes back to how it was when the zone is none. The window
    /// springs from `frame`, where the user let go, into its tile. `false` when no such drag was going on.
    @discardableResult
    func finishDrop(from frame: CGRect?) -> Bool {
        guard let drop = dragDrop else { return false }
        dragDrop = nil
        movePreview.hide()
        let space = workspace(drop.workspace)
        if drop.zone == .none {
            space.engine = drop.original
            // A window that closed during the drag is not in the layout any more.
            for id in space.engine.windows where windows[id] == nil && !Placeholder.isPlaceholder(id) { space.engine.remove(id) }
        }
        springBack(drop.dragged)
        if let managed = windows[drop.dragged] {
            if let frame {
                // From where the user let go: the place of a window that waited out of sight, or the start of one that macOS moved.
                animator.seed(drop.dragged, at: frame)
                animator.place(drop.dragged, at: frame)
            }
            applier.resend(drop.dragged, pid: managed.info.pid)
        }
        relayout()
        if drop.native { endLayoutChange() }
        return true
    }

    /// Shows the slot where the tiled window `id` lands when it is dropped at `pointer`, or hides the placeholder when there is
    /// none: a floating, maximized or fullscreen window has no slot to show.
    func showMovePreview(of id: WindowID, pointer: CGPoint) {
        guard settings.mouse.movePreview, let managed = windows[id], !managed.floating, !managed.isOutOfLayout,
              isVisible(managed.workspace) else { return movePreview.hide() }
        let space = workspace(managed.workspace)
        guard space.fullscreen == nil, !space.maximized.contains(id) else { return movePreview.hide() }
        let tiles = space.engine.frames(in: layoutContext(forWorkspace: space.name), focused: id)
        guard let slot = MovePreview.target(pointer: pointer, dragged: id, tiles: tiles) else { return movePreview.hide() }
        movePreview.show(slot, radius: settings(forWorkspace: space.name).border.radius, below: id)
    }

    private func isLaidOutAndShown(_ id: WindowID) -> Bool {
        guard let managed = windows[id] else { return false }
        return !managed.floating && !managed.isOutOfLayout && isVisible(managed.workspace)
    }

    private func isPinnedToArea(_ id: WindowID) -> Bool {
        guard let managed = windows[id] else { return false }
        let space = workspace(managed.workspace)
        return space.fullscreen == id || space.maximized.contains(id)
    }

    private func isTiledAndShown(_ id: WindowID) -> Bool {
        guard let managed = windows[id] else { return false }
        return !managed.floating && !managed.isOutOfLayout && isVisible(managed.workspace)
            && workspace(managed.workspace).fullscreen == nil && !workspace(managed.workspace).maximized.contains(id)
    }

    private func applyMouseResize(_ frames: [WindowID: CGRect], _ baseline: [WindowID: CGRect]) {
        beginLayoutChange()
        defer { endLayoutChange() }
        let tolerance: CGFloat = 3
        var changed = false
        for (id, after) in frames {
            guard let before = baseline[id], isLaidOutAndShown(id), let managed = windows[id] else { continue }
            let resized = abs(after.width - before.width) > tolerance || abs(after.height - before.height) > tolerance
            let moved = hypot(after.minX - before.minX, after.minY - before.minY) > tolerance
            guard resized || moved else { continue }
            changed = true
            applier.resend(id, pid: managed.info.pid)
            if isPinnedToArea(id) { continue }
            guard isTiledAndShown(id) else { continue }
            animator.place(id, at: after)
            guard resized else {
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
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            matches = windows.filter {
                let title = $0.value.info.title
                return regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil
            }.map(\.key)
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

    func titleBarWindow(at point: CGPoint) -> WindowID? {
        let candidates = Set(windows.filter { !$0.value.isOutOfLayout && isVisible($0.value.workspace) }.keys)
        guard let id = WindowList.topmost(at: point, among: candidates), let frame = currentFrame(of: id),
              titleBarContains(point, frame: frame, height: CGFloat(settings.trackpad.titleBarHeight)) else { return nil }
        return id
    }

    /// The managed window under `point` that is in front. Where only one window is there, as in a tiled layout, its frame says
    /// so without a look at the system: this runs on every move of the mouse with focus-follows-mouse. Where windows overlap (a
    /// floating window over a tile), the window list of macOS says which one is on top.
    func window(at point: CGPoint) -> WindowID? {
        var under: [WindowID] = []
        for monitor in monitors {
            let name = activeWorkspace(of: monitor)
            for (id, managed) in windows where managed.workspace == name && !managed.isOutOfLayout {
                if currentFrame(of: id)?.contains(point) == true { under.append(id) }
            }
        }
        guard under.count > 1 else { return under.first }
        return WindowList.topmost(at: point, among: Set(under)) ?? under.first
    }

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
