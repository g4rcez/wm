import AppKit
import Common
import Core
import Scripting

extension WindowManager {
    /// Runs one command that touches windows, workspaces or layouts. `target` is the window a rule or script
    /// is about; without it the focused window is used.
    func execute(_ args: [String], target: WindowID? = nil) -> ServerAnswer {
        guard let command = args.first else { return fail("missing command", 2, hint: "run `wm help` to see the commands") }
        let rest = Array(args.dropFirst())
        let flags = Set(rest.filter { $0.hasPrefix("--") })
        let words = rest.filter { !$0.hasPrefix("--") }
        let id = target ?? focused

        switch command {
        case "focus": return focusCommand(words, flags, target: target)
        case "move":
            if let bad = unknownOption(flags, allowed: [], usage: "move") { return bad }
            guard let direction = words.first.flatMap(Direction.init(rawValue:)) else { return fail("move needs a direction", 2, usage: "move") }
            return moveDirection(direction, target: id)
        case "swap":
            if let bad = unknownOption(flags, allowed: [], usage: "swap") { return bad }
            guard let direction = words.first.flatMap(Direction.init(rawValue:)) else { return fail("swap needs a direction", 2, usage: "swap") }
            return swapDirection(direction, target: id)
        case "resize":
            if let bad = unknownOption(flags, allowed: [], usage: "resize") { return bad }
            if words == ["maximize"] { return fail("resize maximize is now window maximize", 2, usage: "window maximize") }
            guard words.count == 2, let dimension = ResizeDimension(rawValue: words[0]), let delta = Double(words[1]) else {
                return fail("resize needs a dimension and an amount", 2, usage: "resize")
            }
            return layoutCommand(.resize(dimension, CGFloat(delta)), target: id)
        case "workspace": return workspaceCommand(words, flags, target: target)
        case "window": return windowCommand(words, flags, id)
        case "layout": return layoutGroup(words, flags, id)
        case "list": return listCommand(words, flags, target: target)
        case "pointer":
            if let bad = unknownOption(flags, allowed: [], usage: "pointer") { return bad }
            return moveMouse(words.first, target: id)
        default:
            return fail("unknown command '\(command)'", 2, hint: unknownCommandHint(command) ?? "run `wm help` to see the commands")
        }
    }

    // MARK: - Command groups

    private func focusCommand(_ words: [String], _ flags: Set<String>, target: WindowID?) -> ServerAnswer {
        guard let first = words.first else { return fail("focus needs a direction or a target", 2, usage: "focus") }
        if let direction = Direction(rawValue: first) {
            if let bad = unknownOption(flags, allowed: ["--wrap"], usage: "focus") { return bad }
            focusDirection(direction, wrap: flags.contains("--wrap") || settings.wrapFocus)
            return ok()
        }
        if let bad = unknownOption(flags, allowed: [], usage: "focus") { return bad }
        switch first {
        case "back":
            guard let workspace = focusedWorkspace,
                  let previous = workspace.history.dropFirst().first(where: { windows[$0] != nil }) else { return fail("there is no previous window") }
            focus(previous)
            return ok()
        case "window":
            guard let wanted = words.dropFirst().first.flatMap({ UInt32($0) }) ?? target else {
                return fail("focus window needs the id of a window", 2, usage: "focus window", hint: "see `wm list windows` for ids")
            }
            guard windows[wanted] != nil else { return fail("no window with id \(wanted)", 1, hint: "see `wm list windows` for ids") }
            focus(wanted)
            return ok()
        case "monitor":
            guard let monitor = monitorArgument(words.dropFirst().first) else { return fail("no such monitor", 1, usage: "focus monitor") }
            focusMonitor(monitor.id)
            return ok()
        case "layer":
            let wanted = words.dropFirst().first
            guard wanted == nil || wanted == "floating" || wanted == "tiling" else {
                return fail("focus layer takes floating or tiling", 2, usage: "focus layer")
            }
            return focusLayer(floating: wanted.map { $0 == "floating" })
        default:
            return fail("unknown focus target '\(first)'", 2, usage: "focus")
        }
    }

    /// `focus layer`: the focus goes to the most recent floating window of the workspace, or back to the most recent
    /// tiled one. Without a layer it switches from the one the focused window is in.
    private func focusLayer(floating wanted: Bool?) -> ServerAnswer {
        guard let workspace = focusedWorkspace else { return fail("there is no workspace") }
        let inFloating = focused.flatMap { windows[$0] }.map { $0.workspace == workspace.name && $0.floating } ?? false
        let floating = wanted ?? !inFloating
        func candidates(_ ids: [WindowID]) -> WindowID? {
            ids.first { id in windows[id].map { $0.workspace == workspace.name && $0.floating == floating && !$0.minimized } ?? false }
        }
        guard let next = candidates(workspace.history) ?? candidates(windows.keys.sorted()) else {
            return fail("there is no \(floating ? "floating" : "tiling") window on this workspace")
        }
        focus(next)
        return ok()
    }

    private func workspaceCommand(_ words: [String], _ flags: Set<String>, target: WindowID?) -> ServerAnswer {
        if let bad = unknownOption(flags, allowed: [], usage: "workspace") { return bad }
        switch words.first {
        case "special":
            if isNative { return fail("special workspaces need workspaces = \"emulated\" in the config") }
            guard let name = SpecialWorkspace.name(words.dropFirst().first) else { return fail("bad special workspace name", 2, usage: "workspace special") }
            toggleSpecial(name)
            return ok()
        case "row":
            guard isNative else { return fail("rows need workspaces = \"native\" in the config") }
            guard let row = rowNumber(for: words.dropFirst().first), let desktop = focusedDesktop else { return fail("workspace row needs up, down or a number", 2, usage: "workspace row") }
            return setRow(row, desktop: desktop) ? ok() : fail("cannot show row \(row)")
        default:
            // `wm workspace <name>`, or `wm --window <id> workspace` for the workspace of that window.
            if target != nil, !words.isEmpty { return fail("workspace takes a name or --window, not both", 2, usage: "workspace") }
            guard let name = words.first ?? target.flatMap({ windows[$0]?.workspace }) else { return fail("workspace needs a name", 2, usage: "workspace") }
            let resolved = name == "back" ? (previousWorkspace ?? name) : resolveWorkspaceName(name)
            if SpecialWorkspace.isSpecial(resolved) {
                // `wm --window <id> workspace` for a window of a special workspace shows it; a name does not.
                guard let target else { return fail("special workspaces are shown with `wm workspace special <name>`") }
                focus(target)
                return ok()
            }
            if isNative {
                return switchSpace(to: resolved) ? ok() : fail("no desktop '\(resolved)' on this display", 1, hint: "macOS shortcuts reach desktops 1-10; enable \"Switch to Desktop N\" in Keyboard Shortcuts")
            }
            showWorkspace(resolved, on: focusedMonitorID)
            if let target { focus(target) }
            return ok()
        }
    }

    private func windowCommand(_ words: [String], _ flags: Set<String>, _ id: WindowID?) -> ServerAnswer {
        guard let sub = words.first else { return fail("window needs a command", 2, usage: "window") }
        if sub == "send" { return sendCommand(Array(words.dropFirst()), flags, id) }
        if let bad = unknownOption(flags, allowed: [], usage: "window " + sub) { return bad }
        guard let id, let managed = windows[id] else { return fail("there is no focused window") }
        switch sub {
        case "close":
            watcher(for: managed.info.pid)?.close(id)
            return ok()
        case "float":
            setFloating(id, !managed.floating)
            relayout()
            return ok()
        case "fullscreen":
            let workspace = workspace(managed.workspace)
            workspace.fullscreen = workspace.fullscreen == id ? nil : id
            if workspace.fullscreen != nil { workspace.maximized = [] }
            relayout()
            return ok()
        case "maximize":
            return toggleMaximize(target: id)
        case "pseudo":
            let workspace = workspace(managed.workspace)
            guard workspace.kind == .tiling, !managed.floating else {
                return fail("window pseudo needs a tiled window in the tiling layout", 1, hint: "switch with `wm layout set tiling`")
            }
            if workspace.pseudo[id] != nil {
                workspace.pseudo[id] = nil
            } else if let size = currentFrame(of: id)?.size {
                workspace.pseudo[id] = size
            }
            relayout()
            return ok()
        default:
            return fail("unknown window command '\(sub)'", 2, usage: "window")
        }
    }

    /// `window send <workspace|monitor|row|strip> <where>`: the window goes there and, unless `--stay`, the view follows.
    private func sendCommand(_ words: [String], _ flags: Set<String>, _ id: WindowID?) -> ServerAnswer {
        guard let kind = words.first else { return fail("window send needs a destination", 2, usage: "window send") }
        let value = words.dropFirst().first
        let usage = "window send " + kind
        let stay = flags.contains("--stay"), tile = flags.contains("--tile")
        switch kind {
        case "workspace":
            if let bad = unknownOption(flags, allowed: ["--stay", "--tile"], usage: usage) { return bad }
            guard let given = value else { return fail("window send workspace needs a workspace name", 2, usage: usage) }
            let name = resolveWorkspaceName(given)
            guard let id else { return fail("there is no focused window") }
            if isNative { return fail("moving a window to another desktop needs SIP off", 1, hint: "drag the window in Mission Control instead") }
            if SpecialWorkspace.isSpecial(name), SpecialWorkspace.name(name) == nil { return fail("bad special workspace name", 2, usage: usage) }
            let source = windows[id]?.workspace
            moveWindow(id, to: name)
            arrive(id, tile: tile)
            if stay {
                if let source, let next = workspace(source).history.first(where: { windows[$0] != nil }) { focus(next) } else { relayout() }
            } else {
                // The focus of the window shows a special workspace by itself.
                if !SpecialWorkspace.isSpecial(name) { showWorkspace(name, on: focusedMonitorID, focusWindow: false) }
                focus(id)
            }
            return ok()
        case "monitor":
            if let bad = unknownOption(flags, allowed: ["--tile"], usage: usage) { return bad }
            guard let id else { return fail("there is no focused window") }
            guard let monitor = monitorArgument(value) else { return fail("no such monitor", 1, usage: usage) }
            moveWindow(id, to: monitor.workspace)
            arrive(id, tile: tile)
            focusMonitor(monitor.id)
            focus(id)
            return ok()
        case "row":
            if let bad = unknownOption(flags, allowed: ["--stay", "--tile"], usage: usage) { return bad }
            guard isNative else { return fail("rows need workspaces = \"native\" in the config") }
            guard let row = rowNumber(for: value), let desktop = focusedDesktop else { return fail("window send row needs up, down or a number", 2, usage: usage) }
            guard let id else { return fail("there is no focused window") }
            let source = windows[id]?.workspace
            moveWindow(id, to: NativeWorkspaceName.row(of: desktop, row))
            arrive(id, tile: tile)
            if stay {
                if let source, let next = workspace(source).history.first(where: { windows[$0] != nil }) { focus(next) } else { relayout() }
            } else {
                setRow(row, desktop: desktop, focusWindow: false)
                focus(id)
            }
            return ok()
        case "strip":
            if let bad = unknownOption(flags, allowed: [], usage: usage) { return bad }
            guard let orientation = value.flatMap(Orientation.init(rawValue:)) else { return fail("window send strip needs horizontal or vertical", 2, usage: usage) }
            return layoutCommand(.sendToStrip(orientation), target: id)
        default:
            return fail("unknown destination '\(kind)'", 2, usage: "window send")
        }
    }

    /// A layout command that only the tiling layout has.
    private func tilingCommand(_ command: LayoutCommand, _ id: WindowID?, _ name: String) -> ServerAnswer {
        guard focusedWorkspace?.kind == .tiling else {
            return fail("\(name) needs the tiling layout", 1, hint: "switch with `wm layout set tiling`")
        }
        return layoutCommand(command, target: id)
    }

    private func layoutGroup(_ words: [String], _ flags: Set<String>, _ id: WindowID?) -> ServerAnswer {
        if let bad = unknownOption(flags, allowed: [], usage: "layout") { return bad }
        guard let sub = words.first else { return fail("layout needs a command", 2, usage: "layout") }
        let value = words.dropFirst().first
        switch sub {
        case "set": return setLayout(value)
        case "balance": return layoutCommand(.balance, target: id)
        case "flip": return rotateLayout()
        case "tile": return tile(value, target: id)
        case "rotate":
            guard value == nil || value == "cw" || value == "ccw" else { return fail("layout rotate takes cw or ccw", 2, usage: "layout rotate") }
            return rotate(clockwise: value != "ccw")
        case "preselect":
            guard let side = value.flatMap(Direction.init(rawValue:)) else { return fail("layout preselect needs a direction", 2, usage: "layout preselect") }
            return tilingCommand(.preselect(side), id, "layout preselect")
        case "split":
            switch value {
            case "toggle": return layoutCommand(.toggleSplit, target: id)
            case "swap": return layoutCommand(.swapSplit, target: id)
            case "root": return tilingCommand(.moveToRoot, id, "layout split root")
            case "ratio":
                guard let text = words.dropFirst(2).first, let number = Double(text) else {
                    return fail("layout split ratio needs a number", 2, usage: "layout split ratio")
                }
                return tilingCommand(.splitRatio(number, relative: text.hasPrefix("+") || text.hasPrefix("-")), id, "layout split ratio")
            default: return fail("layout split takes toggle, swap, root or ratio", 2, usage: "layout split")
            }
        case "column":
            switch value {
            case "width":
                let amount = words.dropFirst(2).first
                if amount == "cycle" { return layoutCommand(.columnWidth(.cycle), target: id) }
                guard let fraction = amount.flatMap(Double.init) else { return fail("layout column width needs a fraction or cycle", 2, usage: "layout column width") }
                return layoutCommand(.columnWidth(.fraction(fraction)), target: id)
            case "match": return layoutCommand(.matchWidth, target: id)
            case "center": return layoutCommand(.center, target: id)
            case "center-visible": return layoutCommand(.centerVisible, target: id)
            default: return fail("unknown column command", 2, usage: "layout column")
            }
        case "stack":
            switch value {
            case "join": return layoutCommand(.stack, target: id)
            case "leave": return layoutCommand(.unstack, target: id)
            case "tabs": return layoutCommand(.toggleTabs, target: id)
            case "equalize": return layoutCommand(.equalizeStack, target: id)
            case "height":
                let amount = words.dropFirst(2).first
                if amount == "cycle" { return layoutCommand(.windowHeight(.cycle), target: id) }
                guard let fraction = amount.flatMap(Double.init) else { return fail("layout stack height needs a fraction or cycle", 2, usage: "layout stack height") }
                return layoutCommand(.windowHeight(.fraction(fraction)), target: id)
            default: return fail("layout stack takes join, leave, tabs, equalize or height", 2, usage: "layout stack")
            }
        default:
            let hint = LayoutKind(rawValue: sub) != nil ? "use `wm layout set \(sub)`" : nil
            return fail("unknown layout command '\(sub)'", 2, usage: "layout", hint: hint)
        }
    }

    // MARK: - Focus and move

    private func focusDirection(_ direction: Direction, wrap: Bool) {
        guard let workspace = focusedWorkspace else { return }
        guard let id = focused, let managed = windows[id], managed.workspace == workspace.name else {
            if let first = workspace.history.first ?? workspace.engine.windows.first { focus(first) }
            return
        }
        var next: WindowID?
        if managed.floating {
            var frames: [WindowID: CGRect] = [:]
            for (other, window) in windows where window.workspace == workspace.name && !window.minimized {
                frames[other] = currentFrame(of: other)
            }
            // A floating window covers the windows beside it, so their centres decide the direction.
            next = nearestWindowByCenter(from: id, direction, in: frames, wrap: wrap)
        } else {
            next = workspace.engine.neighbor(of: id, direction, wrap: wrap, in: layoutContext(forWorkspace: workspace.name))
        }
        if let next {
            focus(next)
        } else if let monitor = adjacentMonitor(direction) {
            focusMonitor(monitor.id)
        }
    }

    /// `swap <direction>`: the window and the tiled window that `focus <direction>` would reach exchange slots. The focus
    /// stays on the window. At the edge nothing happens (`move` is the command that crosses to the next monitor).
    private func swapDirection(_ direction: Direction, target id: WindowID?) -> ServerAnswer {
        guard let id, let managed = windows[id] else { return fail("there is no focused window") }
        guard !managed.floating else { return fail("cannot swap a floating window", 1, hint: "tile it first with `wm window float`") }
        let workspace = workspace(managed.workspace)
        let wrap = settings.wrapFocus
        guard let other = workspace.engine.neighbor(of: id, direction, wrap: wrap, in: layoutContext(forWorkspace: workspace.name)),
              swapWindows(id, other) else { return ok() }
        workspace.fullscreen = nil
        relayout()
        return ok()
    }

    private func moveDirection(_ direction: Direction, target id: WindowID?) -> ServerAnswer {
        guard let id, let managed = windows[id] else { return fail("there is no focused window") }
        guard !managed.floating else { return fail("cannot move a floating window", 1, hint: "tile it first with `wm window float`") }
        let workspace = workspace(managed.workspace)
        if workspace.engine.perform(.move(direction), focused: id, in: layoutContext(forWorkspace: workspace.name)) {
            relayout()
        } else if let monitor = adjacentMonitor(direction) {
            moveWindow(id, to: monitor.workspace)
            arrive(id)
            focusMonitor(monitor.id)
            focus(id)
        }
        return ok()
    }

    private var monitorFrames: [MonitorFrame] { monitors.map { MonitorFrame(id: $0.id, frame: $0.frame) } }

    private func adjacentMonitor(_ direction: Direction) -> Monitor? {
        MonitorGeometry.adjacent(to: focusedMonitorID, direction, in: monitorFrames)
            .flatMap { id in monitors.first { $0.id == id } }
    }

    private func monitorArgument(_ text: String?) -> Monitor? {
        guard let text else { return nil }
        if let direction = Direction(rawValue: text) { return adjacentMonitor(direction) }
        let step = text == "next" ? 1 : text == "prev" ? -1 : 0
        guard step != 0 else { return nil }
        return MonitorGeometry.cycle(from: focusedMonitorID, step: step, in: monitorFrames)
            .flatMap { id in monitors.first { $0.id == id } }
    }

    // MARK: - Layout

    private func layoutCommand(_ command: LayoutCommand, target id: WindowID?) -> ServerAnswer {
        guard let id, let managed = windows[id], !managed.floating else { return fail("there is no tiled window in focus") }
        let workspace = workspace(managed.workspace)
        _ = workspace.engine.perform(command, focused: id, in: layoutContext(forWorkspace: workspace.name))
        relayout()
        return ok()
    }

    /// `layout tile <2|3|2+1|1+2|4|5|6|2/3|3/4|1/4>`. Scrolling: the focused window and the windows after it fill one screen in
    /// that pattern; the same pattern again, or `tile chain`, goes back to single columns. Tiling: all windows of the
    /// workspace take the pattern (their number must match); `layout tile chain` goes back to the automatic layout.
    private func tile(_ name: String?, target id: WindowID?) -> ServerAnswer {
        guard let name else { return fail("layout tile needs a pattern", 2, usage: "layout tile") }
        guard let id, let managed = windows[id], !managed.floating else { return fail("there is no tiled window in focus") }
        let workspace = workspace(managed.workspace)
        if name == "chain" {
            _ = workspace.engine.perform(.releaseTemplate, focused: id, in: layoutContext(forWorkspace: workspace.name))
        } else {
            guard let template = SplitTemplate(rawValue: name) else { return fail("unknown pattern '\(name)'", 2, usage: "layout tile") }
            if let error = workspace.engine.templateError(template, focused: id) { return fail(error) }
            _ = workspace.engine.perform(.applyTemplate(template), focused: id, in: layoutContext(forWorkspace: workspace.name))
        }
        relayout()
        return ok()
    }

    /// The template of the window's block, for the picker's first selection.
    func template(of id: WindowID?) -> SplitTemplate? {
        guard let id, let managed = windows[id] else { return nil }
        return (workspace(managed.workspace).engine as? ScrollingEngine)?.template(of: id)
    }

    /// `window maximize`: the window fills the work area inside the outer gaps. Again to restore. In the scrolling layout
    /// the window keeps its place in the strip and only grows, so the strip scrolls it like any column. In the other
    /// layouts (and for a tile block) it floats above the others, which stay tiled behind it. Every window keeps its own
    /// state when focus moves on.
    private func toggleMaximize(target id: WindowID?) -> ServerAnswer {
        guard let id, let managed = windows[id] else { return fail("there is no focused window") }
        guard !managed.floating, !managed.minimized else { return fail("only a tiled window can be maximized", 1, hint: "tile it first with `wm window float`") }
        let workspace = workspace(managed.workspace)
        if workspace.maximized.contains(id) {
            workspace.maximized.remove(id)
            relayout()
            return ok()
        }
        workspace.fullscreen = nil
        if workspace.engine is ScrollingEngine,
           workspace.engine.perform(.maximize, focused: id, in: layoutContext(forWorkspace: workspace.name)) {
            focus(id)
            return ok()
        }
        workspace.maximized.insert(id)
        focus(id)
        return ok()
    }

    /// Maximized by either way: the overlay, or a scrolling column that fills its zone.
    func isMaximized(_ id: WindowID) -> Bool {
        guard let managed = windows[id] else { return false }
        let workspace = workspace(managed.workspace)
        return workspace.maximized.contains(id) || (workspace.engine as? ScrollingEngine)?.isMaximized(id) == true
    }

    /// Every window of the focused workspace moves one slot around the layout. A fullscreen window would hide the
    /// result, so fullscreen ends first.
    private func rotate(clockwise: Bool) -> ServerAnswer {
        guard let workspace = focusedWorkspace else { return fail("there is no workspace") }
        workspace.fullscreen = nil
        let tiledFocus = focused.flatMap { id in windows[id].flatMap { $0.workspace == workspace.name && !$0.floating ? id : nil } }
        _ = workspace.engine.perform(.rotate(clockwise: clockwise), focused: tiledFocus, in: layoutContext(forWorkspace: workspace.name))
        relayout()
        return ok()
    }

    /// `layout flip`: every split of the tiling layout switches between side by side and stacked.
    private func rotateLayout() -> ServerAnswer {
        guard let workspace = focusedWorkspace else { return fail("there is no workspace") }
        guard workspace.kind == .tiling else { return fail("layout flip needs the tiling layout", 1, hint: "switch with `wm layout set tiling`") }
        workspace.fullscreen = nil
        let tiledFocus = focused.flatMap { id in windows[id].flatMap { $0.workspace == workspace.name && !$0.floating ? id : nil } }
        _ = workspace.engine.perform(.rotateLayout, focused: tiledFocus, in: layoutContext(forWorkspace: workspace.name))
        relayout()
        return ok()
    }

    private func setLayout(_ name: String?) -> ServerAnswer {
        guard let kind = name.flatMap(LayoutKind.init(rawValue:)), let workspace = focusedWorkspace else {
            return fail("layout set needs scrolling or tiling", 2, usage: "layout set")
        }
        workspace.maximized = []
        rebuild(workspace, as: kind)
        relayout()
        return ok()
    }

    private func moveMouse(_ where: String?, target id: WindowID?) -> ServerAnswer {
        let point: CGPoint?
        switch `where` {
        case "window":
            point = id.flatMap(currentFrame(of:)).map { CGPoint(x: $0.midX, y: $0.midY) }
        case "monitor":
            point = focusedMonitor.map { CGPoint(x: $0.workArea.midX, y: $0.workArea.midY) }
        default:
            return fail("pointer needs window or monitor", 2, usage: "pointer")
        }
        guard let point else { return fail("there is nothing to move the pointer to") }
        CGWarpMouseCursorPosition(point)
        return ok()
    }

    // MARK: - Queries

    /// `list [windows|workspaces|monitors] [--focused] [--json]`: tables for people, JSON for scripts.
    func listCommand(_ words: [String], _ flags: Set<String>, target: WindowID?) -> ServerAnswer {
        if let bad = unknownOption(flags, allowed: ["--json", "--focused"], usage: "list") { return bad }
        let json = flags.contains("--json")
        guard let kind = words.first else {
            if flags.contains("--focused") { return fail("--focused applies to `wm list windows`", 2, usage: "list") }
            if let target { return ok(json ? (windowValue(target)?.json ?? "null") + "\n" : overviewText(only: target)) }
            return ok(json ? overviewValue().json + "\n" : overviewText())
        }
        guard ["windows", "workspaces", "monitors"].contains(kind) else {
            return fail("unknown list '\(kind)'", 2, usage: "list", hint: kind == "focused" ? "use `wm list windows --focused`" : "choose windows, workspaces, monitors or binds")
        }
        if flags.contains("--focused"), kind != "windows" { return fail("--focused applies to `wm list windows`", 2, usage: "list") }
        if kind == "windows" {
            let ids = target.map { [$0] } ?? (flags.contains("--focused") ? focused.map { [$0] } ?? [] : windows.keys.sorted())
            if json { return ok(LuaValue.array(ids.compactMap { windowValue($0) }).json + "\n") }
            return ok(renderTable(["", "id", "app", "title", "workspace", "state"], ids.compactMap { id in
                guard let managed = windows[id] else { return nil }
                var state: [String] = []
                if managed.floating { state.append("floating") }
                if isMaximized(id) { state.append("maximized") }
                if managed.minimized { state.append("minimized") }
                if (workspace(managed.workspace).engine as? ScrollingEngine)?.strip(of: id) == .vertical { state.append("vertical strip") }
                if workspace(managed.workspace).pseudo[id] != nil { state.append("pseudo") }
                return [id == focused ? "*" : "", String(id), managed.info.appName, truncated(managed.info.title, to: 48), managed.workspace, state.joined(separator: ", ")]
            }))
        }
        if json { return ok((query(kind) ?? .nil).json + "\n") }
        if kind == "monitors" {
            return ok(renderTable(["", "id", "name", "workspace", "size"], monitors.map { monitor in
                [monitor.id == focusedMonitorID ? "*" : "", String(monitor.id), monitor.name,
                 specials[monitor.id].map { "\(monitor.workspace) (special: \($0))" } ?? monitor.workspace,
                 "\(Int(monitor.frame.width))x\(Int(monitor.frame.height))"]
            }))
        }
        let names = workspaces.keys.sorted { $0.compare($1, options: .numeric) == .orderedAscending }
        return ok(renderTable(["", "workspace", "layout", "monitor", "windows"], names.compactMap { name in
            let count = windows.values.filter { $0.workspace == name }.count
            guard isVisible(name) || count > 0 else { return nil }
            return [name == focusedWorkspace?.name ? "*" : "", name, workspaces[name]!.kind.rawValue, monitor(showing: name).map { String($0.id) } ?? "-", String(count)]
        }))
    }

    func query(_ kind: String) -> LuaValue? {
        switch kind {
        case "windows":
            return .array(windows.keys.sorted().compactMap { windowValue($0) })
        case "focused":
            return focused.flatMap { windowValue($0) } ?? .nil
        case "workspaces":
            return .array(workspaces.keys.sorted().map { name in
                let workspace = workspaces[name]!
                var strips: [String: LuaValue] = [:]
                if let scrolling = workspace.engine as? ScrollingEngine {
                    for orientation in [Orientation.horizontal, .vertical] {
                        strips[orientation.rawValue] = .array(scrolling.windows.filter { scrolling.strip(of: $0) == orientation }.map { .number(Double($0)) })
                    }
                }
                return .table([
                    "strips": .table(strips),
                    "name": .string(name),
                    "layout": .string(workspace.kind.rawValue),
                    "visible": .bool(isVisible(name)),
                    "windows": .array(workspace.engine.windows.map { .number(Double($0)) }),
                ])
            })
        case "monitors":
            return .array(monitors.map { monitor in
                .table([
                    "id": .number(Double(monitor.id)),
                    "name": .string(monitor.name),
                    "workspace": .string(monitor.workspace),
                    "special": specials[monitor.id].map { .string($0) } ?? .nil,
                    "focused": .bool(monitor.id == focusedMonitorID),
                    "frame": rectValue(monitor.frame),
                    "work_area": rectValue(monitor.workArea),
                ])
            })
        default:
            return nil
        }
    }

    /// `{monitors, workspaces, windows}` in one document.
    private func overviewValue() -> LuaValue {
        .table([
            "monitors": query("monitors") ?? .array([]),
            "workspaces": query("workspaces") ?? .array([]),
            "windows": query("windows") ?? .array([]),
        ])
    }

    /// The workspaces that are shown or hold windows, with their windows, in the text format of `wm list`.
    private func overviewText(only target: WindowID? = nil) -> String {
        let monitorList = target == nil ? monitors.map { OverviewMonitor(id: $0.id, name: $0.name, workspace: $0.workspace) } : []
        let names = workspaces.keys.sorted { $0.compare($1, options: .numeric) == .orderedAscending }
        let used: [OverviewWorkspace] = names.compactMap { name in
            let workspace = workspaces[name]!
            let members = windows.filter { $0.value.workspace == name && (target == nil || $0.key == target) }.keys.sorted()
            guard target == nil ? (isVisible(name) || !members.isEmpty) : !members.isEmpty else { return nil }
            let scrolling = workspace.engine as? ScrollingEngine
            return OverviewWorkspace(
                name: name,
                layout: workspace.kind.rawValue,
                monitor: monitor(showing: name)?.id,
                windows: members.map { id in
                    let managed = windows[id]!
                    return OverviewWindow(
                        id: id, app: managed.info.appName, title: managed.info.title,
                        focused: id == focused, floating: managed.floating,
                        maximized: isMaximized(id), minimized: managed.minimized,
                        strip: scrolling?.strip(of: id) == .vertical ? "vertical" : nil
                    )
                }
            )
        }
        return renderOverview(monitors: monitorList, workspaces: used)
    }

    private func windowValue(_ id: WindowID) -> LuaValue? {
        guard let managed = windows[id] else { return nil }
        var strip: LuaValue = .nil
        if let scrolling = workspace(managed.workspace).engine as? ScrollingEngine, let which = scrolling.strip(of: id) {
            strip = .string(which.rawValue)
        }
        return .table([
            "id": .number(Double(id)),
            "strip": strip,
            "app": .string(managed.info.bundleID),
            "app_name": .string(managed.info.appName),
            "title": .string(managed.info.title),
            "workspace": .string(managed.workspace),
            "floating": .bool(managed.floating),
            "maximized": .bool(isMaximized(id)),
            "focused": .bool(id == focused),
            "frame": rectValue(currentFrame(of: id) ?? managed.info.frame),
        ])
    }

    private func rectValue(_ rect: CGRect) -> LuaValue {
        .table(["x": .number(rect.minX), "y": .number(rect.minY), "width": .number(rect.width), "height": .number(rect.height)])
    }
}

extension LuaValue {
    /// Compact JSON for `wm list --json`.
    var json: String {
        switch self {
        case .nil: "null"
        case let .bool(value): value ? "true" : "false"
        case let .number(value): value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(value)
        case let .string(value): Self.quote(value)
        case let .array(values): "[" + values.map(\.json).joined(separator: ",") + "]"
        case let .table(values): "{" + values.keys.sorted().map { Self.quote($0) + ":" + values[$0]!.json }.joined(separator: ",") + "}"
        }
    }

    private static func quote(_ text: String) -> String {
        guard let data = try? JSONEncoder().encode(text), let result = String(data: data, encoding: .utf8) else { return "\"\"" }
        return result
    }
}
