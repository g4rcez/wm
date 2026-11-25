import Common
import Core
import Foundation
import Platform

/// A named copy of the saved state, for `session open`.
struct SessionFile: Codable {
    static let currentVersion = 1

    var version = currentVersion
    var savedAt: Date
    var state: SavedState
    /// Where the floating windows were, as parts of the work area, by the id they had: the monitor may have another size.
    var frames: [String: RelativeFrame]
}

enum SessionStore {
    static var directory: URL { StateStore.url.deletingLastPathComponent().appendingPathComponent("sessions") }

    static func url(_ name: String) -> URL { directory.appendingPathComponent(name + ".json") }

    static func names() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.filter(isValidSessionName).sorted()
    }

    static func load(_ name: String) throws -> SessionFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SessionFile.self, from: Data(contentsOf: url(name)))
    }

    static func write(_ file: SessionFile, as name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try StateStore.write(encoder.encode(file), to: url(name))
    }
}

private struct SessionSummary: Encodable {
    var name: String
    var savedAt: String
    var windows: Int
    var workspaces: [String]
}

/// `session save`, `open`, `list` and `delete`.
extension WindowManager {
    func sessionCommand(_ words: [String], _ flags: Set<String>) -> ServerAnswer {
        let sub = words.first ?? "list"
        guard ["save", "open", "list", "delete"].contains(sub) else {
            return fail("unknown session command '\(sub)'", 2, usage: "session")
        }
        let allowed: Set<String> = sub == "open" ? ["--no-launch"] : sub == "list" ? ["--json"] : []
        if let bad = unknownOption(flags, allowed: allowed, usage: "session " + sub) { return bad }
        if sub == "list" {
            if words.count > 1 { return fail("session list takes no arguments", 2, usage: "session list") }
            return listSessions(json: flags.contains("--json"))
        }
        guard words.count == 2 else { return fail("session \(sub) needs one name", 2, usage: "session " + sub) }
        let name = words[1]
        guard isValidSessionName(name) else {
            return fail("'\(name)' is not a session name", 2, usage: "session " + sub, hint: "letters, digits, `.`, `_` and `-`, up to 64")
        }
        if sub == "save" { return saveSession(name) }
        guard FileManager.default.fileExists(atPath: SessionStore.url(name).path) else {
            return fail("there is no session '\(name)'", 1, hint: "see `wm session list`")
        }
        if sub == "open" { return openSession(name, launch: !flags.contains("--no-launch")) }
        do { try FileManager.default.removeItem(at: SessionStore.url(name)) } catch {
            return fail("cannot delete the session '\(name)': \(error.localizedDescription)")
        }
        return ok("deleted \(name)\n")
    }

    private func listSessions(json: Bool) -> ServerAnswer {
        let formatter = ISO8601DateFormatter()
        let summaries = SessionStore.names().compactMap { name -> SessionSummary? in
            guard let file = try? SessionStore.load(name) else { return nil }
            return SessionSummary(
                name: name, savedAt: formatter.string(from: file.savedAt), windows: file.state.windows.count,
                workspaces: file.state.workspaces.keys.sorted())
        }
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(summaries) else { return fail("cannot write the list") }
            return ok(String(decoding: data, as: UTF8.self) + "\n")
        }
        guard !summaries.isEmpty else { return ok("there are no sessions\n") }
        return ok(summaries.map {
            "\($0.name)  \($0.windows) \($0.windows == 1 ? "window" : "windows")  workspaces \($0.workspaces.joined(separator: " "))  saved \($0.savedAt)\n"
        }.joined())
    }

    private func saveSession(_ name: String) -> ServerAnswer {
        // The layouts hold places for windows that have not opened yet.
        guard !isRestoring else { return fail("wm is still restoring windows", 1, hint: "try again in a moment") }
        var state = snapshot()
        state.windows.removeAll { windows[$0.id]?.isOutOfLayout != false }
        guard !state.windows.isEmpty else { return fail("there is no window to save") }
        let used = Set(state.windows.map(\.workspace))
        state.workspaces = state.workspaces.filter { used.contains($0.key) }
        var frames: [String: RelativeFrame] = [:]
        for window in state.windows where window.floating {
            guard let frame = window.floatFrame ?? currentFrame(of: window.id),
                  let area = (monitor(showing: window.workspace) ?? focusedMonitor)?.workArea else { continue }
            frames[String(window.id)] = WindowMemory.relative(frame, in: area)
        }
        do { try SessionStore.write(SessionFile(savedAt: Date(), state: state, frames: frames), as: name) } catch {
            return fail("cannot save the session '\(name)': \(error.localizedDescription)")
        }
        return ok("saved \(name): \(state.windows.count) \(state.windows.count == 1 ? "window" : "windows")\n")
    }

    private func openSession(_ name: String, launch: Bool) -> ServerAnswer {
        guard !isRestoring else { return fail("wm is still restoring windows", 1, hint: "try again in a moment") }
        let file: SessionFile
        do { file = try SessionStore.load(name) } catch { return fail("cannot read the session '\(name)': \(error.localizedDescription)") }
        let saved = file.state
        guard file.version == SessionFile.currentVersion, saved.version == SavedState.currentVersion else {
            return fail("the session '\(name)' is from another version of wm", 1, hint: "save it again")
        }
        guard saved.mode == settings.workspaceMode.rawValue else {
            return fail("the session '\(name)' was saved with workspaces = \"\(saved.mode)\"", 1, hint: "save it again")
        }

        // Which monitor shows each saved workspace now: the one with the saved name, else with the saved id.
        var shown: [(workspace: String, monitor: Monitor)] = []
        for (key, workspace) in saved.monitors.sorted(by: { $0.key < $1.key }) where saved.workspaces[workspace] != nil {
            let monitor = monitors.first { $0.name == saved.monitorNames?[key] && !shown.map(\.monitor.id).contains($0.id) }
                ?? monitors.first { String($0.id) == key }
            if let monitor { shown.append((workspace, monitor)) }
        }
        var entries = saved.windows
        for (index, entry) in entries.enumerated() {
            guard let relative = file.frames[String(entry.id)],
                  let area = (shown.first { $0.workspace == entry.workspace }?.monitor ?? monitor(showing: entry.workspace) ?? focusedMonitor)?.workArea
            else { continue }
            entries[index].floatFrame = WindowMemory.absolute(relative, in: area)
        }

        let candidates = entries.enumerated().map {
            RestoreCandidate(key: $0.offset, bundleID: $0.element.bundleID, title: $0.element.title ?? "", order: $0.element.order ?? $0.offset)
        }
        let open = windows.filter { !$0.value.isOutOfLayout }.map { OpenWindow(id: $0.key, bundleID: $0.value.info.bundleID, title: $0.value.info.title) }
        let matches = matchOpenWindows(open, to: candidates)
        var mapping: [WindowID: WindowID] = [:]
        for entry in entries { mapping[entry.id] = Placeholder.id(for: entry.id) }
        for (id, key) in matches { mapping[entries[key].id] = id }

        for (id, key) in matches.sorted(by: { $0.value < $1.value }) {
            let entry = entries[key]
            setSticky(id, false)
            moveWindow(id, to: entry.workspace)
            setFloating(id, entry.floating)
            if entry.floating, let frame = entry.floatFrame { setFloatFrame(id, frame) }
            if entry.sticky == true { setSticky(id, true) }
            for mark in entry.marks ?? [] { setMark(mark, on: id) }
        }
        for (workspaceName, savedSpace) in saved.workspaces { arrange(workspaceName, as: savedSpace, mapping: mapping) }

        let taken = Set(matches.values)
        let waiting = entries.enumerated().filter { !taken.contains($0.offset) }.map(\.element)
        var launched = 0
        events.emit("session_open", ["name": .string(name), "matched": .number(Double(matches.count)), "waiting": .number(Double(waiting.count))])
        beginSessionRestore(name, waiting: waiting)
        if launch {
            let running = Set(windows.values.map(\.info.bundleID))
            for app in Set(waiting.map(\.bundleID)).subtracting(running).sorted() where !app.isEmpty {
                if AppLauncher.launch(app) { launched += 1 } else { Log.write(.warn, "cannot find the app \(app)", source: "session") }
            }
        }
        for (workspace, monitor) in shown { showWorkspace(workspace, on: monitor.id, focusWindow: false) }
        relayout()
        if let focus = focusedWorkspace?.history.first(where: { windows[$0] != nil }) { self.focus(focus, warpMouse: false) }
        var line = "opening \(name): \(matches.count) placed"
        if !waiting.isEmpty { line += ", \(waiting.count) waiting" }
        if launched > 0 { line += ", \(launched) \(launched == 1 ? "app" : "apps") started" }
        return ok(line + "\n")
    }

    /// Gives a workspace the saved layout. Windows that are on it and not in the session join after the saved ones.
    private func arrange(_ name: String, as saved: SavedWorkspace, mapping: [WindowID: WindowID]) {
        let space = workspace(name)
        var engine = makeEngine(restoring: saved.layout, settings: settings(forWorkspace: name))
        engine.relabel(mapping)
        for id in space.engine.windows where !engine.windows.contains(id) { engine.insert(id, after: engine.windows.last) }
        space.kind = saved.layout.kind
        space.engine = engine
        let history = saved.history.compactMap { mapping[$0] }
        space.history = history + space.history.filter { !history.contains($0) }
        space.maximized = Set(saved.maximized.compactMap { mapping[$0] })
        space.fullscreen = saved.fullscreen.flatMap { mapping[$0] }
        layoutHistory.forget(name)
        events.emit("layout_changed", ["workspace": .string(name), "layout": .string(space.kind.rawValue)])
    }
}
