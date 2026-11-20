import AppKit
import Core
import Platform

/// `wm scroll`: numbers the scroll areas of the focused window and scrolls the active one with vim keys.
@MainActor
final class ScrollController {
    /// How far `gg` and `G` scroll in one event: more than any page.
    private static let extreme = 200_000.0

    private let reader = ElementReader()
    private let overlay = HintOverlay()
    private let colors: () -> HintSettings
    private var areas: ScrollAreas?
    private var keys = ScrollKeys()
    private var loading = false
    private var generation = 0

    /// `colors` gives the colors of the config that is loaded now, so a reload changes them.
    init(colors: @escaping () -> HintSettings) { self.colors = colors }

    var isOpen: Bool { loading || areas != nil }

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
        guard let app = NSWorkspace.shared.frontmostApplication else { return "no app is in front" }
        generation += 1
        let current = generation
        loading = true
        keys = ScrollKeys(step: colors().scrollStep, dashFactor: colors().scrollDashFactor)
        Task { @MainActor in
            let target = await reader.scrollTarget(pid: app.processIdentifier)
            guard generation == current, loading else { return }
            loading = false
            guard let target else {
                close()
                return
            }
            areas = ScrollAreas(frames: target.areas, fallback: target.window)
            activeChanged()
        }
        return nil
    }

    func close() {
        generation += 1
        loading = false
        areas = nil
        overlay.hide()
    }

    /// A click of the user ends the mode.
    func pointerPressed() {
        if isOpen { close() }
    }

    /// Handles a key while the mode is on. Returns `true` when the key is used up.
    func handleKey(_ key: String, flags: CGEventFlags) -> Bool {
        guard isOpen else { return false }
        guard var current = areas else {
            if key == "esc" { close() }
            return true
        }
        let action = keys.press(key, shift: flags.contains(.maskShift), control: flags.contains(.maskControl))
        switch action {
        case .pending:
            break
        case .ignored:
            // A shortcut of the app ends the mode and goes on to the app. Other keys are not for the app either, but they
            // end the mode as well: a key that the mode does not accept must not leave it stuck.
            let shortcut = !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty
            close()
            return !shortcut
        case .exit:
            close()
        case .by(let dx, let dy):
            scroll(current, dx: dx, dy: dy)
        case .halfPage(let direction):
            scroll(current, dx: 0, dy: Double(direction) * current.current.height / 2)
        case .top:
            scroll(current, dx: 0, dy: -Self.extreme)
        case .bottom:
            scroll(current, dx: 0, dy: Self.extreme)
        case .nextArea:
            current.step(1)
            areas = current
            activeChanged()
        case .previousArea:
            current.step(-1)
            areas = current
            activeChanged()
        case .area(let number):
            current.select(number)
            areas = current
            activeChanged()
        }
        return true
    }

    private func scroll(_ areas: ScrollAreas, dx: Double, dy: Double) {
        let frame = areas.current
        ElementReader.scroll(at: CGPoint(x: frame.midX, y: frame.midY), dx: dx, dy: dy)
    }

    /// The pointer goes to the active area: scroll events reach the view under it.
    private func activeChanged() {
        guard let areas else { return }
        let frame = areas.current
        let center = CGPoint(x: frame.midX, y: frame.midY)
        CGWarpMouseCursorPosition(center)
        overlay.show(HintContent(
            areas: areas.frames.enumerated().map { AreaBadge(frame: $1, number: $0, active: $0 == areas.active) },
            note: "Scroll · h j k l · ⇧ dash · d u · gg G · Tab area · Esc", noteAnchor: center,
            colors: colors()))
    }
}
