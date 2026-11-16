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
/// `overview` uses the same panel for all workspaces that hold windows, one row each: the arrow keys or `h j k l` move
/// the selection, Return focuses the window and shows its workspace, Escape closes. Every window has a key label
/// (`WindowHints`): typing it focuses that window.
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
        /// The overview of all workspaces: one name per row, and `h j k l` move the selection.
        var labels: [SwitcherOverlay.Label] = []
        /// The workspace of each row of the overview, in the same order as `labels`.
        var rowNames: [String] = []
        var isOverview = false
        /// The overview gives every window a key label (`nil` in the Alt+Tab switcher).
        var hints: WindowHints?
        var shown = false
    }

    /// The modifiers that keep the switcher open. Shift is not one of them: it only reverses Tab.
    private static let holdMask: CGEventFlags = [.maskAlternate, .maskControl, .maskCommand]

    private let manager: WindowManager
    private let overlay = SwitcherOverlay()
    private let thumbnails = ThumbnailService()
    private var images: [WindowID: CGImage] = [:]
    private var session: Session?
    private var delayTimer: Timer?
    private var pollTimer: Timer?
    private var captureTask: Task<Void, Never>?
    private var lastFocused: WindowID?
    private var refreshTimer: Timer?

    /// The modifiers of the key press that is being handled right now (empty for commands from the CLI or a URL).
    var chordFlags: () -> CGEventFlags = { [] }

    init(manager: WindowManager) {
        self.manager = manager
        overlay.onClick = { [unowned self] id in
            if let id { select(id); commit() } else { cancel() }
        }
        overlay.onDrop = { [unowned self] id, row in drop(id, onRow: row) }
        manager.events.add { [unowned self] name, payload in
            switch name {
            case "window_focus": windowFocused(payload["id"])
            case "window_close": if case let .number(id)? = payload["id"] { images[WindowID(id)] = nil }
            default: break
            }
        }
    }

    var isOpen: Bool { session != nil }

    // MARK: - Commands

    /// `switcher`, `switcher next`, `switcher prev`, `switcher commit`, `switcher cancel`.
    func command(_ arguments: [String], preselect: WindowID? = nil) -> String? {
        switch arguments.first {
        case nil, "open":
            if isOpen { step(1) } else { return open(preselect: preselect) }
        case "next": if isOpen { step(1) } else { return open(preselect: preselect) }
        case "prev": if isOpen { step(-1) } else { return open(reverse: true, preselect: preselect) }
        case "commit": commit()
        case "cancel": cancel()
        default: return "usage: switcher [next|prev|commit|cancel]"
        }
        return nil
    }

    /// Returns an error message when the switcher cannot open.
    private func open(reverse: Bool = false, preselect: WindowID? = nil) -> String? {
        guard let monitor = manager.focusedMonitor, let workspace = manager.focusedWorkspace else { return "no monitor" }
        let context = manager.layoutContext(forWorkspace: workspace.name)
        let overview = workspace.engine.overview(in: context, focused: manager.focused)
        var floating: [WindowID: CGRect] = [:]
        for (id, window) in manager.windows where window.workspace == workspace.name && window.floating && !window.minimized {
            floating[id] = manager.currentFrame(of: id) ?? window.info.frame
        }
        var model = SwitcherModel(overview: overview, floating: floating, mru: workspace.history, focused: manager.focused)
        guard model.selected != nil else { return "no windows to switch between" }
        if reverse { model.step(-2) }
        if let preselect { model.select(preselect) }
        return present(model, floating: Set(floating.keys), on: monitor, hold: chordFlags().intersection(Self.holdMask))
    }

    /// `overview`: opens the miniature of all workspaces, or closes it when it is open. Dragging a window onto the row
    /// of another workspace moves it there; the last row (not with native desktops) is a new, empty workspace.
    func overview(selecting wanted: WindowID? = nil) -> String? {
        if isOpen {
            cancel()
            return nil
        }
        guard let monitor = manager.focusedMonitor else { return "no monitor" }
        // Native desktops that are not shown hold windows that wm cannot reach.
        let shownDesktops = Set(manager.monitors.map { NativeWorkspaceName.desktop(of: $0.workspace) })
        let names = manager.workspaces.keys
            .filter { name in manager.windows.values.contains { $0.workspace == name && !$0.minimized } }
            .filter { !manager.isNative || shownDesktops.contains(NativeWorkspaceName.desktop(of: $0)) }
            .sorted {
                let special = (SpecialWorkspace.isSpecial($0), SpecialWorkspace.isSpecial($1))
                return special.0 == special.1 ? $0.compare($1, options: .numeric) == .orderedAscending : special.1
            }
        var parts: [LayoutOverview] = []
        var floating: Set<WindowID> = []
        for name in names {
            let context = manager.layoutContext(forWorkspace: name)
            var part = manager.workspace(name).engine.overview(in: context, focused: manager.focused)
            // A floating window is at a place on the screen; a scrolling strip shows the screen at its scroll position.
            let scrolled = (part.viewports.first?.minX ?? context.viewport.minX) - context.viewport.minX
            for (id, window) in manager.windows where window.workspace == name && window.floating && !window.minimized {
                part.frames[id] = (window.floatFrame ?? window.info.frame).offsetBy(dx: scrolled, dy: 0)
                floating.insert(id)
            }
            parts.append(part)
        }
        var rowNames = names
        var rowTexts = names
        if !manager.isNative {
            // An empty screen at the end: a window dropped there goes to the first workspace that nobody uses.
            let taken = Set(names).union(manager.monitors.map(\.workspace))
            let fresh = (1...).lazy.map(String.init).first { !taken.contains($0) }!
            parts.append(LayoutOverview(frames: [:], viewports: [CGRect(origin: .zero, size: monitor.workArea.size)]))
            rowNames.append(fresh)
            rowTexts.append("+ new workspace \(fresh)")
        }
        // The rows need room for their names: about 22 points of the panel, whatever the scale is.
        let scale = fit(Miniature.rows(parts, spacing: 0).overview, on: monitor).a
        let stacked = Miniature.rows(parts, spacing: 22 / scale)
        var model = SwitcherModel(overview: stacked.overview, floating: [:], mru: manager.focusedWorkspace?.history ?? [], focused: manager.focused)
        guard model.selected != nil else { return "no windows to show" }
        if let focused = manager.focused { model.select(focused) }
        if let wanted { model.select(wanted) }
        let rows = zip(rowTexts, stacked.rows).map { SwitcherOverlay.Label(text: $0, frame: $1) }
        return present(model, floating: floating, rows: rows, rowNames: rowNames, on: monitor, hold: [])
    }

    /// The transform that fits a layout into most of the screen; the overlay adds its own padding and title row.
    private func fit(_ overview: LayoutOverview, on monitor: Monitor) -> CGAffineTransform {
        let settings = manager.settings.switcher
        let bounds = CGRect(
            x: 0, y: 0,
            width: monitor.frame.width * settings.maxScale - 40,
            height: monitor.frame.height * settings.maxScale - 70
        )
        return Miniature.transform(fitting: Array(overview.frames.values) + overview.viewports, into: bounds, padding: 0, maxScale: 1)
    }

    /// Opens the panel for a model. `rows` (the overview of all workspaces) are in the model's coordinate space.
    private func present(
        _ model: SwitcherModel, floating: Set<WindowID>, rows: [SwitcherOverlay.Label] = [], rowNames: [String] = [],
        on monitor: Monitor, hold: CGEventFlags
    ) -> String? {
        let settings = manager.settings.switcher
        let rects = Array(model.frames.values) + model.viewports
        let fit = fit(LayoutOverview(frames: model.frames, viewports: model.viewports), on: monitor)
        let scaled = rects.map { $0.applying(fit) }
        guard let first = scaled.first else { return "no windows to switch between" }
        let union = scaled.dropFirst().reduce(first) { $0.union($1) }
        let move = CGAffineTransform(translationX: -union.minX, y: -union.minY)
        func place(_ rect: CGRect) -> CGRect { rect.applying(fit).applying(move) }

        let hints = rows.isEmpty ? nil : WindowHints(frames: model.frames)
        let tiles = model.frames.map { id, frame -> SwitcherOverlay.Tile in
            let info = manager.windows[id]?.info
            let icon = info.flatMap { NSRunningApplication(processIdentifier: $0.pid)?.icon }
            return SwitcherOverlay.Tile(
                id: id, frame: place(frame), title: info?.title ?? "", appName: info?.appName ?? "",
                icon: icon, image: images[id], isFloating: floating.contains(id), hint: hints?.labels[id]
            )
        }
        let labels = rows.map { SwitcherOverlay.Label(text: $0.text, frame: place($0.frame)) }
        var next = Session(
            model: model, hold: hold, monitorFrame: monitor.frame, panelSize: union.size, tiles: tiles,
            viewports: model.viewports.map(place), labels: labels, rowNames: rowNames, isOverview: !rows.isEmpty, hints: hints
        )
        // A tap that is over before the switcher opens (the modifier is already up) just switches to the previous window.
        if !hold.isEmpty, EventTap.currentFlags().intersection(hold).isEmpty {
            session = next
            commit()
            return nil
        }
        next.shown = false
        session = next
        startTimers(delay: rows.isEmpty ? settings.delay : 0)
        if settings.thumbnails, !ThumbnailService.hasPermission { ThumbnailService.requestOnce() }
        return nil
    }

    // MARK: - Keys and modifiers

    /// Handles a key press while the switcher is open. Returns `true` when the key is used up.
    func handleKey(_ key: String, flags: CGEventFlags) -> Bool {
        guard let session else { return false }
        if session.isOverview, let direction = ["h": Direction.left, "j": .down, "k": .up, "l": .right][key] {
            move(direction)
            return true
        }
        if session.hints != nil, flags.intersection(Self.holdMask).isEmpty {
            if key == "backspace" {
                self.session?.hints?.deleteLast()
                showHintPrefix()
                return true
            }
            switch self.session?.hints?.press(key) {
            case .focus(let id)?:
                select(id)
                commit()
                return true
            case .pending?:
                showHintPrefix()
                return true
            case .ignored?, nil:
                break
            }
        }
        switch key {
        case "tab": step(flags.contains(.maskShift) ? -1 : 1)
        case "left": move(.left)
        case "right": move(.right)
        case "up": move(.up)
        case "down": move(.down)
        case "enter", "space": commit()
        case "esc": cancel()
        default:
            // Any other key ends the switcher and is typed as usual.
            cancel()
            return false
        }
        return true
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

    private func showHintPrefix() {
        guard let session, session.shown else { return }
        overlay.setHintPrefix(session.hints?.typed ?? "")
    }

    private func select(_ id: WindowID) {
        session?.model.select(id)
        refreshSelection()
    }

    private func refreshSelection() {
        guard let session, session.shown else { return }
        overlay.select(session.model.selected)
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
    /// new layout. The focus stays where it is. With native desktops only a row of the same desktop can be reached.
    private func drop(_ id: WindowID, onRow row: Int) {
        guard let session, session.rowNames.indices.contains(row), let window = manager.windows[id] else { return }
        let name = session.rowNames[row]
        guard name != window.workspace else { return }
        if manager.isNative, NativeWorkspaceName.desktop(of: name) != NativeWorkspaceName.desktop(of: window.workspace) { return }
        close()
        manager.sendQuietly(id, to: name)
        _ = overview(selecting: id)
    }

    private func close() {
        delayTimer?.invalidate()
        pollTimer?.invalidate()
        captureTask?.cancel()
        delayTimer = nil
        pollTimer = nil
        session = nil
        overlay.hide()
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
        overlay.show(
            tiles: current.tiles, viewports: current.viewports, labels: current.labels, panelSize: current.panelSize,
            selected: current.model.selected, settings: manager.settings.switcher, on: current.monitorFrame
        )
        guard manager.settings.switcher.thumbnails, ThumbnailService.hasPermission else { return }
        let ids = current.tiles.map(\.id)
        captureTask = Task { [thumbnails] in
            let captured = await thumbnails.capture(ids)
            guard !Task.isCancelled else { return }
            for (id, image) in captured {
                images[id] = image
                if session != nil { overlay.setImage(image, for: id) }
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
