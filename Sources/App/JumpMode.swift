import AppKit
import Core
import Platform

/// What `wm jump` does with the window that you pick.
enum JumpAction {
    case focus, swap, close
}

/// `wm jump`: a giant number in the middle of every visible window; typing a number picks that window.
@MainActor
final class JumpController {
    private let overlay = HintOverlay()
    private let colors: () -> HintSettings
    /// The visible windows with their frames, the focused one, and the displays.
    private let windows: () -> (frames: [WindowID: CGRect], focused: WindowID?, displays: [CGRect])
    private let choose: (WindowID, JumpAction) -> Void
    private var numbers: WindowNumbers?
    private var action = JumpAction.focus
    private var focused: WindowID?

    init(
        colors: @escaping () -> HintSettings, windows: @escaping () -> (frames: [WindowID: CGRect], focused: WindowID?, displays: [CGRect]),
        choose: @escaping (WindowID, JumpAction) -> Void
    ) {
        self.colors = colors
        self.windows = windows
        self.choose = choose
    }

    var isOpen: Bool { numbers != nil }

    /// `open`, `close` or `toggle`. Returns an error message, or `nil`.
    func command(_ mode: String, action: JumpAction) -> String? {
        switch mode {
        case "close": close()
        case "open": return isOpen ? nil : open(action)
        default:
            if isOpen { close() } else { return open(action) }
        }
        return nil
    }

    private func open(_ action: JumpAction) -> String? {
        let visible = windows()
        guard !visible.frames.isEmpty else { return "there is no window to jump to" }
        self.action = action
        focused = visible.focused
        numbers = WindowNumbers(frames: visible.frames, displays: visible.displays)
        render(visible.frames)
        return nil
    }

    func close() {
        guard numbers != nil else { return }
        numbers = nil
        overlay.hide()
    }

    /// A click of the user ends the mode.
    func pointerPressed() {
        if isOpen { close() }
    }

    /// Handles a key while the mode is on. Returns `true` when the key is used up.
    func handleKey(_ key: String, flags: CGEventFlags) -> Bool {
        guard var current = numbers else { return false }
        let shortcut = !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty
        let result: WindowNumbers.Result
        switch key {
        case "esc":
            close()
            return true
        case "enter":
            result = current.confirm()
        case "backspace":
            current.deleteLast()
            result = .pending
        default:
            result = shortcut ? .ignored : current.press(key)
        }
        switch result {
        case .ignored:
            // A shortcut of the app ends the mode and goes on to the app; so does any other key, but it is not passed on.
            close()
            return !shortcut
        case .pending:
            numbers = current
            render(windows().frames)
        case .pick(let id):
            close()
            choose(id, action)
        }
        return true
    }

    private func render(_ frames: [WindowID: CGRect]) {
        guard let numbers else { return }
        let labels = frames.compactMap { id, frame in
            numbers.label(of: id).map {
                WindowLabel(frame: frame, text: $0, focused: id == focused, dimmed: !numbers.matches(id))
            }
        }
        overlay.show(HintContent(windowLabels: labels, colors: colors()))
    }
}
