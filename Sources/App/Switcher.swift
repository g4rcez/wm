import AppKit
import Core
import Platform
import Scripting

/// The Alt+Tab window switcher: a miniature of the focused workspace's layout with a picture of every window.
///
/// `wm.bind("alt-tab", "switcher")` opens it. While the modifier of that chord is held, Tab / Shift+Tab move the
/// selection through the windows (most recent first), the arrow keys move it across the miniature, and letting go of the
/// modifier focuses the selected window. Return commits and Escape cancels. Opened without a modifier (`wm switcher`,
/// a URL), it stays open until Return or Escape. Focus never moves while the switcher is open, so Escape has nothing
/// to restore.
///
/// `overview` shows all workspaces that hold windows as small screens in one column (see `OverviewOverlay`): the arrow keys
/// move the selection (Ctrl with h j k l or w a s d does the same), typing searches, Return focuses the window and shows its workspace, Escape closes.
@MainActor
final class SwitcherController {
    private struct Session {
        var model: SwitcherModel
        /// The modifiers whose release commits the selection. Empty: sticky.
        var hold: CGEventFlags
        var monitorFrame: CGRect
        var panelSize: CGSize
        var tiles: [SwitcherOverlay.Tile]
        /// The on-screen parts of the layout, in panel points like the tiles.
        var viewports: [CGRect]
        /// The overview of all workspaces (the Alt+Tab switcher has none).
        var overview: OverviewSession?
        var isOverview: Bool { overview != nil }
        /// `switcher --all`: every window of every workspace, most recent first.
        var isAll = false
        var shown = false
    }

    /// What the overview panel shows, and what the search needs to filter it.
    private struct OverviewSession {
        var geometry: OverviewGeometry
        var rows: [OverviewOverlay.RowInfo]
        /// The workspace of each row, in the same order as `rows` (the last one is the new workspace).
        var rowNames: [String]
        var cards: [OverviewOverlay.Card]
        /// What the search looks at in each window, in lower case: the title, the app, the workspace and the marks.
        var haystacks: [WindowID: String]
        var query = ""
        /// The slot that starts in the middle of the screen: the workspace that has the focus.
        var focusedRow = 0
        /// The overview fades in when it opens. It does not after a drop, because it was there before.
        var animated = true
    }

    /// The modifiers that keep the switcher open. Shift is not one of them: it only reverses Tab.
    private static let holdMask: CGEventFlags = [.maskAlternate, .maskControl, .maskCommand]

    private let manager: WindowManager
    private let overlay = SwitcherOverlay()
    private let overviewOverlay = OverviewOverlay()
    /// The search text that the overview opens with again after a window was closed from it.
    private var pendingQuery = ""
    private let thumbnails = ThumbnailService()
    private var images: [WindowID: CGImage] = [:]
    private var session: Session?
    private var delayTimer: Timer?
    private var pollTimer: Timer?
    private var captureTask: Task<Void, Never>?
    private var lastFocused: WindowID?
    private var refreshTimer: Timer?
    /// wm parks the windows of other workspaces off screen, where ScreenCaptureKit cannot see them (`ThumbnailService` falls
    /// back to SkyLight for those). Pictures are also taken while the windows are visible, and kept for the overview: an
    /// app that does not draw while it is parked leaves a stale picture.
    private var visibleRefresh: Timer?
    private var capturedAt: [WindowID: Date] = [:]
    /// The window that `cmd-w` asked to close. When it is gone, the panel opens again without it.
    private var closing: WindowID?

    /// The last picture of a window, taken while it was on screen. The palette shows it as a preview.
    func cachedImage(_ id: WindowID) -> CGImage? { images[id] }

    /// The modifiers of the key press that is being handled right now (empty for commands from the CLI or a URL).
    var chordFlags: () -> CGEventFlags = { [] }

    init(manager: WindowManager) {
        self.manager = manager
        overlay.onClick = { [unowned self] id in
            if let id { select(id); commit() } else { cancel() }
        }
        overlay.onDrop = { [unowned self] id, row in drop(id, onRow: row) }
        // A click focuses the card that was clicked, also a dimmed one that the search does not select.
        overviewOverlay.onClick = { [unowned self] id in
            close()
            if let id { manager.focus(id) }
        }
        overviewOverlay.onClose = { [unowned self] id in closeWindow(id) }
        overviewOverlay.onHover = { [unowned self] id in if session?.model.selected != id { select(id) } }
        overviewOverlay.onDrop = { [unowned self] id, row in drop(id, onRow: row) }
        manager.events.add { [unowned self] name, payload in
            switch name {
            case "window_focus":
                windowFocused(payload["id"])
                scheduleVisibleRefresh()
            case "workspace_changed", "window_open", "layout_changed", "config_reloaded": scheduleVisibleRefresh()
            case "window_close":
                guard case let .number(raw)? = payload["id"] else { break }
                images[WindowID(raw)] = nil
                capturedAt[WindowID(raw)] = nil
                if closing == WindowID(raw) {
                    closing = nil
                    reopen()
                }
            default: break
            }
        }
    }

    var isOpen: Bool { session != nil }

    // MARK: - Commands

    /// `switcher [next|prev|commit|cancel] [--all]`. With `--all` it lists the windows of all workspaces.
    func command(_ arguments: [String], preselect: WindowID? = nil) -> String? {
        let all = arguments.contains("--all")
        let words = arguments.filter { $0 != "--all" }
        switch words.first {
        case nil, "open", "next":
            if isOpen { step(1) } else { return open(preselect: preselect, all: all) }
        case "prev": if isOpen { step(-1) } else { return open(reverse: true, preselect: preselect, all: all) }
        case "commit": commit()
        case "cancel": cancel()
        default: return "usage: switcher [next|prev|commit|cancel] [--all]"
        }
        return nil
    }

    /// `switcher --all`: a row of tiles, one per window of every workspace, most recent first. Choosing one shows its
    /// workspace.
    private func openAll(reverse: Bool, preselect: WindowID?, hold: CGEventFlags?) -> String? {
        guard let monitor = manager.focusedMonitor else { return "no monitor" }
        let listed = manager.windows.filter { !$0.value.isOutOfLayout }.keys
        let ids = manager.recent.filter { listed.contains($0) } + listed.filter { !manager.recent.contains($0) }.sorted()
        let overview = Miniature.grid(ids, tile: CGSize(width: 320, height: 200), columns: min(max(ids.count, 1), 5), spacing: 24)
        var model = SwitcherModel(overview: overview, floating: [:], mru: ids, focused: manager.focused)
        guard model.selected != nil else { return "no windows to switch between" }
        if reverse { model.step(-2) }
        if let preselect { model.select(preselect) }
        let error = present(model, floating: [], on: monitor, hold: hold ?? chordFlags().intersection(Self.holdMask))
        session?.isAll = true
        return error
    }

    /// After a reboot the layouts hold places for windows that have not opened yet. They have nothing to show.
    private func withoutPlaceholders(_ overview: LayoutOverview) -> LayoutOverview {
        LayoutOverview(frames: overview.frames.filter { manager.windows[$0.key] != nil }, viewports: overview.viewports)
    }

    /// `cmd-w` in the panel: the app is asked to close the selected window. The panel opens again when it is gone.
    private func closeSelected() {
        guard let id = session?.model.selected else { return }
        closeWindow(id)
    }

    private func closeWindow(_ id: WindowID) {
        guard let managed = manager.windows[id] else { return }
        closing = id
        manager.watcher(for: managed.info.pid)?.close(id)
    }

    private func reopen() {
        guard let current = session else { return }
        let hold = current.hold, wasOverview = current.isOverview, wasAll = current.isAll
        pendingQuery = current.overview?.query ?? ""
        close()
        if wasOverview {
            _ = overview(animated: false)
        } else {
            _ = open(all: wasAll, hold: hold)
        }
    }

    /// Returns an error message when the switcher cannot open.
    private func open(reverse: Bool = false, preselect: WindowID? = nil, all: Bool = false, hold: CGEventFlags? = nil) -> String? {
        if all { return openAll(reverse: reverse, preselect: preselect, hold: hold) }
        guard let monitor = manager.focusedMonitor, let workspace = manager.focusedWorkspace else { return "no monitor" }
        let context = manager.layoutContext(forWorkspace: workspace.name)
        let overview = withoutPlaceholders(workspace.engine.overview(in: context, focused: manager.focused))
        var floating: [WindowID: CGRect] = [:]
        for (id, window) in manager.windows where window.workspace == workspace.name && window.floating && !window.isOutOfLayout {
            floating[id] = manager.currentFrame(of: id) ?? window.info.frame
        }
        var model = SwitcherModel(overview: overview, floating: floating, mru: workspace.history, focused: manager.focused)
        guard model.selected != nil else { return "no windows to switch between" }
        if reverse { model.step(-2) }
        if let preselect { model.select(preselect) }
        return present(model, floating: Set(floating.keys), on: monitor, hold: hold ?? chordFlags().intersection(Self.holdMask))
    }

    /// `overview`: opens the overview of all workspaces, or closes it when it is open. A row shows a workspace in its own
    /// layout. Typing searches the windows, a click focuses one, and dragging a window onto another row moves it there;
    /// the last row is a new, empty workspace.
    /// `mode` is `toggle`, `open` (nothing happens when it is open) or `close` (nothing happens when it is closed). A swipe
    /// of the trackpad up opens it and down closes it. `animated: false` is for the overview that opens again after a drop.
    func overview(mode: String = "toggle", selecting wanted: WindowID? = nil, animated: Bool = true) -> String? {
        if isOpen {
            if mode != "open" { cancel() }
            return nil
        }
        if mode == "close" { return nil }
        guard let monitor = manager.focusedMonitor else { return "no monitor" }
        let shownNames = Set(manager.monitors.map(\.workspace))
        let names = manager.workspaces.keys
            .filter { name in shownNames.contains(name) || manager.windows.values.contains { $0.workspace == name && !$0.isOutOfLayout } }
            .sorted {
                let special = (SpecialWorkspace.isSpecial($0), SpecialWorkspace.isSpecial($1))
                return special.0 == special.1 ? $0.compare($1, options: .numeric) == .orderedAscending : special.1
            }
        var inputs: [OverviewRowInput] = []
        var infos: [OverviewOverlay.RowInfo] = []
        var cards: [OverviewOverlay.Card] = []
        var haystacks: [WindowID: String] = [:]
        for name in names {
            let context = manager.layoutContext(forWorkspace: name)
            let workspace = manager.workspace(name)
            var part = withoutPlaceholders(workspace.engine.overview(in: context, focused: manager.focused))
            // A floating window is at a place on the screen; a scrolling strip shows the screen at its scroll position.
            let down = (workspace.engine as? ScrollingEngine)?.runsVertically(in: context) == true
            let scrolledX = down ? 0 : (part.viewports.first?.minX ?? context.viewport.minX) - context.viewport.minX
            let scrolledY = down ? (part.viewports.first?.minY ?? context.viewport.minY) - context.viewport.minY : 0
            var floating: Set<WindowID> = []
            for (id, window) in manager.windows where window.workspace == name && window.floating && !window.isOutOfLayout {
                part.frames[id] = (window.floatFrame ?? window.info.frame).offsetBy(dx: scrolledX, dy: scrolledY)
                floating.insert(id)
            }
            inputs.append(OverviewRowInput(
                frames: part.frames, viewports: part.viewports, screen: context.viewport.size,
                origin: part.viewports.first?.origin ?? context.viewport.origin))
            let count = part.frames.count
            infos.append(OverviewOverlay.RowInfo(
                name: name, subtitle: "\(workspace.kind.rawValue) · \(count == 0 ? "empty" : count == 1 ? "1 window" : "\(count) windows")",
                isCurrent: manager.focusedWorkspace?.name == name, isEmpty: count == 0))
            for id in part.frames.keys {
                guard let window = manager.windows[id] else { continue }
                let icon = NSRunningApplication(processIdentifier: window.info.pid)?.icon
                cards.append(OverviewOverlay.Card(
                    id: id, title: window.info.title, appName: window.info.appName, icon: icon, image: images[id], isFloating: floating.contains(id)))
                haystacks[id] = ([window.info.title, window.info.appName, "workspace " + name] + manager.marks(of: id)).joined(separator: " ").lowercased()
            }
        }
        guard !cards.isEmpty else { return "no windows to show" }
        // An empty screen at the end: a window dropped there goes to the first workspace that nobody uses.
        let taken = Set(names).union(shownNames)
        let fresh = (1...).lazy.map(String.init).first { !taken.contains($0) }!
        inputs.append(OverviewRowInput(frames: [:], viewports: [], screen: monitor.workArea.size, origin: monitor.workArea.origin))
        infos.append(OverviewOverlay.RowInfo(name: fresh, subtitle: "new workspace", isNew: true))

        let settings = manager.settings.switcher
        let geometry = OverviewLayout.compute(
            inputs, screen: monitor.frame.size, zoom: CGFloat(manager.settings.overview.zoom), gap: CGFloat(manager.settings.overview.gap))
        let focusedRow = names.firstIndex { $0 == manager.focusedWorkspace?.name } ?? 0
        let query = pendingQuery
        pendingQuery = ""
        let data = OverviewSession(
            geometry: geometry, rows: infos, rowNames: names + [fresh], cards: cards, haystacks: haystacks, query: query,
            focusedRow: focusedRow, animated: animated)
        var model = overviewModel(data, matching: matches(in: data))
        if let wanted { model.select(wanted) }
        var next = Session(model: model, hold: [], monitorFrame: monitor.frame, panelSize: monitor.frame.size, tiles: [], viewports: [], overview: data)
        next.shown = false
        session = next
        startTimers(delay: 0)
        if settings.thumbnails, !ThumbnailService.hasPermission { ThumbnailService.requestOnce() }
        return nil
    }

    /// The windows whose title, app, workspace or marks hold every word of the search. `nil` without a search.
    private func matches(in data: OverviewSession) -> Set<WindowID>? {
        let words = data.query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }
        return Set(data.cards.map(\.id).filter { id in words.allSatisfy { data.haystacks[id]?.contains($0) == true } })
    }

    /// The selection moves among the cards as they lie on the panel, the matching ones when there is a search. The most
    /// recent window is first, so the best match is under the keys.
    private func overviewModel(_ data: OverviewSession, matching: Set<WindowID>?) -> SwitcherModel {
        let frames = data.geometry.cards.filter { matching?.contains($0.key) ?? true }
        var model = SwitcherModel(overview: LayoutOverview(frames: frames, viewports: []), floating: [:], mru: manager.recent, focused: manager.focused)
        if matching != nil, let first = model.order.first {
            model.select(first)
        } else if let focused = manager.focused {
            model.select(focused)
        }
        return model
    }

    /// Typing in the overview: the search text changes, and the cards that do not match are dimmed.
    private func setQuery(_ text: String) {
        guard var current = session, var data = current.overview else { return }
        data.query = text
        let found = matches(in: data)
        current.overview = data
        current.model = overviewModel(data, matching: found)
        session = current
        guard current.shown else { return }
        overviewOverlay.setSearch(text, matches: found, total: data.cards.count)
        overviewOverlay.select(current.model.selected)
    }

    /// The character that a key adds to the search, or `nil` for a key that is not text.
    private static func searchCharacter(_ key: String) -> String? {
        switch key {
        case "space": return " "
        case "minus": return "-"
        case "period": return "."
        case "comma": return ","
        case "slash": return "/"
        default:
            guard key.count == 1, let scalar = key.unicodeScalars.first, CharacterSet.alphanumerics.contains(scalar) else { return nil }
            return key
        }
    }

    /// The direction of a vim key (`h j k l`) or a WASD key, like the arrow of the same side.
    private static func movement(of key: String) -> Direction? {
        switch key {
        case "h", "a": .left
        case "j", "s": .down
        case "k", "w": .up
        case "l", "d": .right
        default: nil
        }
    }

    private func style() -> ResolvedStyle { manager.settings.overlayStyle() }

    /// The transform that fits a layout into most of the screen; the overlay adds its own padding and title row.
    private func fit(_ overview: LayoutOverview, on monitor: Monitor) -> CGAffineTransform {
        let settings = manager.settings.switcher
        let chrome = SwitcherOverlay.chromeSize(scale: manager.settings.appearance.density.scale)
        let bounds = CGRect(
            x: 0, y: 0,
            width: monitor.frame.width * settings.maxScale - chrome.width,
            height: monitor.frame.height * settings.maxScale - chrome.height
        )
        return Miniature.transform(fitting: Array(overview.frames.values) + overview.viewports, into: bounds, padding: 0, maxScale: 1)
    }

    /// Opens the Alt+Tab panel for a model.
    private func present(_ model: SwitcherModel, floating: Set<WindowID>, on monitor: Monitor, hold: CGEventFlags) -> String? {
        let settings = manager.settings.switcher
        let rects = Array(model.frames.values) + model.viewports
        let fit = fit(LayoutOverview(frames: model.frames, viewports: model.viewports), on: monitor)
        let scaled = rects.map { $0.applying(fit) }
        guard let first = scaled.first else { return "no windows to switch between" }
        let union = scaled.dropFirst().reduce(first) { $0.union($1) }
        let move = CGAffineTransform(translationX: -union.minX, y: -union.minY)
        func place(_ rect: CGRect) -> CGRect { rect.applying(fit).applying(move) }

        let tiles = model.frames.map { id, frame -> SwitcherOverlay.Tile in
            let info = manager.windows[id]?.info
            let icon = info.flatMap { NSRunningApplication(processIdentifier: $0.pid)?.icon }
            return SwitcherOverlay.Tile(
                id: id, frame: place(frame), title: info?.title ?? "", appName: info?.appName ?? "",
                icon: icon, image: images[id], isFloating: floating.contains(id), workspace: manager.windows[id]?.workspace ?? ""
            )
        }
        var next = Session(
            model: model, hold: hold, monitorFrame: monitor.frame, panelSize: union.size, tiles: tiles,
            viewports: model.viewports.map(place)
        )
        // A tap that is over before the switcher opens (the modifier is already up) just switches to the previous window.
        if !hold.isEmpty, EventTap.currentFlags().intersection(hold).isEmpty {
            session = next
            commit()
            return nil
        }
        next.shown = false
        session = next
        startTimers(delay: settings.delay)
        if settings.thumbnails, !ThumbnailService.hasPermission { ThumbnailService.requestOnce() }
        return nil
    }

    // MARK: - Keys and modifiers

    /// Handles a key press while the switcher is open. Returns `true` when the key is used up.
    func handleKey(_ key: String, flags: CGEventFlags) -> Bool {
        guard let session else { return false }
        if key == "w", flags.contains(.maskCommand) {
            closeSelected()
            return true
        }
        // Ctrl with a vim or WASD key moves like the arrows. A plain letter is search text in the overview.
        if session.isOverview, flags.contains(.maskControl), !flags.contains(.maskCommand), let direction = Self.movement(of: key) {
            move(direction)
            return true
        }
        if let data = session.overview, flags.intersection(Self.holdMask).isEmpty {
            // In the overview, text goes into the search.
            if key == "backspace" {
                setQuery(String(data.query.dropLast()))
                return true
            }
            if let character = Self.searchCharacter(key) {
                setQuery(data.query + character)
                return true
            }
        }
        switch key {
        case "tab": step(flags.contains(.maskShift) ? -1 : 1)
        case "left": move(.left)
        case "right": move(.right)
        case "up": move(.up)
        case "down": move(.down)
        case "enter": commit()
        case "space": if session.isOverview { return true } else { commit() }
        case "esc": cancel()
        default:
            // Any other key ends the switcher and is typed as usual.
            cancel()
            return false
        }
        return true
    }

    /// A mouse button went down at `point` (the screen, with the origin at the top left). A click outside the overview
    /// closes it, and the click goes on to what is under it. This comes from the event tap, so it does not depend on the
    /// overview window catching the click: a window with nothing drawn on it can let clicks through.
    func pointerPressed(at point: CGPoint) {
        guard let session, session.isOverview else { return }
        let origin = session.monitorFrame.origin
        if !overviewOverlay.isOnContent(CGPoint(x: point.x - origin.x, y: point.y - origin.y)) { close() }
    }

    func flagsChanged(_ flags: CGEventFlags) {
        guard let session, !session.hold.isEmpty, flags.intersection(session.hold).isEmpty else { return }
        commit()
    }

    // MARK: - Selection

    private func step(_ delta: Int) {
        session?.model.step(delta)
        refreshSelection()
    }

    private func move(_ direction: Direction) {
        session?.model.move(direction)
        refreshSelection()
    }

    private func select(_ id: WindowID) {
        session?.model.select(id)
        refreshSelection()
    }

    private func refreshSelection() {
        guard let session, session.shown else { return }
        if session.isOverview { overviewOverlay.select(session.model.selected) } else { overlay.select(session.model.selected) }
    }

    private func commit() {
        guard let session else { return }
        let target = session.model.selected
        close()
        if let target { manager.focus(target) }
    }

    private func cancel() {
        close()
    }

    /// A window was dropped on a row of the overview: it moves to that workspace and the overview opens again with the
    /// new layout. The focus stays where it is.
    private func drop(_ id: WindowID, onRow row: Int) {
        guard let rowNames = session?.overview?.rowNames, rowNames.indices.contains(row), let window = manager.windows[id] else { return }
        let name = rowNames[row]
        guard name != window.workspace else { return }
        close()
        manager.sendQuietly(id, to: name)
        _ = overview(selecting: id, animated: false)
    }

    private func close() {
        delayTimer?.invalidate()
        pollTimer?.invalidate()
        captureTask?.cancel()
        delayTimer = nil
        pollTimer = nil
        session = nil
        overlay.hide()
        overviewOverlay.hide()
    }

    // MARK: - Overlay and pictures

    private func startTimers(delay: Double) {
        delayTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.showOverlay() }
        }
        // A safety net for the modifier release: Secure Input can hide flagsChanged events from the tap.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let session = self.session, !session.hold.isEmpty else { return }
                if EventTap.currentFlags().intersection(session.hold).isEmpty { self.commit() }
            }
        }
    }

    private func showOverlay() {
        guard var current = session, !current.shown else { return }
        current.shown = true
        session = current
        if let data = current.overview {
            overviewOverlay.show(
                geometry: data.geometry, rows: data.rows, cards: data.cards, row: data.focusedRow, selected: current.model.selected,
                query: data.query, style: style(), on: current.monitorFrame, animated: data.animated)
            if !data.query.isEmpty { overviewOverlay.setSearch(data.query, matches: matches(in: data), total: data.cards.count) }
        } else {
            overlay.show(
                tiles: current.tiles, viewports: current.viewports, labels: [], panelSize: current.panelSize,
                selected: current.model.selected, style: style(), on: current.monitorFrame
            )
        }
        guard manager.settings.switcher.thumbnails, ThumbnailService.hasPermission else { return }
        let ids = current.overview?.cards.map(\.id) ?? current.tiles.map(\.id)
        captureTask = Task { [thumbnails] in
            let captured = await thumbnails.capture(ids)
            guard !Task.isCancelled else { return }
            for (id, image) in captured {
                images[id] = image
                capturedAt[id] = Date()
                if let current = session {
                    if current.isOverview { overviewOverlay.setImage(image, for: id) } else { overlay.setImage(image, for: id) }
                }
            }
        }
    }

    /// A second after the last change of focus or layout, the windows that are on screen get a new picture (at most one in 3
    /// seconds each). A window that a workspace switch parks later keeps its last picture for the overview.
    private func scheduleVisibleRefresh() {
        guard manager.settings.switcher.thumbnails, ThumbnailService.hasPermission else { return }
        visibleRefresh?.invalidate()
        visibleRefresh = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshVisible() }
        }
    }

    private func refreshVisible() {
        guard session == nil else { return }
        let now = Date()
        let ids = manager.windows.filter { id, window in
            !window.isOutOfLayout && manager.isVisible(window.workspace) && now.timeIntervalSince(capturedAt[id] ?? .distantPast) > 3
        }.map(\.key)
        guard !ids.isEmpty else { return }
        Task { [thumbnails] in
            let captured = await thumbnails.capture(ids)
            for (id, image) in captured {
                images[id] = image
                capturedAt[id] = Date()
            }
        }
    }

    /// Keeps the picture cache fresh: a window that just lost focus is captured while it is still on screen, so the
    /// switcher has a good picture of it later even after the layout parks it.
    private func windowFocused(_ id: LuaValue?) {
        guard case let .number(raw)? = id else { return }
        let new = WindowID(raw)
        let previous = lastFocused
        lastFocused = new
        guard let previous, previous != new, manager.settings.switcher.thumbnails, ThumbnailService.hasPermission else { return }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task {
                    let captured = await self.thumbnails.capture([previous])
                    for (id, image) in captured { self.images[id] = image }
                }
            }
        }
    }
}
