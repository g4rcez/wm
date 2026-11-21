import AppKit
import Cheatsheet
import Core
import Platform
import SwiftUI

/// The panel of `wm cheatsheet gui`: the keys of the config over the screen, with a filter that you type. It takes the keyboard
/// without making wm the active app (as the palette does), so the app that you came from stays in front. The router lets every
/// key through while it is open, and the panel reads them itself.
@MainActor
final class CheatsheetController: NSObject, NSWindowDelegate {
    private final class KeyPanel: NSPanel {
        var onKey: ((NSEvent) -> Void)?

        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }

        override func sendEvent(_ event: NSEvent) {
            if event.type == .keyDown, let onKey {
                onKey(event)
                return
            }
            super.sendEvent(event)
        }
    }

    private var panel: KeyPanel?
    private var model: CheatsheetModel?

    var isOpen: Bool { panel?.isVisible == true }

    /// The router calls this for a key while the panel is open. The panel is the key window, so every key goes through to it.
    func handleKey(_ key: String, flags: CGEventFlags) -> Bool { false }

    /// Opens the panel on the page of `mode`, or closes it when it is open already.
    func toggle(binds: [CheatBind], mode: String, style: ResolvedStyle) {
        if isOpen { return close() }
        let sheet = buildCheatsheet(binds)
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let theme = Theme(style)
        let width = min(area.width - 80, CGFloat(style.cheatsheetWidth))
        let columns = CheatsheetMetrics.columns(forWidth: width)
        let content = CheatsheetMetrics.contentHeight(sheet, columns: columns, rowHeight: CheatsheetMetrics.rowHeight(style))
        let height = min(max(CheatsheetMetrics.headerHeight + content + CheatsheetMetrics.padding(style) * 2 + 8, 300), area.height * 0.88)
        let model = CheatsheetModel(sheet: sheet, page: sheet.pageIndex(of: mode), size: CGSize(width: width, height: height), theme: theme)
        self.model = model

        let panel = makePanel(model: model, theme: theme)
        self.panel = panel
        panel.setFrame(NSRect(x: area.midX - width / 2, y: area.midY - height / 2 + min(40, area.height * 0.04), width: width, height: height), display: true)
        if theme.duration > 0 {
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = theme.duration
                panel.animator().alphaValue = 1
            }
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        panel.onKey = nil
        panel.orderOut(nil)
        self.panel = nil
        model = nil
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    // MARK: Building

    private func makePanel(model: CheatsheetModel, theme: Theme) -> KeyPanel {
        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = theme.style.shadow
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.onKey = { [weak self] event in self?.key(event) }

        let background = NSVisualEffectView()
        theme.configure(background)
        background.wantsLayer = true
        background.layer?.cornerRadius = theme.cornerRadius
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = CGFloat(theme.style.borderWidth)
        background.layer?.borderColor = theme.cg(theme.separator)
        if let tint = theme.tint {
            let layer = NSView()
            layer.wantsLayer = true
            layer.layer?.backgroundColor = tint.cgColor
            layer.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(layer)
            NSLayoutConstraint.activate([
                layer.leadingAnchor.constraint(equalTo: background.leadingAnchor), layer.trailingAnchor.constraint(equalTo: background.trailingAnchor),
                layer.topAnchor.constraint(equalTo: background.topAnchor), layer.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            ])
        }

        let hosting = NSHostingView(rootView: CheatsheetView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
        return panel
    }

    /// Escape clears the filter, and closes the panel when there is none. ← and → (or Tab) change the mode; other keys type.
    private func key(_ event: NSEvent) {
        guard let model else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            if event.charactersIgnoringModifiers == "w" { close() }
            return
        }
        switch event.keyCode {
        case 53:
            if model.query.isEmpty { close() } else { model.query = "" }
        case 123: model.move(-1)
        case 124: model.move(1)
        case 48: model.move(flags.contains(.shift) ? -1 : 1)
        case 51: if !model.query.isEmpty { model.query.removeLast() }
        case 117: model.query = ""
        default:
            guard !flags.contains(.control), let text = event.characters else { return }
            let typed = text.filter { !$0.isNewline && !($0.unicodeScalars.first.map { $0.value < 0x20 || (0xF700...0xF8FF).contains($0.value) } ?? false) }
            if !typed.isEmpty { model.query += typed }
        }
    }
}
