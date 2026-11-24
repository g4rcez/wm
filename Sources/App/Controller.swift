import AppKit
import Cheatsheet
import Common
import Core
import Foundation
import Platform
import Scripting
import ServiceManagement

final class AppController: HostBridge, @unchecked Sendable {
    static let version = wmVersion

    let manager: WindowManager
    let configURL: URL
    private let broadcaster = Broadcaster()
    private(set) var input: InputRouter!
    @MainActor var keyTapRunning = false
    private(set) var switcher: SwitcherController!
    @MainActor private var idleWatcher: IdleWatcher!
    @MainActor private var wallpaper: WallpaperSwitcher!
    @MainActor private(set) var palette: PaletteController!
    @MainActor let cheatsheet = CheatsheetController()
    @MainActor private var pickerTarget: WindowID?
    @MainActor private lazy var picker: TemplatePicker = {
        let picker = TemplatePicker()
        picker.style = { [unowned self] in manager.settings.appearance.resolved() }
        picker.onChoose = { [unowned self] template in
            if let template, template.isFrame, !manager.templates(of: pickerTarget).contains(template) { manager.remember(frame: template) }
            _ = run(["layout", "tile", TemplateGlyph.label(template)], target: pickerTarget)
        }
        return picker
    }()
    @MainActor private lazy var trackpad = TrackpadInput(
        deliver: { [unowned self] events in input.handleFinger(events) }, pinch: { [unowned self] pinch in input.handlePinch(pinch) })
    @MainActor private lazy var hints = HintController(colors: { [unowned self] in manager.settings.hints }, look: { [unowned self] in labelLook })
    @MainActor private lazy var scroller = ScrollController(colors: { [unowned self] in manager.settings.hints }, look: { [unowned self] in labelLook })
    @MainActor private lazy var jump = JumpController(
        colors: { [unowned self] in manager.settings.hints }, windows: { [unowned self] in manager.jumpWindows() },
        choose: { [unowned self] id, action in manager.jumpChoose(id, action) })
    @MainActor private lazy var selector = SelectController(
        colors: { [unowned self] in manager.settings.hints }, keys: { [unowned self] in manager.settings.select },
        look: { [unowned self] in labelLook }, display: { [unowned self] in manager.focusedMonitor.map { ($0.id, $0.frame) } },
        notify: { [unowned self] text in onNotify(text, 2) })
    @MainActor private var labelLook: LabelLook {
        LabelLook(settings: manager.settings.prefix.label, style: manager.settings.appearance.resolved())
    }
    private let menuReader = MenuReader()
    @MainActor private lazy var menuPopup = MenuPopup()
    private lazy var host = LuaHost(bridge: self)
    private var server: SocketServer?
    @MainActor var onConfigError: (String?) -> Void = { _ in }
    @MainActor var trayVisible: () -> Bool = { false }
    @MainActor var trayDebug: () -> String = { "" }
    @MainActor var onNotify: (String, TimeInterval) -> Void = { _, _ in }
    @MainActor private(set) var bindRecords: [BindRecord] = []

    @MainActor init(manager: WindowManager, configURL: URL) {
        self.manager = manager
        self.configURL = configURL
        input = InputRouter(
            manager: manager,
            run: { [unowned self] command in
                let words = splitCommand(command)
                let answer = run(words)
                if words.first == "window", ["remember", "forget"].contains(words.dropFirst().first) {
                    notifyOutcome(of: answer)
                }
            },
            call: { [unowned self] id in host.call(function: id) }
        )
        switcher = SwitcherController(manager: manager)
        input.switcher = switcher
        palette = PaletteController(
            manager: manager, reader: menuReader,
            cachedImage: { [unowned switcher = switcher!] id in switcher.cachedImage(id) },
            run: { [unowned self] words in run(words) },
            notify: { [unowned self] text in onNotify(text, 3) })
        input.palette = palette
        input.cheatsheet = cheatsheet
        input.picker = picker
        input.hints = hints
        input.scroller = scroller
        input.jump = jump
        input.selector = selector
        switcher.chordFlags = { [unowned input = input!] in input.currentFlags }
        idleWatcher = IdleWatcher(emit: { [manager] name, payload in manager.events.emit(name, payload) }, isPaused: { [manager] in manager.isPaused })
        wallpaper = WallpaperSwitcher()
        manager.onWorkspacesShown = { [unowned self] shown in wallpaper.update(shown: shown) }
        manager.runOnEmpty = { [unowned self] request in
            guard let pid = runShell(request.command) else { return }
            if let options = request.options { manager.expectWindow(from: pid, options: options) }
        }
        manager.runRuleCommand = { [unowned self] command, window in _ = run(command, target: window) }
        manager.events.add { [unowned self] name, payload in
            host.fire(event: name, payload: payload)
            broadcaster.send(event: name, json: LuaValue.table(payload.merging(["event": .string(name)]) { $1 }).json)
        }
    }

    @MainActor private func notifyOutcome(of answer: ServerAnswer) {
        let failed = answer.exitCode != 0
        let line = (failed ? answer.stderr : answer.stdout).split(separator: "\n").first.map(String.init) ?? ""
        let message = line.replacingOccurrences(of: "wm: error: ", with: "")
        if !message.isEmpty { onNotify(failed ? "wm: \(message)" : message, failed ? 4 : 2) }
    }

    @MainActor func startServer() throws {
        server = try SocketServer(subscriber: { [broadcaster, unowned self] descriptor, words in
            guard case .success(let subscription) = Subscription.parse(words) else {
                close(descriptor)
                return
            }
            broadcaster.add(descriptor, subscription, snapshot: subscription.snapshot ? snapshotJSON() : nil)
        }) { [unowned self] request in
            run(request)
        }
    }

    private func snapshotJSON() -> String {
        let overview = run(ClientRequest(args: ["list", "--json"])).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = onMain { manager.mode }
        return #"{"event":"snapshot","mode":\#(LuaValue.string(mode).json),"state":\#(overview.isEmpty ? "null" : overview)}"#
    }

    @MainActor func stopServer() {
        server?.stop()
        manager.saveState()
        manager.restoreAll()
        wallpaper.restore()
    }

    func run(_ request: ClientRequest) -> ServerAnswer {
        let (args, verbose) = stripVerbose(request.args)
        if let id = request.windowId, onMain({ manager.windows[id] == nil }) {
            return fail("no window with id \(id)", 1, hint: "see `wm list windows` for ids")
        }
        var target = request.windowId
        if let selector = request.windowSelector {
            guard let id = onMain({ manager.window(matching: selector) }) else {
                return fail("no window matches '\(selector)'", 1, hint: "see `wm list windows`")
            }
            target = id
        }
        var answer = run(args, target: target)
        if verbose, answer.exitCode == 0 { answer.stdout += onMain { stateLine() } }
        return answer
    }

    @MainActor private func showMenu(of target: WindowID?) -> ServerAnswer {
        let pid: pid_t
        if let id = target ?? manager.focused, let managed = manager.windows[id] {
            pid = managed.info.pid
        } else if let front = NSWorkspace.shared.frontmostApplication {
            pid = front.processIdentifier
        } else {
            return fail("there is no app to show the menus of")
        }
        let reader = menuReader
        Task { @MainActor in
            guard let tree = await reader.read(pid: pid) else {
                onNotify("This app has no menus that wm can read", 2)
                return
            }
            menuPopup.show(tree) { token in
                NSRunningApplication(processIdentifier: pid)?.activate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { reader.press(token: token) }
            }
        }
        return ok()
    }

    @MainActor private func updateTrackpad(_ settings: TrackpadSettings) {
        trackpad.stop()
        guard settings.enabled else { return }
        guard !trackpad.start() else { return }
        let message = "trackpad gestures need MultitouchSupport and a trackpad"
        if settings.warnsWhenMissing { onNotify("wm: \(message)", 3) } else { Log.write(.info, message, source: "trackpad") }
    }

    @MainActor private func stateLine() -> String {
        let workspace = manager.focusedWorkspace
        var parts = ["workspace \(workspace?.name ?? "-") (\(workspace?.kind.rawValue ?? "-"))"]
        if let id = manager.focused, let window = manager.windows[id] { parts.append("focus \(id) \(window.info.appName)") }
        parts.append("\(manager.windows.count) windows")
        return parts.joined(separator: " · ") + "\n"
    }

    func run(_ args: [String], target: WindowID? = nil) -> ServerAnswer {
        switch args.first {
        case "version": return ok("wm \(Self.version) (Lua 5.4)\n")
        case "noop": return ok()
        case "doctor":
            return onMain {
                let facts = DoctorFacts(
                    accessibility: AXIsProcessTrusted(), keyTap: keyTapRunning, screenRecording: CGPreflightScreenCaptureAccess(),
                    loginItemWanted: manager.settings.startAtLogin, loginItemEnabled: SMAppService.mainApp.status == .enabled,
                    isAppBundle: Bundle.main.bundleURL.pathExtension == "app", onboarded: Onboarding.isDone(),
                    native: manager.nativeFacts())
                return (try? JSONEncoder().encode(facts)).map { ok(String(decoding: $0, as: UTF8.self)) } ?? fail("cannot encode the facts")
            }
        case "switcher":
            return onMain {
                switcher.command(Array(args.dropFirst()), preselect: target).map { fail($0, 1, usage: "switcher") } ?? ok()
            }
        case "overview":
            let mode = args.dropFirst().first
            guard mode == nil || ["open", "close", "toggle"].contains(mode) else {
                return fail("overview takes open, close or toggle", 2, usage: "overview")
            }
            return onMain { switcher.overview(mode: mode ?? "toggle").map { fail($0) } ?? ok() }
        case "hints", "scroll":
            let parsed = parseToggleArguments(Array(args.dropFirst()))
            let flags = parsed.flags
            if let bad = unknownOption(flags, allowed: args[0] == "hints" ? ["--wait"] : [], usage: args[0]) { return bad }
            guard parsed.isValid else { return fail("\(args[0]) takes open, close or toggle", 2, usage: args[0]) }
            let mode = parsed.mode?.rawValue
            return onMain {
                if mode != "close" { selector.close(); jump.close() }
                let error: String?
                if args[0] == "hints" {
                    if mode != "close" { scroller.close() }
                    error = hints.command(mode ?? "toggle", wait: flags.contains("--wait"))
                } else {
                    if mode != "close" { hints.close() }
                    error = scroller.command(mode ?? "toggle")
                }
                return error.map { fail($0) } ?? ok()
            }
        case "jump":
            let parsed = parseToggleArguments(Array(args.dropFirst()))
            let flags = parsed.flags
            if let bad = unknownOption(flags, allowed: ["--swap", "--close"], usage: "jump") { return bad }
            guard parsed.isValid else { return fail("jump takes open, close or toggle", 2, usage: "jump") }
            let mode = parsed.mode?.rawValue
            guard flags.count < 2 else { return fail("jump takes --swap or --close, not both", 2, usage: "jump") }
            let action: JumpAction = flags.contains("--swap") ? .swap : flags.contains("--close") ? .close : .focus
            return onMain {
                if mode != "close" { hints.close(); scroller.close(); selector.close() }
                return jump.command(mode ?? "toggle", action: action).map { fail($0) } ?? ok()
            }
        case "select":
            let mode = args.dropFirst().first
            guard args.count <= 2, mode == nil || ["open", "close", "toggle"].contains(mode) else {
                return fail("select takes open, close or toggle", 2, usage: "select")
            }
            return onMain {
                if mode != "close" {
                    hints.close()
                    scroller.close()
                    jump.close()
                }
                return selector.command(mode ?? "toggle").map { fail($0) } ?? ok()
            }
        case "menu":
            return onMain { showMenu(of: target) }
        case "palette":
            return onMain { palette.command(Array(args.dropFirst())).map { fail($0, 2, usage: "palette") } ?? ok() }
        case "layout" where args == ["layout", "tile"]:
            return onMain {
                guard let monitor = manager.focusedMonitor else { return fail("there is no monitor") }
                let id = target ?? manager.focused
                pickerTarget = id
                picker.show(on: monitor.workArea, templates: manager.templates(of: id), current: manager.template(of: id), allowsGrid: manager.layoutKind(of: id) == .tiling)
                return ok()
            }
        case "cheatsheet":
            return cheatsheetCommand(Array(args.dropFirst()))
        case "list" where args.dropFirst().first == "binds":
            return onMain { listBinds(Set(args.filter { $0.hasPrefix("--") })) }
        case "daemon": return daemon(Array(args.dropFirst()))
        case "subscribe":
            if case .failure(let error) = Subscription.parse(Array(args.dropFirst())) {
                return fail(error.message, 2, usage: "subscribe", hint: "events: " + subscribableEvents.joined(separator: ", "))
            }
            return ok()
        case "pick":
            return pick(Array(args.dropFirst()))
        case "exec":
            let text = args.dropFirst().joined(separator: " ")
            let parsed: ExecRequest
            do { parsed = try parseExecRule(text) } catch let error as ConfigError { return fail(error.message, 2, usage: "exec") } catch { return fail("\(error)") }
            guard !parsed.command.isEmpty else { return fail("exec needs a shell command", 2, usage: "exec") }
            let pid = runShell(parsed.command, window: target)
            if let options = parsed.options, let pid { onMain { manager.expectWindow(from: pid, options: options) } }
            return ok()
        case "batch":
            return batch(args.dropFirst().joined(separator: " "), target: target)
        case "set":
            return onMain { setSetting(Array(args.dropFirst())) }
        case "notify":
            return onMain { notify(Array(args.dropFirst())) }
        case "key":
            return onMain { sendKey(Array(args.dropFirst()), target: target) }
        case "mode":
            guard let name = args.dropFirst().first else { return fail("mode needs a name", 2, usage: "mode") }
            if name == "back" { return onMain { _ = manager.modeBack(); return ok() } }
            return onMain {
                manager.setMode(name) ? ok() : fail("no mode '\(name)'", 1, hint: "modes: " + manager.modeNames.sorted().joined(separator: ", "))
            }
        case nil:
            return fail("missing command", 2, hint: "run `wm help` to see the commands")
        default:
            return onMain { manager.execute(args, target: target) }
        }
    }

    private func pick(_ rest: [String]) -> ServerAnswer {
        if let bad = unknownOption(Set(rest.filter { $0.hasPrefix("--") }), allowed: ["--json"], usage: "pick") { return bad }
        if rest.contains(where: { !$0.hasPrefix("--") }) { return fail("pick takes no arguments", 2, usage: "pick") }
        if Thread.isMainThread { return fail("pick only works from the command line", 1, hint: "run `wm pick` in a terminal") }

        let click = Slot<CGPoint>()
        let clicked = DispatchSemaphore(value: 0)
        let armed = onMain {
            let armed = input.beginPick { point in
                click.value = point
                clicked.signal()
            }
            if armed { onNotify("Click a window · Esc cancels", 2) }
            return armed
        }
        guard armed else { return fail("another `wm pick` is waiting for a click") }
        let finished = clicked.wait(timeout: .now() + 30) == .success
        let point = onMain {
            input.endPick()
            return click.value
        }
        guard let point else { return fail(finished ? "pick cancelled" : "no click within 30 seconds") }
        guard let hit = WindowList.frontmost(at: point) else { return fail("there is no window at the click") }

        let unmanaged = Slot<WindowInfo>()
        if onMain({ manager.windows[hit.id] == nil }) {
            let read = DispatchSemaphore(value: 0)
            Task { @MainActor in
                unmanaged.value = await manager.readWindow(hit.id, pid: hit.pid)
                read.signal()
            }
            read.wait()
        }
        return onMain {
            guard let picked = manager.pickedWindow(hit.id, unmanaged: unmanaged.value) else {
                return fail("wm cannot read this window", 1, hint: "it belongs to an app that wm does not watch (pid \(hit.pid))")
            }
            return ok(rest.contains("--json") ? manager.pickValue(picked).json + "\n" : renderPick(picked))
        }
    }

    private func cheatsheetCommand(_ words: [String]) -> ServerAnswer {
        guard words.count <= 1, words.first.map({ ["tui", "gui"].contains($0) }) ?? true else {
            return fail("expected tui or gui", 2, usage: "cheatsheet")
        }
        if words.first == "tui" {
            return fail("the terminal sheet is drawn by `wm` in a terminal", 2, usage: "cheatsheet", hint: "run `wm cheatsheet tui` in a terminal")
        }
        return onMain {
            cheatsheet.toggle(binds: bindRecords.map(CheatBind.init), mode: manager.mode, style: manager.settings.appearance.resolved())
            return ok()
        }
    }

    @MainActor private func listBinds(_ flags: Set<String>) -> ServerAnswer {
        if let bad = unknownOption(flags, allowed: ["--json"], usage: "list") { return bad }
        func when(_ trigger: BindTrigger) -> String { trigger == .longPress ? "long press" : trigger.rawValue }
        if flags.contains("--json") {
            return ok(LuaValue.array(bindRecords.map { record in
                .table([
                    "mode": .string(record.mode), "keys": .string(record.keys), "trigger": .string(record.trigger.rawValue),
                    "command": .string(record.action), "description": record.options.description.map { .string($0) } ?? .nil,
                    "repeating": record.options.repeating.map { .bool($0) } ?? .nil, "universal": .bool(record.options.universal),
                    "hidden": .bool(record.options.hidden),
                ])
            }).json + "\n")
        }
        return ok(renderTable(["mode", "keys", "when", "command", "description"], bindRecords.map {
            [$0.mode, $0.keys, when($0.trigger), truncated($0.action, to: 40), $0.options.description ?? ""]
        }))
    }

    private func daemon(_ words: [String]) -> ServerAnswer {
        let flags = Set(words.filter { $0.hasPrefix("--") })
        switch words.first(where: { !$0.hasPrefix("--") }) {
        case "status":
            if let bad = unknownOption(flags, allowed: ["--json"], usage: "daemon status") { return bad }
            return onMain { status(json: flags.contains("--json")) }
        case "reload":
            if let bad = unknownOption(flags, allowed: [], usage: "daemon reload") { return bad }
            return reloadFromAnyThread()
        case "stop":
            if let bad = unknownOption(flags, allowed: [], usage: "daemon stop") { return bad }
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
            return ok()
        case "start":
            return ok("wm is already running\n")
        default:
            return fail("daemon needs start, stop, status or reload", 2, usage: "daemon")
        }
    }

    @MainActor private func status(json: Bool) -> ServerAnswer {
        let workspace = manager.focusedWorkspace
        let debug = ProcessInfo.processInfo.environment["WM_DEBUG"] != nil
        if json {
            return ok(LuaValue.table([
                "running": .bool(true), "version": .string(Self.version),
                "workspace": .string(workspace?.name ?? ""), "layout": .string(workspace?.kind.rawValue ?? ""),
                "mode": .string(manager.mode), "windows": .number(Double(manager.windows.count)),
                "monitors": .number(Double(manager.monitors.count)), "menu_bar_visible": .bool(trayVisible()),
            ]).json + "\n")
        }
        var rows = [
            ["workspace", workspace.map { "\($0.name) (\($0.kind.rawValue))" } ?? "-"],
            ["mode", manager.mode],
            ["windows", String(manager.windows.count)],
            ["monitors", String(manager.monitors.count)],
            ["menu bar", trayVisible() ? "shown" : "hidden by macOS: allow wm in System Settings > Menu Bar"],
        ]
        if debug { rows += [["tray", trayDebug()], ["animation", manager.animationSummary]] }
        let width = rows.map { $0[0].count }.max() ?? 0
        return ok((["wm \(Self.version) is running"] + rows.map { "  " + $0[0].padding(toLength: width, withPad: " ", startingAt: 0) + "  " + $0[1] }).joined(separator: "\n") + "\n")
    }

    private func onMain<T: Sendable>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated(body) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(body) }
    }

    private func batch(_ text: String, target: WindowID?) -> ServerAnswer {
        let commands = splitBatch(text)
        guard !commands.isEmpty else { return fail("batch needs commands separated by ;", 2, usage: "batch") }
        var output = ""
        for command in commands {
            let words = splitCommand(command)
            guard words.first != "batch" else { return fail("a batch cannot contain a batch", 2, usage: "batch") }
            var answer = run(words, target: target)
            output += answer.stdout
            if answer.exitCode != 0 {
                answer.stdout = output
                answer.stderr += "hint: the batch stopped at `\(command)`\n"
                return answer
            }
        }
        return ok(output)
    }

    @MainActor private func setSetting(_ words: [String]) -> ServerAnswer {
        guard words.count >= 2 else { return fail("set needs a setting and a value", 2, usage: "set") }
        var next = manager.settings
        do {
            try applyRuntimeSetting(path: words[0], value: words.dropFirst().joined(separator: " "), to: &next)
        } catch let error as ConfigError {
            return fail(error.message, 2, usage: "set")
        } catch {
            return fail("\(error)")
        }
        manager.apply(settings: next, rules: manager.rules, workspaceLayouts: manager.workspaceLayouts, workspaceRules: manager.workspaceRules)
        input.tap.setPointerTracking(next.focusFollowsMouse.enabled)
        updateTrackpad(next.trackpad)
        return ok()
    }

    @MainActor private func notify(_ words: [String]) -> ServerAnswer {
        var seconds = 2.0
        var text: [String] = []
        for word in words {
            if word.hasPrefix("--seconds=") {
                guard let value = Double(word.dropFirst(10)), value > 0 else { return fail("--seconds needs a positive number", 2, usage: "notify") }
                seconds = min(value, 60)
            } else if word.hasPrefix("--") {
                return fail("unknown option \(word)", 2, usage: "notify")
            } else {
                text.append(word)
            }
        }
        guard !text.isEmpty else { return fail("notify needs a text", 2, usage: "notify") }
        onNotify(text.joined(separator: " "), seconds)
        return ok()
    }

    @MainActor private func sendKey(_ words: [String], target: WindowID?) -> ServerAnswer {
        guard let verb = words.first, ["send", "press"].contains(verb), let text = words.dropFirst().first else {
            return fail("key needs send or press, and a chord", 2, usage: "key send")
        }
        if verb == "press" {
            guard let chord = try? parseChord(text, allowMedia: true), !chord.modifiers.contains(.hyper) else {
                return fail("'\(text)' is not a chord like cmd-shift-r or a media key like play", 2, usage: "key press")
            }
            KeyOutput.tap(chord)
            return ok()
        }
        guard let chord = try? parseChord(text), !chord.modifiers.contains(.hyper), let code = KeyCodes.code(for: chord.key) else {
            return fail("'\(text)' is not a chord like cmd-shift-r", 2, usage: "key send")
        }
        guard let id = target ?? manager.focused, let window = manager.windows[id] else { return fail("there is no window to send the key to") }
        EventTap.post(keyCode: code, flags: KeyOutput.flags(of: chord.modifiers), toPID: window.info.pid)
        return ok()
    }

    @discardableResult
    private func runShell(_ command: String, window: WindowID? = nil) -> Int32? {
        let process = Process()
        if let window {
            process.environment = ProcessInfo.processInfo.environment.merging(["WM_WINDOW_ID": String(window)]) { $1 }
        }
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return process.processIdentifier
        } catch {
            Log.write(.error, "exec failed: \(error)", source: "exec")
            return nil
        }
    }

    @MainActor func handle(url: URL) {
        guard let request = commandRequest(fromURL: url) else { return }
        if let command = urlBlockedCommand(in: request.args, allowed: manager.settings.urlAllow) {
            Log.write(.warn, "blocked wm:// command '\(command)'; add it to url.allow to permit it", source: "url")
            return
        }
        let answer = run(request)
        if answer.exitCode != 0 { Log.write(.error, answer.stderr.trimmingCharacters(in: .whitespacesAndNewlines), source: "url") }
    }

    private func reloadFromAnyThread() -> ServerAnswer {
        if Thread.isMainThread { return reloadInBackground() }
        return reload()
    }

    private func reloadInBackground() -> ServerAnswer {
        Task.detached { [self] in _ = reload() }
        return ok("reloading\n")
    }

    func reload(notify: Bool = true) -> ServerAnswer {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            let message = "no config at \(configURL.path); using defaults"
            onMain { apply(LoadedConfig(settings: Settings(), binds: [:], rules: [])); onConfigError(message) }
            if notify { notifyConfig(title: "wm: no config", body: message) }
            return fail(message)
        }
        do {
            let loaded = try host.load(configURL: configURL)
            onMain { apply(loaded); onConfigError(nil) }
            Log.write(.info, "config loaded: \(configURL.path)", source: "config")
            if notify { notifyConfig(title: "wm", body: "Config reloaded: \(configURL.lastPathComponent)") }
            return ok("config reloaded\n")
        } catch {
            let message = (error as? ConfigError)?.message ?? "\(error)"
            Log.write(.error, "config error: \(message)", source: "config")
            onMain { onConfigError(message) }
            if notify { notifyConfig(title: "wm: config error", body: message) }
            return fail(message)
        }
    }

    private func notifyConfig(title: String, body: String) {
        Task {
            do { try await SystemNotification.post(title: title, body: body, id: "wm.config") } catch {
                Log.write(.debug, "cannot show a notification: \(error)", source: "notification")
            }
        }
    }

    private var systemCmdTabDisabled = false

    @MainActor private func setSystemCmdTab(disabled: Bool) {
        guard disabled != systemCmdTabDisabled else { return }
        systemCmdTabDisabled = disabled
        SystemShortcuts.setCommandTab(enabled: !disabled)
    }

    private var capsLockMapped = false
    private var keyboardSettings = KeyboardSettings()
    @MainActor private lazy var keyboardWatcher = KeyboardWatcher { [unowned self] in refreshKeyboards() }

    @MainActor private func setCapsLockHyper(_ on: Bool) {
        guard on || capsLockMapped else { return }
        capsLockMapped = on
        if on { refreshKeyboards() } else { KeyboardRemap.removeCapsLockMapping() }
    }

    @MainActor private func refreshKeyboards() {
        guard capsLockMapped else { return }
        let keyboards = KeyboardDevices.list()
        if keyboards.isEmpty {
            KeyboardRemap.setCapsLockToF18(true)
        } else {
            KeyboardRemap.apply(KeyboardPlan.plan(keyboards, settings: keyboardSettings))
        }
    }

    @MainActor func watchKeyboards() {
        keyboardWatcher.start()
    }

    @MainActor func restoreSystemShortcuts() {
        setSystemCmdTab(disabled: false)
        setCapsLockHyper(false)
    }

    @MainActor func keyboardsWoke() {
        refreshKeyboards()
    }

    @MainActor private func apply(_ loaded: LoadedConfig) {
        manager.modeNames = Set(loaded.binds.keys).subtracting([universalMode]).union(["main"])
        _ = manager.setMode("main")
        input.cancelSequence()
        input.binds = loaded.binds
        input.sequences = loaded.sequences
        input.releaseBinds = loaded.releaseBinds
        input.longPressBinds = loaded.longPressBinds
        input.holdBinds = loaded.holdBinds
        setSystemCmdTab(disabled: loaded.settings.binds.disableSystemCmdTab)
        keyboardSettings = loaded.settings.keyboards
        setCapsLockHyper(loaded.settings.binds.capsLockHyper)
        input.noRepeat = loaded.noRepeat
        input.modeOptions = loaded.modeOptions
        input.longPressTimeouts = loaded.longPressTimeouts
        let pad = loaded.settings.trackpad
        let builtIn = pad.enabled ? Gesture.missingDefaults(loaded.gestures, fingers: pad.fingers) : []
        let titleBar = pad.enabled && pad.titleBar
            ? loaded.gestures.filter { $0.zone == .titleBar } + Gesture.missingTitleBarDefaults(loaded.gestures) : []
        input.gestures = loaded.gestures + builtIn
        input.titleBarGestures = titleBar
        bindRecords = loaded.bindRecords + builtIn.map(\.bindRecord) + titleBar.filter(\.isBuiltIn).map(\.bindRecord)
        manager.apply(
            settings: loaded.settings, rules: loaded.rules, workspaceLayouts: loaded.workspaceLayouts,
            workspaceRules: loaded.workspaceRules)
        input.tap.setPointerTracking(loaded.settings.focusFollowsMouse.enabled)
        updateTrackpad(loaded.settings.trackpad)
        updateStartAtLogin(loaded.settings.startAtLogin)
        idleWatcher.configure(thresholds: loaded.idleThresholds)
        wallpaper.configure(Dictionary(uniqueKeysWithValues: loaded.workspaceRules.compactMap { name, rule in rule.wallpaper.map { (name, $0) } }))
        manager.events.emit("config_reloaded")
    }

    @MainActor private func updateStartAtLogin(_ wanted: Bool) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let service = SMAppService.mainApp
        do {
            if wanted, service.status != .enabled { try service.register() }
            if !wanted, service.status == .enabled { try service.unregister() }
        } catch {
            Log.write(.error, "start_at_login: \(error)", source: "login")
        }
    }

    func dispatch(_ command: String, window: UInt32?) -> (exitCode: Int32, stdout: String, stderr: String) {
        var words = splitCommand(command)
        var target = window
        var selector: String?
        if target == nil {
            do {
                let parsed = try parseWindowFlag(words)
                target = parsed.windowId
                selector = parsed.selector
                words = parsed.rest
            } catch let error as WindowFlagError {
                return (2, "", "wm: \(error.message)\n")
            } catch {}
        }
        let answer = Array(words.prefix(2)) == ["daemon", "reload"] ? reloadInBackground() : run(ClientRequest(args: words, windowId: target, windowSelector: selector))
        return (answer.exitCode, answer.stdout, answer.stderr)
    }

    func query(_ what: String) -> LuaValue {
        onMain { manager.query(what) ?? .nil }
    }

    func exec(_ command: String) {
        runShell(command)
    }

    func exec(_ command: String, options: ExecOptions) {
        guard let pid = runShell(command) else { return }
        onMain { manager.expectWindow(from: pid, options: options) }
    }

    func log(_ message: String) {
        Log.write(.info, message, source: "lua")
    }

    func logError(_ message: String) {
        Log.write(.error, message, source: "lua")
    }
}

final class Broadcaster: @unchecked Sendable {
    private let queue = DispatchQueue(label: "wm.broadcast")
    private var subscribers: [(descriptor: Int32, subscription: Subscription)] = []

    func add(_ descriptor: Int32, _ subscription: Subscription, snapshot: String? = nil) {
        queue.async {
            if let snapshot, (try? writeFrame(descriptor, Data(snapshot.utf8))) == nil {
                close(descriptor)
                return
            }
            self.subscribers.append((descriptor, subscription))
        }
    }

    func send(event: String, json: String) {
        queue.async {
            let payload = Data(json.utf8)
            self.subscribers.removeAll { subscriber in
                guard subscriber.subscription.wants(event) else { return false }
                guard (try? writeFrame(subscriber.descriptor, payload)) == nil else { return false }
                close(subscriber.descriptor)
                return true
            }
        }
    }
}

private final class Slot<Value>: @unchecked Sendable {
    var value: Value?
}
