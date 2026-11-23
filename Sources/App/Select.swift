import AppKit
import Common
import Core
import Platform

/// `wm select`: finds a text on the screen and selects it with the keyboard, then copies it or right-clicks on it.
///
/// The mode has two steps. In the search step every key is text: the places of the text are highlighted, and Return takes the
/// focused one. In the select step every key is a command: the vim keys move the cursor, `v` extends the selection, and the
/// two letters of a label take the selection to a match. `y` or Return copies; Shift-Return right-clicks.
@MainActor
final class SelectController {
    private enum Phase {
        case closed
        /// The screen is being read. The text keys are kept for the search.
        case loading
        case search
        case select
    }

    private let reader = ElementReader()
    private let overlay: HintOverlay
    private let colors: () -> HintSettings
    private let keys: () -> SelectSettings
    private let pictures = ThumbnailService()
    /// The display to read: the one with the focused window.
    private let display: () -> (id: UInt32, frame: CGRect)?
    private let notify: (String) -> Void
    private var phase = Phase.closed
    private var generation = 0
    private var page = TextPage(words: [])
    private var anchor = CGPoint.zero
    private var query = ""
    private var matches: [TextMatch] = []
    private var labels: [Int: String] = [:]
    /// The match that Return takes, as an index into `matches`.
    private var focused = 0
    /// The first letter of a label, while the second one is not typed.
    private var typed = ""
    private var selection: TextSelection?
    /// Some windows have their text in pixels, and wm cannot take a picture of the screen.
    private var cannotSee = false

    init(
        colors: @escaping () -> HintSettings, keys: @escaping () -> SelectSettings, look: @escaping () -> LabelLook,
        display: @escaping () -> (id: UInt32, frame: CGRect)?, notify: @escaping (String) -> Void) {
        overlay = HintOverlay(look: look)
        self.colors = colors
        self.keys = keys
        self.display = display
        self.notify = notify
    }

    var isOpen: Bool {
        if case .closed = phase { return false }
        return true
    }

    /// `open`, `close` or `toggle`. Returns an error message, or `nil`.
    func command(_ mode: String) -> String? {
        switch mode {
        case "close": close()
        case "open": return isOpen ? nil : open()
        default:
            if isOpen { close() } else { return open() }
        }
        return nil
    }

    private func open() -> String? {
        guard let (id, frame) = display() else { return "there is no monitor" }
        generation += 1
        let current = generation
        phase = .loading
        page = TextPage(words: [])
        anchor = CGPoint(x: frame.midX, y: frame.midY)
        query = ""
        refresh()
        Task { @MainActor in
            let start = ContinuousClock.now
            let text = await reader.text(on: frame)
            Log.write(.debug, "accessibility: \(text.words.count) words of \(text.windows.count) windows in \(ContinuousClock.now - start)", source: "select")
            guard generation == current, case .loading = phase else {
                Log.write(.debug, "dropped after the accessibility read: the mode was closed or opened again", source: "select")
                return
            }
            var words = text.words
            // A window that gives few words has its text in pixels: the OCR reads its part of a picture of the display.
            let counts = Dictionary(grouping: words, by: \.window).mapValues(\.count)
            let poor = text.windows.indices.filter { TextPage.needsOCR(wordCount: counts[$0] ?? 0) }
            cannotSee = false
            if !poor.isEmpty {
                Log.write(.debug, "OCR for windows \(poor) of \(text.windows.count)", source: "select")
                let image = await pictures.captureDisplay(id)
                Log.write(.debug, "display picture: \(image == nil ? "none" : "ok") at \(ContinuousClock.now - start)", source: "select")
                if let image {
                    let read = await TextRecognizer.words(in: image, display: frame, windows: poor.map { ($0, text.windows[$0]) })
                    Log.write(.debug, "OCR: \(read.count) words at \(ContinuousClock.now - start)", source: "select")
                    let recognized = Set(read.map(\.window))
                    words.removeAll { recognized.contains($0.window) }
                    words += read
                } else {
                    cannotSee = true
                    ThumbnailService.requestOnce()
                }
                guard generation == current, case .loading = phase else {
                    Log.write(.debug, "dropped after the OCR: the mode was closed or opened again", source: "select")
                    return
                }
            }
            page = TextPage(words: words, windows: text.windows)
            Log.write(
                .info, "\(page.words.count) words of \(text.windows.count) windows (\(poor.count) by OCR) in \(ContinuousClock.now - start)",
                source: "select")
            phase = .search
            refresh()
        }
        return nil
    }

    func close() {
        generation += 1
        phase = .closed
        selection = nil
        overlay.hide()
    }

    /// A mouse button went down: a click of the user ends the mode.
    func pointerPressed() {
        if isOpen { close() }
    }

    /// Handles a key while the mode is on. Returns `true` when the key is used up.
    func handleKey(_ key: String, flags: CGEventFlags) -> Bool {
        switch phase {
        case .closed: return false
        case .loading, .search: return searchKey(key, flags: flags)
        case .select: return selectKey(key, flags: flags)
        }
    }

    private func searchKey(_ key: String, flags: CGEventFlags) -> Bool {
        let shift = flags.contains(.maskShift)
        let control = flags.contains(.maskControl)
        switch key {
        case "esc": close()
        case "tab": step(shift ? -1 : 1)
        case "down": step(1)
        case "up": step(-1)
        case "n" where control: step(1)
        case "p" where control: step(-1)
        case "enter":
            guard matches.indices.contains(focused) else { break }
            selection = TextSelection(matches[focused])
            phase = .select
            render()
        case "backspace":
            if !query.isEmpty { query.removeLast() }
            refresh()
        default:
            // Any other shortcut is the app's: the mode ends and the app gets it.
            if control || flags.contains(.maskAlternate) || flags.contains(.maskCommand) {
                close()
                return false
            }
            // The text does not start with a space, and a space is not repeated.
            guard let character = HintController.character(key) else {
                close()
                break
            }
            guard character != " " || !(query.isEmpty || query.hasSuffix(" ")) else { break }
            query += character
            refresh()
        }
        return true
    }

    private func selectKey(_ key: String, flags: CGEventFlags) -> Bool {
        if key == "esc" {
            close()
            return true
        }
        // The second letter of a label. A letter that completes no label cancels the first one.
        if !typed.isEmpty {
            let label = typed + key
            typed = ""
            if let id = labels.first(where: { $0.value == label })?.key, matches.indices.contains(id) { selection?.jump(to: matches[id]) }
            render()
            return true
        }
        let command = flags.contains(.maskCommand), control = flags.contains(.maskControl), option = flags.contains(.maskAlternate)
        let chord = SelectSettings.chordName(key: key, control: control, option: option, shift: flags.contains(.maskShift), command: command)
        if let action = keys().actions[chord] {
            run(action)
            return true
        }
        // Any other shortcut is the app's: the mode ends and the app gets it.
        if command || control || option {
            close()
            return false
        }
        if labels.values.contains(where: { $0.hasPrefix(key) }) {
            typed = key
            render()
        } else {
            // Not a label, not a command: the mode does not accept the key, and it ends.
            close()
        }
        return true
    }

    private func run(_ action: SelectAction) {
        switch action {
        case .copy: copy()
        case .rightClick: rightClick()
        case .search:
            selection = nil
            phase = .search
            render()
        case .extend:
            selection?.toggleExtend()
            render()
        case .expand:
            selection?.expand(in: page)
            render()
        case .left: move(.left)
        case .right: move(.right)
        case .down: move(.down)
        case .up: move(.up)
        case .nextWord: move(.nextWord)
        case .previousWord: move(.previousWord)
        case .wordEnd: move(.wordEnd)
        case .lineStart: move(.lineStart)
        case .lineEnd: move(.lineEnd)
        }
    }

    /// A chord of the settings as the note shows it: `shift-enter` is `⇧⏎`.
    private func shown(_ action: SelectAction) -> String {
        guard var text = keys().keys[action]?.first else { return "" }
        for (name, symbol) in [("ctrl-", "⌃"), ("alt-", "⌥"), ("shift-", "⇧"), ("cmd-", "⌘")] { text = text.replacingOccurrences(of: name, with: symbol) }
        for (name, symbol) in [("enter", "⏎"), ("slash", "/"), ("backspace", "⌫"), ("space", "␣")] where text.hasSuffix(name) {
            text = String(text.dropLast(name.count)) + symbol
        }
        return text
    }

    private func step(_ direction: Int) {
        guard !matches.isEmpty else { return }
        focused = (focused + direction + matches.count) % matches.count
        render()
    }

    private func move(_ motion: TextMotion) {
        selection?.move(motion, in: page)
        render()
    }

    private func copy() {
        guard let text = selection?.text(in: page) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        close()
        notify("Copied")
    }

    private func rightClick() {
        guard let point = selection?.clickPoint(in: page) else { return }
        close()
        ElementReader.click(at: point, button: .right)
    }

    /// The text of the search changed, or the page did.
    private func refresh() {
        matches = page.matches(query)
        labels = page.labels(for: matches, avoiding: keys().reservedLetters)
        focused = 0
        typed = ""
        render()
    }

    private func render() {
        var content = HintContent(noteAnchor: anchor, colors: colors())
        switch phase {
        case .closed:
            return
        case .loading:
            content.note = LabelContent(text: "Reading the screen…" + (query.isEmpty ? "" : " · \(query)"))
        case .search:
            // Without a text every word is a match: only the focused one is shown then.
            if !query.isEmpty { content.matches = matches.map(\.frame) }
            if matches.indices.contains(focused) { content.badges = [HintBadge(frame: matches[focused].frame, label: "", focused: true)] }
            let found = query.isEmpty ? "" : matches.isEmpty ? " \(query) · not found" : " \(query) · \(focused + 1)/\(matches.count)"
            var entries = page.words.isEmpty ? [LabelEntry(key: "esc", text: "no text here")]
                : [LabelEntry(key: "abc", text: "search"), LabelEntry(key: "⏎", text: "select"), LabelEntry(key: "⇥", text: "next"),
                   LabelEntry(key: "esc", text: "close")]
            if cannotSee { entries.append(LabelEntry(key: "!", text: "Screen Recording is off: some windows are not read")) }
            content.note = LabelContent(badge: "select" + found, entries: entries)
        case .select:
            content.selection = selection?.rects(in: page) ?? []
            content.badges = matches.compactMap { match in
                guard let label = labels[match.id] else { return nil }
                return HintBadge(frame: match.frame, label: label, typed: typed.count, dimmed: !typed.isEmpty && !label.hasPrefix(typed))
            }
            let moves = [SelectAction.left, .down, .up, .right].map(shown).filter { !$0.isEmpty }.joined(separator: " ")
            let words = [SelectAction.nextWord, .previousWord, .wordEnd].map(shown).filter { !$0.isEmpty }.joined(separator: " ")
            var entries = [(moves, "move"), (words, "word")].filter { !$0.0.isEmpty }.map { LabelEntry(key: $0.0, text: $0.1) }
            entries += [(SelectAction.copy, "copy"), (.rightClick, "right click"), (.extend, "extend"), (.expand, "grow"), (.search, "search")]
                .compactMap { action, name in shown(action).isEmpty ? nil : LabelEntry(key: shown(action), text: name) }
            entries.append(LabelEntry(key: "esc", text: "close"))
            content.note = LabelContent(badge: selection?.extend == true ? "visual" : "select", entries: entries)
        }
        overlay.show(content)
    }
}
