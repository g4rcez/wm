import AppKit
import Common
import Core
import Platform
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
            if let bad = unknownOption(flags, allowed: ["--wrap"], usage: "move") { return bad }
            guard let direction = words.first.flatMap(Direction.init(rawValue:)) else { return fail("move needs a direction", 2, usage: "move") }
            let step = words.dropFirst().first.map { Double($0) }
            if step == .some(nil) || words.count > 2 { return fail("move takes a direction and an optional number of points", 2, usage: "move") }
            return moveDirection(direction, target: id, step: CGFloat(step.flatMap { $0 } ?? 40), wrap: flags.contains("--wrap") || settings.wrapFocus)
        case "swap":
            if let bad = unknownOption(flags, allowed: ["--wrap"], usage: "swap") { return bad }
            guard let direction = words.first.flatMap(Direction.init(rawValue:)) else { return fail("swap needs a direction", 2, usage: "swap") }
            return swapDirection(direction, target: id, wrap: flags.contains("--wrap") || settings.wrapFocus)
        case "resize":
            if let bad = unknownOption(flags, allowed: [], usage: "resize") { return bad }
            if words == ["maximize"] { return fail("resize maximize is now window maximize", 2, usage: "window maximize") }
            if words.first == "dir" {
                guard words.count == 3, let direction = Direction(rawValue: words[1]), let points = Double(words[2]), points > 0 else {
                    return fail("resize dir needs a direction and a positive amount", 2, usage: "resize")
                }
                return resizeDirection(id, direction, CGFloat(points))
            }
            if words.count == 2, let side = Direction(rawValue: words[0]), let delta = Double(words[1]) {
                return resizeSide(id, side, CGFloat(delta))
            }
            guard words.count == 2, let dimension = ResizeDimension(rawValue: words[0]), let delta = Double(words[1]) else {
                return fail("resize needs a dimension or a side, and an amount", 2, usage: "resize")
            }
            if let id, let managed = windows[id], managed.floating {
                return resizeFloating(id, dimension, CGFloat(delta))
            }
            return layoutCommand(.resize(dimension, CGFloat(delta)), target: id)
        case "workspace": return workspaceCommand(words, flags, target: target)
        case "window": return windowCommand(words, flags, id)
        case "layout": return layoutGroup(words, flags, id)
        case "list", "query": return listCommand(words, flags, target: target)
        case "memory": return memoryCommand(words, flags)
        case "menubar":
            if let bad = unknownOption(flags, allowed: [], usage: "menubar") { return bad }
            switch words.first {
            case "set":
                let text = words.dropFirst().joined(separator: " ")
                guard !text.isEmpty else { return fail("menubar set needs a text", 2, usage: "menubar set", hint: "`wm menubar reset` goes back to the automatic text") }
                setMenuLabel(text)
                return ok()
            case "reset":
                if words.count > 1 { return fail("menubar reset takes no arguments", 2, usage: "menubar reset") }
                setMenuLabel(nil)
                return ok()
            default:
                return fail("menubar needs set or reset", 2, usage: "menubar")
            }
        case "pointer":
            if let bad = unknownOption(flags, allowed: [], usage: "pointer") { return bad }
            return moveMouse(words.first, target: id)
        case "zen":
            if let bad = unknownOption(flags, allowed: [], usage: "zen") { return bad }
            switch words.first {
            case nil: _ = setZen(nil)
            case "on": _ = setZen(true)
            case "off": _ = setZen(false)
            default: return fail("zen takes on or off", 2, usage: "zen")
            }
            return ok()
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
        let isStep = first == "next" || first == "prev"
        if let bad = unknownOption(flags, allowed: isStep ? ["--wrap"] : first == "app" ? ["--launch"] : [], usage: first == "app" ? "focus app" : "focus") { return bad }
        switch first {
        case "app":
            // Run or raise: the app's window gets the focus (the next one when the focus is on the app already); an app
            // without a window starts with --launch.
            let name = words.dropFirst().joined(separator: " ")
            guard !name.isEmpty else { return fail("focus app needs the name of an app", 2, usage: "focus app") }
            let ofApp = windows.filter {
                !$0.value.minimized && ($0.value.info.bundleID.caseInsensitiveCompare(name) == .orderedSame
                    || $0.value.info.appName.caseInsensitiveCompare(name) == .orderedSame)
            }.map(\.key)
            if let id = windowToRaise(ofApp: ofApp, focused: focused, recent: recent) {
                focus(id)
                return ok()
            }
            guard flags.contains("--launch") else {
                return fail("no window of \(name)", 1, hint: "`wm focus app \(name) --launch` starts the app")
            }
            guard AppLauncher.launch(name) else { return fail("cannot find the app \(name)", 1, hint: "use its name as in /Applications, or its bundle id") }
            return ok()
        case "column", "stack":
            guard let index = words.dropFirst().first.flatMap(LaneIndex.init(parsing:)) else {
                return fail("focus \(first) needs first, last or a number", 2, usage: "focus \(first)")
            }
            return focusLane(index, inStack: first == "stack")
        case "mark":
            guard let name = words.dropFirst().first else { return fail("focus mark needs a name", 2, usage: "focus mark") }
            guard let marked = marks[name], windows[marked] != nil else { return fail("no window has the mark '\(name)'", 1, hint: "see `wm list windows`") }
            focus(marked)
            return ok()
        case "next", "prev":
            return focusStep(first == "next" ? 1 : -1, wrap: flags.contains("--wrap") || settings.wrapFocus)
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

    /// `window sticky`: the window shows on every workspace that its monitor shows. A tiled window floats first. Again to end it;
    /// the window then stays floating on the workspace that it is on.
    private func toggleSticky(_ id: WindowID) -> ServerAnswer {
        guard let managed = windows[id], !managed.isOutOfLayout else {
            return fail("this window is not in the layout (minimized or in native fullscreen)")
        }
        if !managed.sticky, !managed.floating { setFloating(id, true) }
        setSticky(id, !managed.sticky)
        relayout()
        return ok()
    }

    /// `window swipe <direction>`: what a swipe on the title bar does. A floating window snaps to a half (left, right) or fills the
    /// screen (up). A tiled window moves in its layout (left, right) or is maximized (up). Down minimizes either one.
    private func swipe(_ id: WindowID, _ direction: Direction) -> ServerAnswer {
        guard let managed = windows[id] else { return fail("there is no focused window") }
        switch direction {
        case .down: return windowCommand(["minimize"], [], id)
        case .up: return windowCommand([managed.floating ? "fullscreen" : "maximize"], [], id)
        case .left, .right:
            return managed.floating ? snap(id, direction == .left ? .left : .right) : moveDirection(direction, target: id, step: 40, wrap: false)
        }
    }

    /// `window snap <place>`: the window floats into that part of the work area (inside the outer gaps). The same place again goes
    /// on to the next size (half, a third, two thirds). A tiled window floats first.
    private func snap(_ id: WindowID, _ place: SnapPlace) -> ServerAnswer {
        guard let managed = windows[id], !managed.isOutOfLayout else {
            return fail("this window is not in the layout (minimized or in native fullscreen)")
        }
        let context = layoutContext(forWorkspace: managed.workspace)
        let area = context.gaps.outerArea(context.viewport)
        guard area.width > 0, area.height > 0 else { return fail("there is no monitor") }
        var step = 0
        if managed.floating {
            step = nextSnapStep(current: managed.floatFrame ?? currentFrame(of: id) ?? .zero, place: place, in: area)
        } else {
            setFloating(id, true)
        }
        setFloatFrame(id, snapFrame(place, step: step, in: area))
        relayout()
        return ok()
    }

    /// `focus column <n>`: the most recently focused window of that column (else its top window). `focus stack <n>`: that
    /// window of the focused column. Both need the scrolling layout.
    private func focusLane(_ index: LaneIndex, inStack: Bool) -> ServerAnswer {
        let name = inStack ? "focus stack" : "focus column"
        guard let workspace = focusedWorkspace, let engine = workspace.engine as? ScrollingEngine else {
            return fail("\(name) needs the scrolling layout", 1, hint: "switch with `wm layout set scrolling`")
        }
        let strip = focused.flatMap { engine.strip(of: $0) } ?? .horizontal
        let lanes = engine.lanes(of: strip)
        let target: WindowID?
        if inStack {
            guard let id = focused, let lane = lanes.first(where: { $0.contains(id) }) else { return fail("there is no focused window") }
            target = index.resolve(count: lane.count).map { lane[$0] }
        } else {
            let lane = index.resolve(count: lanes.count).map { lanes[$0] }
            target = lane.flatMap { lane in workspace.history.first(where: lane.contains) ?? lane.first }
        }
        guard let target else { return fail("there is no such \(inStack ? "window" : "column")") }
        focus(target)
        return ok()
    }

    /// `focus next` and `focus prev`: the tiled windows in layout order, then the floating ones by id.
    private func focusStep(_ step: Int, wrap: Bool) -> ServerAnswer {
        guard let workspace = focusedWorkspace else { return fail("there is no workspace") }
        let floating = windows.filter { $0.value.workspace == workspace.name && $0.value.floating && !$0.value.isOutOfLayout }.keys.sorted()
        let order = workspace.engine.windows.filter { windows[$0] != nil } + floating
        guard !order.isEmpty else { return fail("there is no window on this workspace") }
        guard let current = focused.flatMap({ order.firstIndex(of: $0) }) else {
            focus(order[0])
            return ok()
        }
        var next = current + step
        if !order.indices.contains(next) {
            guard wrap else { return fail("there is no \(step > 0 ? "next" : "previous") window", 1, hint: "use --wrap to go around") }
            next = (next + order.count) % order.count
        }
        focus(order[next])
        return ok()
    }

    /// `focus layer`: the focus goes to the most recent floating window of the workspace, or back to the most recent
    /// tiled one. Without a layer it switches from the one the focused window is in.
    private func focusLayer(floating wanted: Bool?) -> ServerAnswer {
        guard let workspace = focusedWorkspace else { return fail("there is no workspace") }
        let inFloating = focused.flatMap { windows[$0] }.map { $0.workspace == workspace.name && $0.floating } ?? false
        let floating = wanted ?? !inFloating
        func candidates(_ ids: [WindowID]) -> WindowID? {
            ids.first { id in windows[id].map { $0.workspace == workspace.name && $0.floating == floating && !$0.isOutOfLayout } ?? false }
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
        case "move":
            guard words.dropFirst().first == "monitor", let spec = words.dropFirst(2).first else {
                return fail("workspace move needs `monitor <monitor>`", 2, usage: "workspace move monitor")
            }
            guard let monitor = monitorArgument(spec) else { return fail("no such monitor", 1, usage: "workspace move monitor") }
            if let reason = moveWorkspace(to: monitor) { return fail(reason) }
            return ok()
        case "float-all":
            switch words.dropFirst().first {
            case nil, "on": return floatAll(true)
            case "off": return floatAll(false)
            case let name?:
                // A pattern: the windows float into the cells of that tile template, as `layout tile` would place them.
                guard let template = templates(of: nil).first(where: { $0.name == name }) ?? SplitTemplate.builtIn(named: name) else {
                    return fail("unknown pattern '\(name)'", 2, usage: "workspace float-all", hint: "on, off, or a pattern of `wm help layout tile`")
                }
                return floatAll(true, into: template)
            }
        case "special":
            guard let name = SpecialWorkspace.name(words.dropFirst().first) else { return fail("bad special workspace name", 2, usage: "workspace special") }
            toggleSpecial(name)
            return ok()
        default:
            // `wm workspace <name>`, or `wm --window <id> workspace` for the workspace of that window.
            if target != nil, !words.isEmpty { return fail("workspace takes a name or --window, not both", 2, usage: "workspace") }
            guard let name = words.first ?? target.flatMap({ windows[$0]?.workspace }) else { return fail("workspace needs a name", 2, usage: "workspace") }
            var resolved = name == "back" ? (previousWorkspace ?? name) : resolveWorkspaceName(name)
            // With `workspace_back_and_forth`, asking for the workspace that is shown goes back to the previous one.
            if settings.workspaceBackAndForth, target == nil, name != "back", resolved == focusedMonitor?.workspace,
               let previousWorkspace {
                resolved = previousWorkspace
            }
            if SpecialWorkspace.isSpecial(resolved) {
                // `wm --window <id> workspace` for a window of a special workspace shows it; a name does not.
                guard let target else { return fail("special workspaces are shown with `wm workspace special <name>`") }
                focus(target)
                return ok()
            }
            showWorkspace(resolved, on: focusedMonitorID)
            if let target { focus(target) }
            return ok()
        }
    }

    private func windowCommand(_ words: [String], _ flags: Set<String>, _ id: WindowID?) -> ServerAnswer {
        guard let sub = words.first else { return fail("window needs a command", 2, usage: "window") }
        if sub == "send" { return sendCommand(Array(words.dropFirst()), flags, id) }
        if let bad = unknownOption(flags, allowed: sub == "remember" || sub == "forget" ? ["--title"] : [], usage: "window " + sub) { return bad }
        guard let id, let managed = windows[id] else {
            guard id != nil else { return fail("there is no focused window") }
            return fail(
                "the focused window is not managed by wm",
                hint: "wm skips windows that are not standard windows or dialogs, and windows in native fullscreen; `wm logs` says why a new window was skipped")
        }
        switch sub {
        case "sticky":
            return toggleSticky(id)
        case "snap":
            guard let place = words.dropFirst().first.flatMap(SnapPlace.init(rawValue:)) else {
                return fail("window snap needs a place", 2, usage: "window snap", hint: "one of " + SnapPlace.allCases.map(\.rawValue).joined(separator: ", "))
            }
            return snap(id, place)
        case "place": return place(id, Array(words.dropFirst()))
        case "move-to": return moveTo(id, Array(words.dropFirst()))
        case "remember":
            guard let entry = rememberWindow(id, withTitle: flags.contains("--title")) else {
                return fail("this window is not in the layout (minimized or in native fullscreen)")
            }
            return ok("remembered " + entry.summary + "\n")
        case "forget":
            guard forgetWindow(id, withTitle: flags.contains("--title")) else {
                return fail("nothing is remembered for this window", 1, hint: flags.contains("--title") ? "without --title, `wm window forget` removes the entry of the app" : "see `wm list memory`")
            }
            return ok("forgot \(managed.info.appName)\n")
        case "close":
            watcher(for: managed.info.pid)?.close(id)
            return ok()
        case "minimize":
            watcher(for: managed.info.pid)?.minimize(id)
            return ok()
        case "swipe":
            guard let direction = words.dropFirst().first.flatMap(Direction.init(rawValue:)) else {
                return fail("window swipe needs a direction", 2, usage: "window swipe", hint: "left, right, up or down")
            }
            return swipe(id, direction)
        case "float":
            let on: Bool
            switch words.dropFirst().first {
            case nil: on = !managed.floating
            case "on": on = true
            case "off": on = false
            default: return fail("window float takes on or off", 2, usage: "window float")
            }
            setFloating(id, on)
            relayout()
            return ok()
        case "center":
            guard !managed.isOutOfLayout, let area = floatArea(of: managed) else {
                return fail("this window is not in the layout (minimized or in native fullscreen)")
            }
            setFloating(id, true)
            guard let frame = windows[id]?.floatFrame ?? currentFrame(of: id) else { return fail("this window has no frame") }
            setFloatFrame(id, FloatGeometry.centered(frame, in: area))
            relayout()
            return ok()
        case "fullscreen":
            let workspace = workspace(managed.workspace)
            workspace.fullscreen = workspace.fullscreen == id ? nil : id
            if workspace.fullscreen != nil { workspace.maximized = [] }
            events.emit("window_fullscreen", ["id": .number(Double(id)), "fullscreen": .bool(workspace.fullscreen == id), "native": .bool(false)])
            relayout()
            return ok()
        case "maximize":
            return toggleMaximize(target: id)
        case "mark":
            guard let name = words.dropFirst().first else { return fail("window mark needs a name", 2, usage: "window mark") }
            setMark(name, on: id)
            return ok()
        case "unmark":
            removeMarks(named: words.dropFirst().first, of: id)
            return ok()
        case "raise-floating": return raiseFloating()
        case "rescue": return rescueFloating()
        case "native-fullscreen":
            guard let watcher = watcher(for: managed.info.pid) else { return fail("cannot reach the app of this window") }
            watcher.setFullscreen(id, !managed.nativeFullscreen)
            // The app reports the change a moment later.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                scheduleRefresh()
            }
            return ok()
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
        let stay = flags.contains("--stay"), tile = flags.contains("--tile"), wholeColumn = flags.contains("--column")
        switch kind {
        case "workspace":
            if let bad = unknownOption(flags, allowed: ["--stay", "--tile", "--column"], usage: usage) { return bad }
            guard let given = value else { return fail("window send workspace needs a workspace name", 2, usage: usage) }
            let name = resolveWorkspaceName(given)
            guard let id else { return fail("there is no focused window") }
            if SpecialWorkspace.isSpecial(name), SpecialWorkspace.name(name) == nil { return fail("bad special workspace name", 2, usage: usage) }
            let source = windows[id]?.workspace
            if wholeColumn {
                moveColumn(of: id, to: name)
            } else {
                moveWindow(id, to: name)
                arrive(id, tile: tile)
            }
            if stay {
                if let source, let next = workspace(source).history.first(where: { windows[$0] != nil }) { focus(next) } else { relayout() }
            } else {
                // The focus of the window shows a special workspace by itself.
                if !SpecialWorkspace.isSpecial(name) { showWorkspace(name, on: focusedMonitorID, focusWindow: false) }
                focus(id)
            }
            return ok()
        case "monitor":
            if let bad = unknownOption(flags, allowed: ["--tile", "--column"], usage: usage) { return bad }
            guard let id else { return fail("there is no focused window") }
            guard let monitor = monitorArgument(value) else { return fail("no such monitor", 1, usage: usage) }
            if wholeColumn {
                moveColumn(of: id, to: monitor.workspace)
            } else {
                moveWindow(id, to: monitor.workspace)
                arrive(id, tile: tile)
            }
            focusMonitor(monitor.id)
            focus(id)
            return ok()
        case "strip":
            if let bad = unknownOption(flags, allowed: [], usage: usage) { return bad }
            guard let orientation = value.flatMap(Orientation.init(rawValue:)) else { return fail("window send strip needs horizontal or vertical", 2, usage: usage) }
            return layoutCommand(.sendToStrip(orientation), target: id)
        default:
            return fail("unknown destination '\(kind)'", 2, usage: "window send")
        }
    }

    /// `workspace float-all [on|off|pattern]`: every window of the workspace that the focused monitor shows floats (`off`: tiles again). The
    /// windows that are minimized or in native fullscreen are not in the layout and stay as they are.
    /// With a `template`, the windows take its cells in order (the tiled ones as the layout lists them, then the floating ones);
    /// the windows past the last cell float where they are.
    private func floatAll(_ on: Bool, into template: SplitTemplate? = nil) -> ServerAnswer {
        guard let workspace = focusedWorkspace else { return fail("there is no workspace") }
        let inLayout = Set(windows.filter { $0.value.workspace == workspace.name && !$0.value.isOutOfLayout }.keys)
        guard !inLayout.isEmpty else { return fail("there is no window on this workspace") }
        // The order has to be read before the windows float: a floating window leaves the engine.
        let tiled = workspace.engine.windows.filter(inLayout.contains)
        let ordered = tiled + inLayout.subtracting(tiled).sorted()
        for id in ordered { setFloating(id, on) }
        if let template {
            for (index, id) in ordered.prefix(template.count).enumerated() {
                guard let frame = cellFrame(template, index, workspace: workspace.name) else { return fail("there is no monitor") }
                setFloatFrame(id, frame)
            }
        }
        relayout()
        return ok()
    }

    /// Where cell `index` of a tile template sits on the screen of the workspace: inside the outer gaps, with half the inner gap
    /// on each side. `nil` when there is no monitor.
    private func cellFrame(_ template: SplitTemplate, _ index: Int, workspace name: String) -> CGRect? {
        let context = layoutContext(forWorkspace: name)
        let area = context.gaps.outerArea(context.viewport)
        guard area.width > 0, area.height > 0, template.cells.indices.contains(index) else { return nil }
        let region = CGRect(
            x: area.minX + template.area.minX * area.width, y: area.minY + template.area.minY * area.height,
            width: template.area.width * area.width, height: template.area.height * area.height)
        let cell = template.cells[index]
        return CGRect(
            x: region.minX + cell.minX * region.width, y: region.minY + cell.minY * region.height,
            width: cell.width * region.width, height: cell.height * region.height
        ).insetBy(dx: context.gaps.inner / 2, dy: context.gaps.inner / 2)
    }

    /// `window place <pattern> <n>`: the window floats into cell n (from 1) of a tile pattern. The other windows stay as they are.
    private func place(_ id: WindowID, _ words: [String]) -> ServerAnswer {
        guard let managed = windows[id], !managed.isOutOfLayout else {
            return fail("this window is not in the layout (minimized or in native fullscreen)")
        }
        guard words.count == 2 else { return fail("window place needs a pattern and a cell number", 2, usage: "window place") }
        guard let template = templates(of: id).first(where: { $0.name == words[0] }) ?? SplitTemplate.builtIn(named: words[0]) else {
            return fail("unknown pattern '\(words[0])'", 2, usage: "window place", hint: "see `wm help layout tile`")
        }
        guard let number = Int(words[1]), (1...template.count).contains(number) else {
            return fail("the pattern '\(template.name)' has \(template.count) cell(s): give a number from 1 to \(template.count)", 2, usage: "window place")
        }
        guard let frame = cellFrame(template, number - 1, workspace: managed.workspace) else { return fail("there is no monitor") }
        setFloating(id, true)
        setFloatFrame(id, frame)
        relayout()
        return ok()
    }

    /// `window move-to <x> <y>`: the top left corner of the floating window goes to that point of the work area (`50%` is a fraction
    /// of its width or height). The size stays and the window stays inside the area. A tiled window floats first.
    private func moveTo(_ id: WindowID, _ words: [String]) -> ServerAnswer {
        guard let managed = windows[id], !managed.isOutOfLayout, let area = floatArea(of: managed) else {
            return fail("this window is not in the layout (minimized or in native fullscreen)")
        }
        func coordinate(_ text: String, of length: CGFloat) -> CGFloat? {
            if text.hasSuffix("%") { return Double(text.dropLast()).map { CGFloat($0) / 100 * length } }
            return Double(text).map { CGFloat($0) }
        }
        guard words.count == 2, let x = coordinate(words[0], of: area.width), let y = coordinate(words[1], of: area.height) else {
            return fail("window move-to needs x and y", 2, usage: "window move-to", hint: "points from the top left of the work area, or a percent such as 50%")
        }
        setFloating(id, true)
        guard let frame = windows[id]?.floatFrame ?? currentFrame(of: id) else { return fail("this window has no frame") }
        setFloatFrame(id, FloatGeometry.placed(frame, at: CGPoint(x: area.minX + x, y: area.minY + y), in: area))
        relayout()
        return ok()
    }

    /// `window raise-floating`: every floating window of the shown workspace comes to the front, the most recent last.
    private func raiseFloating() -> ServerAnswer {
        guard let workspace = focusedWorkspace else { return fail("there is no workspace") }
        let floating = windows.filter { $0.value.workspace == workspace.name && $0.value.floating && !$0.value.isOutOfLayout }.keys
        guard !floating.isEmpty else { return fail("there is no floating window on this workspace") }
        let recent = workspace.history
        // The least recently used window first, so the most recent one ends on top.
        let ordered = floating.sorted { (recent.firstIndex(of: $0) ?? Int.max, $0) > (recent.firstIndex(of: $1) ?? Int.max, $1) }
        for id in ordered.dropLast() { windows[id].flatMap { watcher(for: $0.info.pid) }?.raise(id) }
        if let top = ordered.last { focus(top) }
        return ok()
    }

    /// `window rescue`: a floating window that is mostly outside its monitor comes back inside the work area.
    private func rescueFloating() -> ServerAnswer {
        var moved = 0
        for (id, managed) in windows where managed.floating && !managed.isOutOfLayout {
            guard let monitor = monitor(showing: managed.workspace), let frame = currentFrame(of: id),
                  let better = MonitorGeometry.rescued(frame, in: monitor.workArea) else { continue }
            setFloatFrame(id, better)
            moved += 1
        }
        guard moved > 0 else { return ok() }
        relayout(snapAll: true)
        return ok()
    }

    /// `--column`: the whole column of the window goes to the workspace, keeps its stack, its width and its tabs, and joins
    /// the layout there like `--tile` (no maximize, no balance). Without the scrolling layout it is the window alone.
    private func moveColumn(of id: WindowID, to name: String) {
        guard let managed = windows[id] else { return }
        let source = workspace(managed.workspace)
        let engine = source.engine as? ScrollingEngine
        let strip = engine?.strip(of: id) ?? .horizontal
        let column = engine?.lanes(of: strip).first { $0.contains(id) } ?? [id]
        let width = engine?.columnSize(of: id)
        let tabbed = engine?.tabs(of: id) != nil
        guard let head = column.first else { return }

        var anchor: WindowID?
        for member in column {
            moveWindow(member, to: name, after: anchor)
            anchor = member
        }
        let destination = workspace(name)
        let context = layoutContext(forWorkspace: name)
        // Each window opened in a column of its own, beside the one before it; they stack into the first one.
        for member in column.dropFirst() { _ = destination.engine.perform(.stack(.left), focused: member, in: context) }
        guard destination.kind == .scrolling else { return }
        if let width { _ = destination.engine.perform(.columnWidth(.fraction(width)), focused: head, in: context) }
        let isTabbed = (destination.engine as? ScrollingEngine)?.tabs(of: head) != nil
        if column.count > 1, isTabbed != tabbed { _ = destination.engine.perform(.toggleTabs, focused: head, in: context) }
    }

    /// A layout command that only the tiling layout has.
    private func tilingCommand(_ command: LayoutCommand, _ id: WindowID?, _ name: String) -> ServerAnswer {
        guard focusedWorkspace?.kind == .tiling else {
            return fail("\(name) needs the tiling layout", 1, hint: "switch with `wm layout set tiling`")
        }
        return layoutCommand(command, target: id)
    }

    private func masterCommand(_ command: LayoutCommand, _ id: WindowID?, _ name: String) -> ServerAnswer {
        guard focusedWorkspace?.kind == .master else {
            return fail("\(name) needs the master layout", 1, hint: "switch with `wm layout set master`")
        }
        return layoutCommand(command, target: id)
    }

    /// `layout master <promote|count|ratio|orientation>`.
    private func masterGroup(_ words: [String], _ id: WindowID?) -> ServerAnswer {
        let amount = words.dropFirst(2).first
        let relative = amount.map { $0.hasPrefix("+") || $0.hasPrefix("-") } ?? false
        switch words.dropFirst().first {
        case "promote": return masterCommand(.promote, id, "layout master promote")
        case "count":
            guard let amount, let number = Int(amount) else {
                return fail("layout master count needs a number, or +n or -n", 2, usage: "layout master count")
            }
            return masterCommand(.masterCount(number, relative: relative), id, "layout master count")
        case "ratio":
            guard let amount, let number = Double(amount) else {
                return fail("layout master ratio needs a number, or +n or -n", 2, usage: "layout master ratio")
            }
            return masterCommand(.masterRatio(number, relative: relative), id, "layout master ratio")
        case "orientation":
            if amount == nil || amount == "next" { return masterCommand(.masterOrientation(nil), id, "layout master orientation") }
            guard let place = amount.flatMap(MasterOrientation.init(rawValue:)) else {
                return fail("layout master orientation takes left, right, top, bottom, center or next", 2, usage: "layout master orientation")
            }
            return masterCommand(.masterOrientation(place), id, "layout master orientation")
        default:
            return fail("layout master takes promote, count, ratio or orientation", 2, usage: "layout master")
        }
    }

    private func layoutGroup(_ words: [String], _ flags: Set<String>, _ id: WindowID?) -> ServerAnswer {
        if let bad = unknownOption(flags, allowed: [], usage: "layout") { return bad }
        guard let sub = words.first else { return fail("layout needs a command", 2, usage: "layout") }
        let value = words.dropFirst().first
        switch sub {
        case "set": return setLayout(value)
        case "balance": return layoutCommand(.balance, target: id)
        case "master": return masterGroup(words, id)
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
            case "expand": return layoutCommand(.expandColumn, target: id)
            case "center": return layoutCommand(.center, target: id)
            case "center-visible": return layoutCommand(.centerVisible, target: id)
            case "move":
                guard let index = words.dropFirst(2).first.flatMap(LaneIndex.init(parsing:)) else {
                    return fail("layout column move needs first, last or a number", 2, usage: "layout column move")
                }
                return layoutCommand(.moveColumn(index), target: id)
            default: return fail("unknown column command", 2, usage: "layout column")
            }
        case "stack":
            switch value {
            case "join", "leave":
                // The window joins the column on its left, or leaves to a column on its right, unless a side is given.
                let side = words.dropFirst(2).first
                guard side == nil || Direction(rawValue: side!) != nil else {
                    return fail("layout stack \(value!) takes left or right", 2, usage: "layout stack")
                }
                let direction = side.flatMap(Direction.init(rawValue:)) ?? (value == "join" ? .left : .right)
                return layoutCommand(value == "join" ? .stack(direction) : .unstack(direction), target: id)
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
            for (other, window) in windows where window.workspace == workspace.name && !window.isOutOfLayout {
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
    /// stays on the window. At the edge nothing happens (`move` is the command that crosses to the next monitor), unless `wrap`
    /// goes around: then the window trades places with the one at the other end.
    private func swapDirection(_ direction: Direction, target id: WindowID?, wrap: Bool) -> ServerAnswer {
        guard let id, let managed = windows[id] else { return fail("there is no focused window") }
        guard !managed.floating else { return fail("cannot swap a floating window", 1, hint: "tile it first with `wm window float`") }
        let workspace = workspace(managed.workspace)
        guard let other = workspace.engine.neighbor(of: id, direction, wrap: wrap, in: layoutContext(forWorkspace: workspace.name)),
              swapWindows(id, other) else { return ok() }
        workspace.fullscreen = nil
        relayout()
        return ok()
    }

    /// The work area of the monitor that shows the window's workspace: where a floating window may be put by keyboard.
    private func floatArea(of managed: ManagedWindow) -> CGRect? {
        (monitor(showing: managed.workspace) ?? focusedMonitor)?.workArea
    }

    /// A floating window: its frame, and the area that it must stay in.
    private func floatingFrame(_ id: WindowID) -> (frame: CGRect, area: CGRect)? {
        guard let managed = windows[id], managed.floating, !managed.isOutOfLayout, let area = floatArea(of: managed),
              let frame = managed.floatFrame ?? currentFrame(of: id) else { return nil }
        return (frame, area)
    }

    private func resizeFloating(_ id: WindowID, _ dimension: ResizeDimension, _ delta: CGFloat) -> ServerAnswer {
        guard let (frame, area) = floatingFrame(id) else { return fail("this window is not in the layout (minimized or in native fullscreen)") }
        setFloatFrame(id, FloatGeometry.resized(frame, dimension, by: delta, in: area))
        relayout()
        return ok()
    }

    /// `resize dir <left|right|up|down> <n>`: the nearest divider on that axis moves n points toward the direction, so a window on the
    /// far side grows and one on the near side shrinks. A floating window has no divider: right and down grow it, left and up shrink it
    /// (its top left corner stays).
    private func resizeDirection(_ id: WindowID?, _ direction: Direction, _ points: CGFloat) -> ServerAnswer {
        guard let id, let managed = windows[id] else { return fail("there is no focused window") }
        if managed.floating {
            guard let (frame, area) = floatingFrame(id) else { return fail("this window is not in the layout (minimized or in native fullscreen)") }
            let growing = direction == .right || direction == .down
            setFloatFrame(id, FloatGeometry.resized(frame, direction.isHorizontal ? .width : .height, by: growing ? points : -points, in: area))
            relayout()
            return ok()
        }
        let workspace = workspace(managed.workspace)
        guard workspace.engine.perform(.resizeDirection(direction, points), focused: id, in: layoutContext(forWorkspace: workspace.name)) else {
            return fail("no divider to move \(direction.rawValue)", 1, hint: "a single window, or a layout with no split on that axis, has none")
        }
        relayout()
        return ok()
    }

    /// `resize <left|right|up|down> <+n|-n>`: the edge of the window on that side moves outward by n points (a negative n moves it
    /// inward); the other edges stay. A tiled window moves the divider on that side, so it fails on the side of the screen's edge,
    /// where there is no divider. A floating window keeps its other edges and stays inside the work area.
    private func resizeSide(_ id: WindowID?, _ side: Direction, _ delta: CGFloat) -> ServerAnswer {
        guard let id, let managed = windows[id] else { return fail("there is no focused window") }
        if managed.floating {
            guard let (frame, area) = floatingFrame(id) else { return fail("this window is not in the layout (minimized or in native fullscreen)") }
            let moved = CGPoint(x: side == .left ? -delta : (side == .right ? delta : 0), y: side == .up ? -delta : (side == .down ? delta : 0))
            let resized = MonitorGeometry.resized(
                frame, edges: (side == .left ? .left : .right, side == .up ? .up : .down), by: moved, minimum: CGSize(width: 100, height: 60))
            setFloatFrame(id, resized.intersection(area).isNull ? frame : resized.intersection(area))
            relayout()
            return ok()
        }
        let workspace = workspace(managed.workspace)
        guard workspace.engine.perform(.resizeEdge(side, delta), focused: id, in: layoutContext(forWorkspace: workspace.name)) else {
            return fail("this window has no divider on its \(side.rawValue) side", 1, hint: "the side of a screen edge cannot move; try the opposite side")
        }
        relayout()
        return ok()
    }

    /// `move <direction>`. A tiled window moves in its layout; at the edge `wrap` sends it around to the other end (it trades places
    /// with the window that `focus <direction> --wrap` reaches), and without `wrap` it goes on to the next monitor.
    private func moveDirection(_ direction: Direction, target id: WindowID?, step: CGFloat, wrap: Bool) -> ServerAnswer {
        guard let id, let managed = windows[id] else { return fail("there is no focused window") }
        if managed.floating {
            guard let (frame, area) = floatingFrame(id) else { return fail("this window is not in the layout (minimized or in native fullscreen)") }
            setFloatFrame(id, FloatGeometry.moved(frame, direction, by: step, in: area))
            relayout()
            return ok()
        }
        let workspace = workspace(managed.workspace)
        if workspace.engine.perform(.move(direction), focused: id, in: layoutContext(forWorkspace: workspace.name)) {
            relayout()
        } else if wrap, let other = workspace.engine.neighbor(of: id, direction, wrap: true, in: layoutContext(forWorkspace: workspace.name)),
                  swapWindows(id, other) {
            workspace.fullscreen = nil
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
        if text == "last" { return previousMonitorID.flatMap { id in monitors.first { $0.id == id } } }
        let step = text == "next" ? 1 : text == "prev" ? -1 : 0
        // Not a movement: a role, a number or part of the name, as in a rule.
        guard step != 0 else { return monitor(matching: text) }
        return MonitorGeometry.cycle(from: focusedMonitorID, step: step, in: monitorFrames)
            .flatMap { id in monitors.first { $0.id == id } }
    }

    // MARK: - Layout

    private func layoutCommand(_ command: LayoutCommand, target id: WindowID?) -> ServerAnswer {
        if let id, windows[id]?.floating == true, let answer = floatingLayoutCommand(command, id) { return answer }
        guard let id, let managed = windows[id], !managed.floating else { return fail("there is no tiled window in focus", 1, hint: "this command has no meaning for a floating window") }
        let workspace = workspace(managed.workspace)
        _ = workspace.engine.perform(command, focused: id, in: layoutContext(forWorkspace: workspace.name))
        relayout()
        return ok()
    }

    /// `layout tile <2|3|2+1|1+2|4|5|6|2/3|3/4|1/4>`. Scrolling: the focused window and the windows after it fill one screen in
    /// that pattern; the same pattern again, or `tile chain`, goes back to single columns. Tiling: all windows of the
    /// workspace take the pattern (their number must match, except that a lone window takes the first cell); `layout tile chain` goes back to the automatic layout.
    private func tile(_ name: String?, target id: WindowID?) -> ServerAnswer {
        guard let name else { return fail("layout tile needs a pattern", 2, usage: "layout tile") }
        guard let id, let managed = windows[id], !managed.floating else { return fail("there is no tiled window in focus") }
        let workspace = workspace(managed.workspace)
        if name == "chain" {
            _ = workspace.engine.perform(.releaseTemplate, focused: id, in: layoutContext(forWorkspace: workspace.name))
        } else {
            // A name that the config left out of its list still works when it is a built-in one.
            guard let template = templates(of: id).first(where: { $0.name == name }) ?? SplitTemplate.builtIn(named: name) else {
                return fail("unknown pattern '\(name)'", 2, usage: "layout tile")
            }
            if let error = workspace.engine.templateError(template, focused: id) { return fail(error) }
            _ = workspace.engine.perform(.applyTemplate(template), focused: id, in: layoutContext(forWorkspace: workspace.name))
        }
        relayout()
        return ok()
    }

    /// The tile templates of the layout of the window's workspace (the focused workspace without a window), as the config lists them.
    func templates(of id: WindowID?) -> [SplitTemplate] {
        let kind = layoutKind(of: id)
        return settings.templates(for: kind) + (kind == .tiling ? customTemplates : [])
    }

    func layoutKind(of id: WindowID?) -> LayoutKind {
        id.flatMap { windows[$0] }.map { workspace($0.workspace).kind } ?? focusedWorkspace?.kind ?? settings.layout
    }

    /// Keeps a frame that the user drew, so `layout tile <name>` and the picker find it after a restart.
    func remember(frame: SplitTemplate) {
        customTemplates = CustomTemplates.adding(frame, to: customTemplates)
        do { try CustomTemplates.write(customTemplates, to: StateStore.templatesURL) } catch {
            Log.write(.warn, "cannot save \(StateStore.templatesURL.path): \(error)", source: "templates", prefix: "wmd")
        }
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
        guard !managed.isOutOfLayout else { return fail("this window is not in the layout (minimized or in native fullscreen)") }
        if managed.floating { return maximizeFloating(id, managed) }
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

    /// A floating window fills the work area inside the gaps; again, it goes back to the frame it had.
    private func maximizeFloating(_ id: WindowID, _ managed: ManagedWindow) -> ServerAnswer {
        let context = layoutContext(forWorkspace: managed.workspace)
        let area = context.gaps.outerArea(context.viewport)
        guard area.width > 0, area.height > 0 else { return fail("there is no monitor") }
        let frame = managed.floatFrame ?? currentFrame(of: id) ?? managed.info.frame
        let near: (CGFloat, CGFloat) -> Bool = { abs($0 - $1) <= 4 }
        let isMaximized = near(frame.minX, area.minX) && near(frame.minY, area.minY) && near(frame.width, area.width) && near(frame.height, area.height)
        if isMaximized, let restore = managed.floatRestore {
            setFloatRestore(id, nil)
            setFloatFrame(id, restore)
        } else {
            // A window that was moved after it was maximized has an old entry: the entry is the frame of now.
            setFloatRestore(id, isMaximized ? nil : frame)
            setFloatFrame(id, area)
        }
        relayout()
        focus(id)
        return ok()
    }

    /// The tiling and scrolling commands that have a meaning for a floating window do it for the window: the width and height
    /// fractions, `layout column expand` (the whole width) and the centering. `nil` for the others.
    private func floatingLayoutCommand(_ command: LayoutCommand, _ id: WindowID) -> ServerAnswer? {
        guard let (frame, area) = floatingFrame(id) else { return nil }
        func apply(_ new: CGRect) -> ServerAnswer {
            setFloatFrame(id, new)
            relayout()
            return ok()
        }
        func resize(_ dimension: ResizeDimension, _ spec: ColumnWidth) -> ServerAnswer {
            switch spec {
            case .cycle: apply(FloatGeometry.sized(frame, dimension, fraction: FloatGeometry.nextFraction(of: frame, dimension, in: area), in: area))
            case .fraction(let fraction): apply(FloatGeometry.sized(frame, dimension, fraction: fraction, in: area))
            }
        }
        switch command {
        case .columnWidth(let spec): return resize(.width, spec)
        case .windowHeight(let spec): return resize(.height, spec)
        case .expandColumn: return apply(FloatGeometry.sized(frame, .width, fraction: 1, in: area))
        case .center, .centerVisible: return apply(FloatGeometry.centered(frame, in: area))
        default: return nil
        }
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
            return fail("layout set needs scrolling, tiling, master, monocle or floating", 2, usage: "layout set")
        }
        workspace.maximized = []
        // Into `floating`: the windows float where they are. Out of it they stay floating, and only new windows tile.
        let tiled = kind == .floating && workspace.kind != .floating ? workspace.engine.windows : []
        let frames = tiled.isEmpty ? [:] : workspace.engine.frames(in: layoutContext(forWorkspace: workspace.name), focused: tiled.first)
        rebuild(workspace, as: kind)
        for id in tiled {
            setFloating(id, true)
            if let frame = frames[id] { setFloatFrame(id, frame) }
        }
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

    // MARK: - Memory

    /// `memory [list|forget|clear]`: the entries that `window remember` keeps, seen and removed without a window.
    private func memoryCommand(_ words: [String], _ flags: Set<String>) -> ServerAnswer {
        switch words.first ?? "list" {
        case "list":
            if let bad = unknownOption(flags, allowed: ["--json"], usage: "memory list") { return bad }
            if words.count > 1 { return fail("memory list takes no arguments", 2, usage: "memory list") }
            return listCommand(["memory"], flags, target: nil)
        case "forget":
            let titleFlag = flags.first { $0.hasPrefix("--title=") }
            if let bad = unknownOption(flags.filter { $0 != titleFlag }, allowed: ["--all"], usage: "memory forget") { return bad }
            let name = words.dropFirst().joined(separator: " ")
            guard !name.isEmpty else {
                return fail("memory forget needs the name or the bundle id of an app", 2, usage: "memory forget", hint: "see `wm memory list`")
            }
            let title = titleFlag.map { String($0.dropFirst("--title=".count)) }
            if title?.isEmpty == true { return fail("--title needs a title", 2, usage: "memory forget") }
            if title != nil, flags.contains("--all") { return fail("--title and --all cannot go together", 2, usage: "memory forget") }
            let removed = forgetMemory(appNamed: name, title: title, allTitles: flags.contains("--all"))
            guard let first = removed.first else {
                let known = memory.hasEntries(ofApp: name)
                return fail(
                    "nothing is remembered for \(name)" + (title.map { " with the title \($0.debugDescription)" } ?? ""), 1,
                    hint: known ? "that app has other entries: pick one with --title=<text>, or remove them all with --all" : "see `wm memory list`")
            }
            let what = removed.count == 1 ? (first.title.map { "the entry \($0.debugDescription) of" } ?? "the entry of") : "\(removed.count) entries of"
            return ok("forgot \(what) \(first.appName)\n")
        case "clear":
            if let bad = unknownOption(flags, allowed: [], usage: "memory clear") { return bad }
            if words.count > 1 { return fail("memory clear takes no arguments", 2, usage: "memory clear") }
            let count = clearMemory()
            guard count > 0 else { return ok("nothing is remembered\n") }
            return ok("forgot \(count) \(count == 1 ? "entry" : "entries")\n")
        case let other:
            return fail("unknown memory command '\(other)'", 2, usage: "memory")
        }
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
        guard ["windows", "workspaces", "monitors", "memory", "keyboards"].contains(kind) else {
            return fail("unknown list '\(kind)'", 2, usage: "list", hint: kind == "focused" ? "use `wm list windows --focused`" : "choose windows, workspaces, monitors, keyboards, memory or binds")
        }
        if kind == "keyboards" {
            if flags.contains("--focused") { return fail("--focused applies to `wm list windows` and `wm list monitors`", 2, usage: "list") }
            if json { return ok((query("keyboards") ?? .nil).json + "\n") }
            let keyboards = KeyboardDevices.list()
            guard !keyboards.isEmpty else { return ok("no keyboards found\n") }
            return ok(renderTable(["name", "id", "transport", "built-in", "state", "capslock"], keyboards.map { keyboard in
                [keyboard.name, keyboard.id, keyboard.transport, keyboard.isBuiltIn ? "yes" : "no",
                 settings.keyboards.isEnabled(keyboard) ? "enabled" : "disabled", keyboard.hyperMapped ? "hyper" : "normal"]
            }))
        }
        if flags.contains("--focused"), kind != "windows", kind != "monitors" {
            return fail("--focused applies to `wm list windows` and `wm list monitors`", 2, usage: "list")
        }
        if kind == "windows" {
            let ids = target.map { [$0] } ?? (flags.contains("--focused") ? focused.map { [$0] } ?? [] : windows.keys.sorted())
            if json { return ok(LuaValue.array(ids.compactMap { windowValue($0) }).json + "\n") }
            return ok(renderTable(["", "id", "app", "title", "workspace", "state"], ids.compactMap { id in
                guard let managed = windows[id] else { return nil }
                return [id == focused ? "*" : "", String(id), managed.info.appName, truncated(managed.info.title, to: 48), managed.workspace, stateLabels(of: id, managed).joined(separator: ", ")]
            }))
        }
        let onlyFocusedMonitor = kind == "monitors" && flags.contains("--focused")
        if json {
            // With --focused, `list monitors` is a list of the one focused monitor, like `list windows --focused`.
            return ok((onlyFocusedMonitor ? .array([query("monitor") ?? .nil].filter { $0 != .nil }) : query(kind) ?? .nil).json + "\n")
        }
        if kind == "monitors" {
            let mainIndex = monitors.firstIndex(where: \.isMain) ?? 0
            return ok(renderTable(["", "id", "name", "workspace", "size", "role"], monitors.enumerated().compactMap { offset, monitor in
                guard !onlyFocusedMonitor || monitor.id == focusedMonitorID else { return nil }
                return [monitor.id == focusedMonitorID ? "*" : "", String(monitor.id), monitor.name,
                        specials[monitor.id].map { "\(monitor.workspace) (special: \($0))" } ?? monitor.workspace,
                        "\(Int(monitor.frame.width))x\(Int(monitor.frame.height))",
                        MonitorSelector.roleName(index: offset, mainIndex: mainIndex) ?? "-"]
            }))
        }
        if kind == "memory" {
            return ok(renderTable(["app", "title", "workspace", "monitor", "mode", "frame"], memory.windows.map {
                [$0.appName, $0.title.map { truncated($0, to: 32) } ?? "-", $0.workspace, $0.monitor ?? "-", $0.mode, $0.frameText]
            }))
        }
        let names = workspaces.keys.sorted { $0.compare($1, options: .numeric) == .orderedAscending }
        return ok(renderTable(["", "workspace", "layout", "monitor", "windows"], names.compactMap { name in
            let count = windows.values.filter { $0.workspace == name }.count
            guard isVisible(name) || count > 0 else { return nil }
            return [name == focusedWorkspace?.name ? "*" : "", name, workspaces[name]!.kind.rawValue, monitor(showing: name).map { String($0.id) } ?? "-", String(count)]
        }))
    }

    /// One monitor as `wm list monitors --json` and `wm.query` show it. `index` counts from 1, from the left (the number that
    /// a monitor selector takes); `role` is `main`, `secondary` or `tertiary`.
    func monitorValue(at offset: Int) -> LuaValue {
        let monitor = monitors[offset]
        let mainIndex = monitors.firstIndex(where: \.isMain) ?? 0
        return .table([
            "id": .number(Double(monitor.id)),
            "name": .string(monitor.name),
            "index": .number(Double(offset + 1)),
            "role": MonitorSelector.roleName(index: offset, mainIndex: mainIndex).map { .string($0) } ?? .nil,
            "main": .bool(monitor.isMain),
            "workspace": .string(monitor.workspace),
            "special": specials[monitor.id].map { .string($0) } ?? .nil,
            "focused": .bool(monitor.id == focusedMonitorID),
            "frame": rectValue(monitor.frame),
            "work_area": rectValue(monitor.workArea),
        ])
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
            return .array(monitors.indices.map { monitorValue(at: $0) })
        case "memory":
            return .array(memory.windows.map { entry in
                var fields: [String: LuaValue] = [
                    "app": .string(entry.app), "name": .string(entry.appName), "workspace": .string(entry.workspace),
                    "mode": .string(entry.mode), "floating": .bool(entry.floating), "maximized": .bool(entry.maximized),
                    "marks": .array(entry.marks.map { .string($0) }),
                ]
                if let title = entry.title { fields["title"] = .string(title) }
                if let monitor = entry.monitor { fields["monitor"] = .string(monitor) }
                if let frame = entry.frame {
                    fields["frame"] = .table(["x": .number(frame.x), "y": .number(frame.y), "width": .number(frame.width), "height": .number(frame.height)])
                }
                if let width = entry.columnWidth { fields["column_width"] = .number(width) }
                if let strip = entry.strip { fields["strip"] = .string(strip.rawValue) }
                return .table(fields)
            })
        case "keyboards":
            return .array(KeyboardDevices.list().map { keyboard in
                var fields: [String: LuaValue] = [
                    "name": .string(keyboard.name), "id": .string(keyboard.id), "vendor_id": .number(Double(keyboard.vendorID)),
                    "product_id": .number(Double(keyboard.productID)), "location_id": .number(Double(keyboard.locationID)),
                    "transport": .string(keyboard.transport), "built_in": .bool(keyboard.isBuiltIn),
                    "enabled": .bool(settings.keyboards.isEnabled(keyboard)), "hyper": .bool(keyboard.hyperMapped),
                ]
                if let manufacturer = keyboard.manufacturer { fields["manufacturer"] = .string(manufacturer) }
                return .table(fields)
            })
        case "monitor":
            // The focused monitor, or nil when there is none.
            return monitors.firstIndex { $0.id == focusedMonitorID }.map { monitorValue(at: $0) } ?? .nil
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

    /// The words of the `state` column of `list windows`: `floating`, `sticky`, `mark:<name>`, ...
    private func stateLabels(of id: WindowID, _ managed: ManagedWindow) -> [String] {
        var state: [String] = []
        if managed.floating { state.append("floating") }
        if managed.sticky { state.append("sticky") }
        if isMaximized(id) { state.append("maximized") }
        if managed.minimized { state.append("minimized") }
        if managed.nativeFullscreen { state.append("fullscreen") }
        for name in marks(of: id) { state.append("mark:" + name) }
        if (workspace(managed.workspace).engine as? ScrollingEngine)?.strip(of: id) == .vertical { state.append("vertical strip") }
        if workspace(managed.workspace).pseudo[id] != nil { state.append("pseudo") }
        return state
    }

    /// What `wm pick` shows for a window: from wm's own state when it manages the window, else from what its app reports.
    func pickedWindow(_ id: WindowID, unmanaged: WindowInfo?) -> PickedWindow? {
        if let managed = windows[id] {
            let frame = currentFrame(of: id) ?? managed.info.frame
            return PickedWindow(
                id: id, pid: managed.info.pid, bundleID: managed.info.bundleID, appName: managed.info.appName, title: managed.info.title,
                role: managed.info.role, subrole: managed.info.subrole, frame: PickedFrame(frame), managed: true,
                workspace: managed.workspace, state: stateLabels(of: id, managed))
        }
        guard let info = unmanaged else { return nil }
        return PickedWindow(
            id: id, pid: info.pid, bundleID: info.bundleID, appName: info.appName, title: info.title, role: info.role,
            subrole: info.subrole, frame: PickedFrame(info.frame), managed: false, workspace: nil, state: [])
    }

    /// `wm pick --json`: the object of `list windows --json` for a managed window, with `pid`, `role`, `subrole` and `managed` added.
    func pickValue(_ picked: PickedWindow) -> LuaValue {
        var fields: [String: LuaValue]
        if case .table(let listed)? = windowValue(picked.id) {
            fields = listed
        } else {
            fields = [
                "id": .number(Double(picked.id)), "app": .string(picked.bundleID), "app_name": .string(picked.appName),
                "title": .string(picked.title),
                "frame": .table(["x": .number(picked.frame.x), "y": .number(picked.frame.y), "width": .number(picked.frame.width), "height": .number(picked.frame.height)]),
            ]
        }
        fields["pid"] = .number(Double(picked.pid))
        fields["role"] = .string(picked.role)
        fields["subrole"] = .string(picked.subrole)
        fields["managed"] = .bool(picked.managed)
        return .table(fields)
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
            "sticky": .bool(managed.sticky),
            "maximized": .bool(isMaximized(id)),
            "focused": .bool(id == focused),
            "marks": .array(marks(of: id).map { .string($0) }),
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
