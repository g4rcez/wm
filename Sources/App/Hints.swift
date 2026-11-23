import AppKit
import Core
import Platform

/// `wm hints`: two-letter labels on the clickable elements of the focused window, the menu bar, the menu extras and the Dock, as the
/// flash plugin of Neovim does. `/` starts a search that keeps the labels of the matches. There are two modes. In the click mode
/// typing a label clicks the element. In the wait mode (`--wait`) the search starts at once, a label only highlights the element,
/// and Return clicks it (Shift-Return right-clicks).
@MainActor
final class HintController {
    private enum Phase {
        case closed
        /// The elements are being read. The keys are used up, so they do not go to the app.
        case loading
        case open
        /// A click was made. A second Return in a short time makes it a double click.
        case armed(CGPoint)
    }

    /// The time after a click in which Return clicks again.
    private static let doubleClickWindow: Duration = .milliseconds(300)

    /// `wait`: highlight, and wait for Return.
    private var wait = false
    private let reader = ElementReader()
    private let overlay: HintOverlay
    private let colors: () -> HintSettings
    private var phase = Phase.closed
    private var search = ElementSearch(elements: [])
    private var generation = 0

    /// `colors` gives the colors of the config that is loaded now, so a reload changes them; `look` the place and the style of
    /// the key label.
    init(colors: @escaping () -> HintSettings, look: @escaping () -> LabelLook) {
        self.colors = colors
        overlay = HintOverlay(look: look)
    }

    var isOpen: Bool {
        if case .closed = phase { return false }
        return true
    }

    /// `open`, `close` or `toggle`, in the wait mode or not. Returns an error message, or `nil`.
    func command(_ mode: String, wait: Bool) -> String? {
        switch mode {
        case "close": close()
        case "open": return isOpen ? nil : open(wait: wait)
        default:
            if isOpen { close() } else { return open(wait: wait) }
        }
        return nil
    }

    private func open(wait: Bool) -> String? {
        self.wait = wait
        guard let app = NSWorkspace.shared.frontmostApplication else { return "no app is in front" }
        generation += 1
        let current = generation
        phase = .loading
        let screens = Displays.all().map(\.frame)
        Task { @MainActor in
            let elements = await reader.clickables(pid: app.processIdentifier, screens: screens)
            guard generation == current, case .loading = phase else { return }
            search = ElementSearch(elements: elements, keepsLabels: wait, letters: colors().letters)
            if wait { search.beginSearch() }
            phase = .open
            render()
        }
        return nil
    }

    func close() {
        generation += 1
        phase = .closed
        overlay.hide()
    }

    /// A mouse button went down. A click of the user ends the mode, except right after our own click: the event of that click
    /// comes back through the tap.
    func pointerPressed() {
        if case .armed = phase { return }
        if isOpen { close() }
    }

    /// Handles a key while the mode is on. Returns `true` when the key is used up.
    func handleKey(_ key: String, flags: CGEventFlags) -> Bool {
        switch phase {
        case .closed:
            return false
        case .armed(let point):
            if key == "enter" {
                ElementReader.click(at: point, button: .left, clickState: 2)
                close()
                return true
            }
            close()
            return false
        case .loading:
            if key == "esc" { close() }
            return true
        case .open:
            break
        }
        let shift = flags.contains(.maskShift)
        let control = flags.contains(.maskControl)
        let command = flags.contains(.maskCommand)
        switch key {
        case "esc": close()
        case "tab": step(shift ? -1 : 1)
        case "down": step(1)
        case "up": step(-1)
        case "n" where control: step(1)
        case "p" where control: step(-1)
        case "enter":
            if let target = search.target { click(target, button: shift ? .right : .left, flags: command ? .maskCommand : []) }
        case "backspace":
            search.backspace()
            // The wait mode is always a search: going back from the first letter leaves the text empty, not the search.
            if wait { search.beginSearch() }
            changed()
        default:
            // The second letter of a label can carry Shift (right click) or Cmd (Cmd-click). Any other shortcut is the app's:
            // the mode ends and the app gets it.
            let completing = !search.typed.isEmpty
            if control || flags.contains(.maskAlternate) || (command && !completing) {
                close()
                return false
            }
            if key == "slash", !search.searching, !completing {
                search.beginSearch()
                changed()
            } else if let character = Self.character(key) {
                switch search.press(character) {
                case .picked(let element): click(element, button: shift ? .right : .left, flags: command ? .maskCommand : [])
                case .updated: changed()
                case .ignored: if character != " " { close() }
                }
            } else {
                // A key that is no label, no search text and no command is not accepted: it ends the mode.
                close()
            }
        }
        return true
    }

    private func step(_ direction: Int) {
        search.step(direction)
        render()
    }

    /// The state of the search changed. In the wait mode the first match is highlighted, so that Return has a target.
    private func changed() {
        if wait, search.searching, !search.query.isEmpty, search.focused == nil { search.step(1) }
        render()
    }

    private func click(_ target: HintElement, button: MouseButton, flags: CGEventFlags) {
        let point = CGPoint(x: target.frame.midX, y: target.frame.midY)
        overlay.hide()
        ElementReader.click(at: point, button: button, flags: flags)
        guard button == .left, flags.isEmpty else {
            close()
            return
        }
        generation += 1
        let current = generation
        phase = .armed(point)
        Task { @MainActor in
            try? await Task.sleep(for: Self.doubleClickWindow)
            if generation == current { close() }
        }
    }

    private func render() {
        // The wait mode highlights the element that Return clicks, with a label or without.
        let highlighted = wait ? search.target?.id : search.focused
        // The wait mode shows every label; the elements that the text does not match are dimmed.
        let shown = wait ? search.elements : search.matches
        var badges = shown.compactMap { element -> HintBadge? in
            guard let label = search.label(of: element.id) else { return nil }
            let typed = search.typed
            let dimmed = wait ? !search.query.isEmpty && !search.matches.contains { $0.id == element.id }
                : !typed.isEmpty && !label.hasPrefix(typed)
            return HintBadge(frame: element.frame, label: label, typed: typed.count, dimmed: dimmed, focused: element.id == highlighted)
        }
        if let element = search.matches.first(where: { $0.id == highlighted }), search.label(of: element.id) == nil {
            badges.append(HintBadge(frame: element.frame, label: "", focused: true))
        }
        let note: LabelContent
        if search.elements.isEmpty {
            note = LabelContent(badge: "hints", entries: [LabelEntry(key: "esc", text: "nothing to click here")])
        } else if search.searching {
            var entries = [LabelEntry(key: "ab", text: search.query.isEmpty ? "label or title" : "label")]
            if wait { entries += [LabelEntry(key: "⏎", text: "click"), LabelEntry(key: "⇧⏎", text: "right click")] }
            entries += [LabelEntry(key: "⌫", text: "back"), LabelEntry(key: "esc", text: "close")]
            let found = search.query.isEmpty ? "" : " /\(search.query) · \(search.matches.count)"
            note = LabelContent(badge: "hints" + found, entries: entries)
        } else {
            note = LabelContent(badge: "hints", entries: [
                LabelEntry(key: "ab", text: "click"), LabelEntry(key: "/", text: "search"), LabelEntry(key: "esc", text: "close"),
            ])
        }
        overlay.show(HintContent(badges: badges, note: note, noteAnchor: CGEvent(source: nil)?.location ?? .zero, colors: colors()))
    }

    /// The character that a key types, or `nil` for a key that is not text.
    static func character(_ key: String) -> String? {
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
}
