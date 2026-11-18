import AppKit
import Common
import Core
import Platform

/// The command palette: one text field that finds running apps with their windows, the tabs of browsers and terminals, wm
/// commands and the menu items of the frontmost app. Every row has an icon: the icon of the app, or a small window drawn for the command.
///
/// `palette` opens it. Without a prefix it lists the running apps, each followed by its windows, and typing finds tabs
/// too; `>` lists the commands and `/` the menu items of the app that was in front. Up and down move, Return runs the row, Tab completes a command, Escape
/// closes.
@MainActor
final class PaletteController {
    private let manager: WindowManager
    private let panel = PalettePanel()
    private let reader: MenuReader
    private let cachedImage: (WindowID) -> CGImage?
    private let thumbnails = ThumbnailService()
    private let run: ([String]) -> ServerAnswer
    private let notify: (String) -> Void

    /// The modifiers that keep the `--cmdtab` palette open. `nil`: the palette is the normal one.
    private var holding: CGEventFlags?
    private var defaultMode: PaletteMode = .all
    private var input = ""
    private var entries: [PaletteEntry] = []
    private var flatWindows: [PaletteEntry] = []
    private var shown: [PaletteEntry] = []
    private var icons: [pid_t: NSImage] = [:]
    private var menuPID: pid_t?
    private var menuEntries: [PaletteEntry] = []
    private let tabReader = TabReader()
    /// The tabs of the last time the palette read them. They stay between openings, so the list is there at once; each
    /// opening reads them again. The key of a tab entry is its index here.
    private var tabs: [PaletteTab] = []
    private var webTabs: [PaletteTab] = []
    private var rexTabList: [PaletteTab] = []
    private var tmuxTabList: [PaletteTab] = []
    private var tabEntries: [PaletteEntry] = []
    /// The list of `palette tabs`: the tabs, and the windows of the apps that have no tabs, grouped by app, the app of the
    /// most recent window first.
    private var tabsList: [PaletteEntry] = []
    /// The terminals that show tmux, for the icon of a tmux window.
    private var tmuxClients: [TmuxClient] = []
    /// The preview shows the picture of the selected window. It needs the setting and the Screen Recording permission, like
    /// the window switcher.
    private var previewsOn = false
    private var previewTask: Task<Void, Never>?
    /// Pictures taken while the palette is open: larger than the ones of the switcher.
    private var previews: [WindowID: CGImage] = [:]

    var isOpen: Bool { panel.isOpen }

    init(manager: WindowManager, reader: MenuReader, cachedImage: @escaping (WindowID) -> CGImage?, run: @escaping ([String]) -> ServerAnswer, notify: @escaping (String) -> Void) {
        self.manager = manager
        self.reader = reader
        self.cachedImage = cachedImage
        self.run = run
        self.notify = notify
        panel.onChange = { [unowned self] text in changed(text) }
        panel.onActivate = { [unowned self] row in activate(row) }
        panel.onTab = { [unowned self] row in complete(row) }
        panel.onSelect = { [unowned self] row in selected(row) }
        panel.onCancel = { [unowned self] in close() }
    }

    /// `palette [windows|apps|tabs|commands|menu] [--cmdtab [--reverse]]`. Returns an error message for a word that is not a list.
    func command(_ arguments: [String]) -> String? {
        let usage = "usage: palette [windows|apps|tabs|commands|menu|reset] [--cmdtab [--reverse]]"
        // Like the command of Raycast that resets its window position: bind it, or run it from the `>` list.
        if arguments == ["reset"] {
            panel.resetPosition()
            return nil
        }
        let words = arguments.filter { !$0.hasPrefix("--") }
        let cmdTab = arguments.contains("--cmdtab"), reverse = arguments.contains("--reverse")
        guard Set(arguments.filter { $0.hasPrefix("--") }).isSubset(of: ["--cmdtab", "--reverse"]), words.count <= 1, !reverse || cmdTab else { return usage }
        if isOpen {
            // A second press of the same keys goes to the next app.
            if cmdTab, holding != nil { move(reverse ? -1 : 1) } else { close() }
            return nil
        }
        let mode: PaletteMode
        if cmdTab {
            guard words.isEmpty else { return usage }
            mode = .apps
        } else if let word = words.first {
            guard let named = PaletteMode(rawValue: word), named != .all else { return usage }
            mode = named
        } else {
            mode = .all
        }
        open(mode, cmdTab: cmdTab, reverse: reverse)
        return nil
    }

    // MARK: - Cmd+Tab

    /// The keys of the `--cmdtab` palette. Tab and the arrow keys move, Return switches, Escape cancels. The keys are used up,
    /// so the Cmd+Tab of macOS does not see them. Any other key closes the palette and goes on to the app.
    func handleKey(_ key: String, flags: CGEventFlags) -> Bool {
        guard isOpen, holding != nil else { return false }
        switch key {
        case "tab": move(flags.contains(.maskShift) ? -1 : 1)
        case "left", "up": move(-1)
        case "right", "down": move(1)
        case "enter", "space": commit()
        case "esc": close()
        default:
            close()
            return false
        }
        return true
    }

    /// Letting go of the modifier of the `--cmdtab` palette switches to the selected app.
    func flagsChanged(_ flags: CGEventFlags) {
        guard isOpen, let hold = holding, flags.intersection(hold).isEmpty else { return }
        commit()
    }

    private func move(_ delta: Int) {
        panel.move(delta)
    }

    private func commit() {
        let row = panel.selectedRow
        activate(row)
        close()
    }

    // MARK: - Opening

    private func open(_ mode: PaletteMode, cmdTab: Bool = false, reverse: Bool = false) {
        defaultMode = mode
        holding = cmdTab ? EventTap.currentFlags().intersection([.maskCommand, .maskAlternate, .maskControl]) : nil
        icons = [:]
        previews = [:]
        if manager.settings.switcher.thumbnails, !ThumbnailService.hasPermission { ThumbnailService.requestOnce() }
        previewsOn = manager.settings.switcher.thumbnails && ThumbnailService.hasPermission
        panel.previewsEnabled = previewsOn
        menuPID = manager.focused.flatMap { manager.windows[$0]?.info.pid } ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        menuEntries = []
        entries = appEntries() + commandEntries()
        flatWindows = windowEntries()
        rebuildTabsList()
        let prefix = mode == .commands ? "> " : mode == .menu ? "/ " : ""
        input = prefix
        panel.show(text: prefix, placeholder: cmdTab ? "Switch to an app" : mode == .tabs ? "Search tabs…" : "Search windows, apps and tabs…")
        refresh()
        if cmdTab {
            // Like Cmd+Tab: the first press selects the previous app, and a reverse press the last one.
            panel.select(row: reverse ? max(shown.count - 1, 0) : min(1, max(shown.count - 1, 0)))
            // A tap that is over before the palette opens (the modifier is already up) switches at once.
            if holding?.isEmpty == true { commit() }
            return
        }
        if let pid = menuPID {
            let reader = reader
            Task { @MainActor in
                guard let tree = await reader.read(pid: pid), isOpen else { return }
                menuEntries = tree.flattened().map { PaletteEntry(kind: .menu, title: $0.path, detail: $0.shortcut ?? "", key: String($0.token)) }
                refresh()
            }
        }
        loadTabs()
    }

    /// What one source gave. Each source is shown as soon as it is there: tmux and Rex answer at once, and a browser can
    /// take seconds.
    private enum TabSource: Sendable {
        case web([PaletteTab]), rex([PaletteTab]), tmux([PaletteTab], [TmuxClient])
    }

    private func loadTabs() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let browsers = TabReader.browsers.filter(running.contains)
        let rexRuns = running.contains(TabReader.rexBundleID)
        if !rexRuns { apply(.rex([])) }
        Task { @MainActor [tabReader] in
            await withTaskGroup(of: TabSource.self) { group in
                group.addTask { .web(await tabReader.browserTabs(browsers)) }
                if rexRuns { group.addTask { .rex(await tabReader.rexTabs()) } }
                group.addTask { .tmux(await tabReader.tmuxTabs(), await tabReader.clients()) }
                for await source in group { apply(source) }
            }
        }
    }

    /// Keeps what a source gave. A source that gave the same as the last time changes nothing, so the selection of the
    /// user stays where it is.
    private func apply(_ source: TabSource) {
        switch source {
        case let .web(found):
            guard found != webTabs else { return }
            webTabs = found
        case let .rex(found):
            guard found != rexTabList else { return }
            rexTabList = found
        case let .tmux(found, clients):
            guard found != tmuxTabList || clients != tmuxClients else { return }
            tmuxTabList = found
            tmuxClients = clients
        }
        tabs = webTabs + rexTabList + tmuxTabList
        rebuildTabsList()
        if isOpen { refresh() }
        Log.write(.debug, "palette tabs: " + tabCounts(tabs), source: "palette")
    }

    /// How many tabs each source gave, for the log: a source that gives none is the first thing to look at.
    private func tabCounts(_ read: [PaletteTab]) -> String {
        var counts: [String: Int] = ["browsers": 0, "rex": 0, "tmux": 0]
        for tab in read {
            switch tab.source {
            case .browser: counts["browsers", default: 0] += 1
            case .rex: counts["rex", default: 0] += 1
            case .tmux: counts["tmux", default: 0] += 1
            }
        }
        return counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
    }

    /// The tabs of `palette tabs`, with the windows of the apps that give no tabs: the window is the tab of such an app. An
    /// app whose tabs were read (a browser, Rex) shows its tabs and not its windows. The apps go by the recency of their
    /// windows, so the app that you used last is at the top.
    private func rebuildTabsList() {
        tabEntries = tabs.enumerated().map { PaletteEntry(kind: .tabs, title: $1.title, detail: $1.detail, key: String($0)) }
        let windows = paletteWindows()
        let recent = manager.recent
        let recency = { (id: WindowID) in recent.firstIndex(of: id) ?? Int.max }
        var owners: [String: pid_t?] = [:]
        let ownerOf = { (tab: PaletteTab) -> pid_t? in
            let name: String
            switch tab.source {
            case let .browser(id, _, _): name = id
            case .rex: name = TabReader.rexBundleID
            case let .tmux(session, _): name = "tmux " + session
            }
            if let known = owners[name] { return known }
            let pid = self.owner(of: tab)
            owners[name] = .some(pid)
            return pid
        }
        var tabbed = Set<pid_t>()
        for tab in tabs {
            if case .tmux = tab.source { continue }
            if let pid = ownerOf(tab) { tabbed.insert(pid) }
        }
        var groups: [(rank: Int, entries: [PaletteEntry])] = []
        var index: [pid_t: Int] = [:]
        func add(_ pid: pid_t?, _ entry: PaletteEntry) {
            let key = pid ?? -1
            if let found = index[key] { return groups[found].entries.append(entry) }
            index[key] = groups.count
            groups.append((pid.map { pid in windows.filter { $0.pid == pid }.map { recency($0.id) }.min() ?? Int.max } ?? Int.max, [entry]))
        }
        for (position, tab) in tabs.enumerated() { add(ownerOf(tab), tabEntries[position]) }
        for window in windows.sorted(by: { (recency($0.id), $0.id) < (recency($1.id), $1.id) }) where !tabbed.contains(window.pid) {
            let app = manager.windows[window.id]?.info.appName ?? ""
            add(window.pid, PaletteEntry(kind: .windows, title: window.title, detail: app + " · " + window.place, key: String(window.id)))
        }
        tabsList = groups.enumerated().sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }.flatMap(\.element.entries)
    }

    private func close() {
        holding = nil
        previewTask?.cancel()
        panel.hide()
    }

    private func paletteWindows() -> [PaletteWindow] {
        manager.windows.compactMap { id, window in
            guard !window.isOutOfLayout else { return nil }
            let marks = manager.marks(of: id).map { "mark:" + $0 }
            let place = (["workspace " + window.workspace] + marks).joined(separator: " · ")
            return PaletteWindow(id: id, pid: window.info.pid, title: window.info.title.isEmpty ? window.info.appName : window.info.title, place: place)
        }
    }

    /// The running apps, each followed by its windows. An app with a window that wm manages, but that is not a regular app
    /// (a menu bar app, for example), is listed too.
    private func appEntries() -> [PaletteEntry] {
        var apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            .map { PaletteApp(pid: $0.processIdentifier, name: $0.localizedName ?? "App") }
        for window in manager.windows.values where !apps.contains(where: { $0.pid == window.info.pid }) {
            apps.append(PaletteApp(pid: window.info.pid, name: window.info.appName))
        }
        return paletteAppGroups(apps: apps, windows: paletteWindows(), recent: manager.recent)
    }

    /// Every window, the most recent first, for `palette windows`.
    private func windowEntries() -> [PaletteEntry] {
        let recent = manager.recent
        return paletteWindows().sorted { (recent.firstIndex(of: $0.id) ?? Int.max, $0.id) < (recent.firstIndex(of: $1.id) ?? Int.max, $1.id) }
            .map { PaletteEntry(kind: .windows, title: $0.title, detail: (manager.windows[$0.id]?.info.appName ?? "") + " · " + $0.place, key: String($0.id)) }
    }

    /// A command that needs arguments completes into the field (`fill:`); one that needs none runs (`run:`).
    private func commandEntries() -> [PaletteEntry] {
        commandSpecs.map {
            PaletteEntry(kind: .commands, title: $0.signature, detail: $0.summary, key: ($0.args.isEmpty ? "run:" : "fill:") + $0.path)
        }
    }

    // MARK: - Searching

    private func changed(_ text: String) {
        input = text
        refresh()
    }

    private func refresh() {
        let query = PaletteQuery.parse(input, default: defaultMode)
        var found: [PaletteEntry]
        if query.mode == .commands, let suggestions = argumentEntries(for: query.text) {
            found = suggestions
        } else {
            let source = query.mode == .windows ? flatWindows : query.mode == .tabs ? tabsList : entries + tabEntries + menuEntries
            found = rank(source, query: query)
        }
        // The Cmd+Tab list is the apps only, as in macOS.
        if holding != nil { found = found.filter { $0.kind == .apps } }
        // The tabs of a browser can be many; the list of tabs shows all of them.
        shown = Array(found.prefix(query.mode == .tabs ? 1000 : 50))
        let grouped = query.text.isEmpty && (query.mode == .all || query.mode == .apps)
        // Tab completes a command in the commands list; in the other lists Tab and Shift-Tab cycle the rows.
        panel.cyclesWithTab = query.mode != .commands
        let ofWindows = query.mode == .all || query.mode == .apps || query.mode == .windows
        panel.setRows(shown.map { row(for: $0, indent: grouped && $0.kind == .windows) }, section: sectionTitle(query), preview: ofWindows)
    }

    /// The window that a row stands for: the window itself, or the most recent window of the app.
    private func previewWindow(of entry: PaletteEntry) -> WindowID? {
        switch entry.kind {
        case .windows: return WindowID(entry.key)
        case .apps: return pid_t(entry.key).flatMap(recentWindow(of:))
        default: return nil
        }
    }

    private func recentWindow(of pid: pid_t) -> WindowID? {
        let own = manager.windows.filter { $0.value.info.pid == pid && !$0.value.isOutOfLayout }
        return manager.recent.first { own[$0] != nil } ?? own.keys.sorted().first
    }

    /// Shows the last picture of the window at once, then takes a sharper one. A window of another workspace is parked off
    /// screen; `ThumbnailService` takes its picture there too.
    private func selected(_ row: Int) {
        previewTask?.cancel()
        guard previewsOn, shown.indices.contains(row) else { return }
        guard let id = previewWindow(of: shown[row]), let window = manager.windows[id] else {
            let tab = shown[row].kind == .tabs ? Int(shown[row].key).map { tabs[$0] } : nil
            panel.setPreview(nil, placeholder: shown[row].kind == .apps ? icon(pid: pid_t(shown[row].key)) : tab.flatMap(tabIcon))
            return
        }
        let app = icon(pid: window.info.pid)
        panel.setPreview(previews[id] ?? cachedImage(id), placeholder: app)
        guard !window.isOutOfLayout else { return }
        previewTask = Task { [thumbnails] in
            let captured = await thumbnails.capture([id], maxPixel: 1000)
            guard !Task.isCancelled, isOpen, let image = captured[id] else { return }
            previews[id] = image
            panel.setPreview(image, placeholder: app)
        }
    }

    private func sectionTitle(_ query: PaletteQuery) -> String {
        switch query.mode {
        case .commands: "Commands"
        case .menu: "Menu" + (menuPID.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }.map { " · " + $0 } ?? "")
        case .windows: query.text.isEmpty ? "Windows" : "Results"
        case .tabs: query.text.isEmpty ? "Tabs" : "Results"
        default: holding != nil ? "Apps" : query.text.isEmpty ? "Apps & Windows" : "Results"
        }
    }

    private func icon(pid: pid_t?) -> NSImage? {
        guard let pid else { return nil }
        if let hit = icons[pid] { return hit }
        let image = NSRunningApplication(processIdentifier: pid)?.icon
        icons[pid] = image
        return image
    }

    private func row(for entry: PaletteEntry, indent: Bool) -> PalettePanel.Row {
        switch entry.kind {
        case .apps:
            return .init(title: entry.title, subtitle: entry.detail, accessory: "Application", icon: icon(pid: pid_t(entry.key)), action: "Switch to App")
        case .windows:
            let window = WindowID(entry.key).flatMap { manager.windows[$0] }
            // Under its app the name of the app is not repeated.
            let subtitle = indent ? entry.detail.split(separator: "·").dropFirst().joined(separator: "·").trimmingCharacters(in: .whitespaces) : entry.detail
            return .init(title: entry.title, subtitle: subtitle, accessory: "Window", icon: icon(pid: window?.info.pid), indent: indent, action: "Focus Window")
        case .tabs:
            return .init(title: entry.title, subtitle: entry.detail, accessory: "Tab", icon: Int(entry.key).flatMap { tabIcon(tabs[$0]) }, action: "Switch to Tab")
        case .menu:
            let parts = entry.title.components(separatedBy: " > ")
            return .init(
                title: parts.last ?? entry.title, subtitle: parts.dropLast().joined(separator: " › "), accessory: entry.detail.isEmpty ? "Menu Item" : entry.detail,
                icon: icon(pid: menuPID), action: "Press Menu Item")
        case .commands:
            let words = entry.key.drop { $0 != ":" }.dropFirst().split(separator: " ").map(String.init)
            let fills = entry.key.hasPrefix("fill:")
            return .init(
                title: entry.title, subtitle: entry.detail, accessory: "Command", icon: CommandIcon.image(commandGlyph(for: words)),
                action: fills ? "Complete" : "Run Command", key: fills ? "⇥" : "↵")
        case .all:
            return .init(title: entry.title)
        }
    }

    /// Once the words name a command and a space follows, the palette lists what can come next (workspaces, modes, the
    /// values that the command takes), found the way the shell completion finds them.
    private func argumentEntries(for text: String) -> [PaletteEntry]? {
        let words = text.split(separator: " ").map(String.init)
        guard let first = words.first, commandNames.contains(first), text.contains(" ") else { return nil }
        let typing = text.hasSuffix(" ") ? "" : words.last ?? ""
        let before = text.hasSuffix(" ") ? text : String(text.dropLast(typing.count))
        var source = CompletionSource()
        source.windows = { [manager] in manager.windows.map { LiveWindow(id: $0.key, app: $0.value.info.appName, title: $0.value.info.title) } }
        source.workspaces = { [manager] in manager.workspaces.keys.sorted() }
        source.modes = { [manager] in Array(manager.modeNames).sorted() }
        source.marks = { [manager] in manager.marks.keys.sorted() }
        let query = (text.hasSuffix(" ") ? words : Array(words.dropLast())) + [typing]
        guard case let .candidates(list) = Common.complete(query, source: source) else { return [] }
        return list.filter { $0.word.hasPrefix(typing) && !$0.word.hasPrefix("-") }.map {
            PaletteEntry(kind: .commands, title: before + $0.word, detail: $0.summary ?? "", key: "run:" + before + $0.word)
        }
    }

    // MARK: - Running

    /// Tab: the row goes into the field.
    private func complete(_ row: Int) {
        guard shown.indices.contains(row), shown[row].kind == .commands else { return }
        let key = shown[row].key
        let text = key.hasPrefix("fill:") ? String(key.dropFirst(5)) + " " : String(key.dropFirst(4))
        input = "> " + text
        panel.setText(input)
        refresh()
    }

    private func activate(_ row: Int?) {
        let query = PaletteQuery.parse(input, default: defaultMode)
        guard let row, shown.indices.contains(row) else {
            // Nothing in the list: in the commands list, what was typed is the command.
            if query.mode == .commands, !query.text.isEmpty { execute(query.text.split(separator: " ").map(String.init)) }
            return
        }
        let entry = shown[row]
        switch entry.kind {
        case .windows:
            close()
            if let id = WindowID(entry.key) { manager.focus(id) }
        case .apps:
            close()
            guard let pid = pid_t(entry.key) else { return }
            if let id = recentWindow(of: pid) {
                manager.focus(id)
            } else {
                NSRunningApplication(processIdentifier: pid)?.activate()
            }
        case .tabs:
            close()
            if let index = Int(entry.key), tabs.indices.contains(index) { switchTo(tabs[index]) }
        case .menu:
            close()
            guard let token = Int(entry.key) else { return }
            if let pid = menuPID { NSRunningApplication(processIdentifier: pid)?.activate() }
            let reader = reader
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { reader.press(token: token) }
        case .commands:
            if entry.key.hasPrefix("fill:") { complete(row); return }
            execute(String(entry.key.dropFirst(4)).split(separator: " ").map(String.init))
        case .all:
            break
        }
    }

    // MARK: - Tabs

    /// The icon of the app that shows the tab. A tmux window that no terminal shows gets the drawing of a terminal.
    private func tabIcon(_ tab: PaletteTab) -> NSImage? {
        icon(pid: owner(of: tab)) ?? NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
    }

    /// The app that shows the tab: the browser, Rex, or the terminal of the tmux client that shows the session (else of the
    /// first client). `nil` for tmux without a client.
    private func owner(of tab: PaletteTab) -> pid_t? {
        let bundleID: String
        switch tab.source {
        case let .browser(id, _, _): bundleID = id
        case .rex: bundleID = TabReader.rexBundleID
        case let .tmux(session, _): return tmuxClient(for: session, among: tmuxClients).flatMap { terminal(of: $0.pid) }
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
    }

    /// The program selects the tab, then wm focuses the window that shows it, which also shows the workspace of the window.
    private func switchTo(_ tab: PaletteTab) {
        Task { @MainActor [tabReader] in
            var pid = owner(of: tab)
            switch await tabReader.activate(tab) {
            case .done: break
            case let .client(client): pid = terminal(of: client)
            case let .failed(message): return notify(message)
            }
            guard let pid else { return }
            // The window of a browser has the title of its selected tab, with the name of the browser after it.
            let titled = manager.windows.first { $0.value.info.pid == pid && !tab.title.isEmpty && $0.value.info.title.hasPrefix(tab.title) }?.key
            if let id = titled ?? recentWindow(of: pid) {
                manager.focus(id)
            } else {
                NSRunningApplication(processIdentifier: pid)?.activate()
            }
        }
    }

    /// The app with the terminal of a tmux client: the nearest parent of the client that has a window. The shells of Rex
    /// are children of its server, not of the app, so a parent that is the server stands for Rex.
    private func terminal(of client: pid_t) -> pid_t? {
        for parent in ProcessTree.ancestors(of: client) {
            if manager.windows.values.contains(where: { $0.info.pid == parent }) { return parent }
            if NSRunningApplication(processIdentifier: parent)?.bundleIdentifier?.hasPrefix(TabReader.rexBundleID) == true {
                return NSRunningApplication.runningApplications(withBundleIdentifier: TabReader.rexBundleID).first?.processIdentifier
            }
        }
        return nil
    }

    private func execute(_ words: [String]) {
        close()
        guard !words.isEmpty else { return }
        let answer = run(words)
        if answer.exitCode != 0 { notify(answer.stderr.isEmpty ? "wm: the command failed" : answer.stderr) }
    }
}
