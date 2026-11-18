import AppKit
import ApplicationServices
import Common

/// The setup window. It shows the permissions, offers a starter config when there is none, and has the Start button that
/// lets wm manage windows. The status refreshes each second, because the user grants the permissions in System Settings.
@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    private let configURL: URL
    private let onStart: () -> Void
    private var window: NSWindow?
    private var timer: Timer?
    /// `true` the first time: Start is what lets wm manage windows. Later the window is only a place to look at the setup.
    private var gated = true

    private let accessibilityStatus = NSTextField(labelWithString: "")
    private let screenStatus = NSTextField(labelWithString: "")
    private let configStatus = NSTextField(wrappingLabelWithString: "")
    private let presetPopup = NSPopUpButton()
    private let modPopup = NSPopUpButton()
    private let writeButton = NSButton()
    private let startButton = NSButton()
    private let accessibilityGrant = NSButton()
    private let screenGrant = NSButton()
    private var stack: NSStackView?

    init(configURL: URL, onStart: @escaping () -> Void) {
        self.configURL = configURL
        self.onStart = onStart
        super.init()
    }

    func show(gated: Bool) {
        self.gated = gated
        if window == nil { build() }
        startButton.title = gated ? "Start managing windows" : "Done"
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Build

    private func build() {
        let title = NSTextField(labelWithString: "Set up wm")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let intro = NSTextField(wrappingLabelWithString: "wm moves your windows only after you press Start. Grant the permissions first; the starter config is optional.")
        intro.textColor = .secondaryLabelColor

        for (button, action) in [(accessibilityGrant, #selector(grantAccessibility)), (screenGrant, #selector(grantScreenRecording))] {
            button.title = "Grant…"
            button.bezelStyle = .rounded
            button.target = self
            button.action = action
        }

        presetPopup.addItems(withTitles: InitTemplate.allCases.map(\.rawValue))
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged)
        presetPopup.setAccessibilityLabel("Starter config")
        modPopup.addItems(withTitles: initModKeys)
        modPopup.setAccessibilityLabel("Main modifier key")
        modPopup.selectItem(withTitle: InitTemplate.allCases[0].defaultMod)
        writeButton.title = "Write config"
        writeButton.bezelStyle = .rounded
        writeButton.target = self
        writeButton.action = #selector(writeConfig)
        let presetRow = NSStackView(views: [NSTextField(labelWithString: "Binds like"), presetPopup, NSTextField(labelWithString: "with"), modPopup, writeButton])
        presetRow.spacing = 8

        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"
        startButton.target = self
        startButton.action = #selector(start)

        let stack = NSStackView(views: [
            title, intro,
            row("Accessibility", "Required: wm moves windows and reads keys with it.", accessibilityStatus, accessibilityGrant),
            row("Screen Recording", "Optional: only for the thumbnails of the switcher and the overview.", screenStatus, screenGrant),
            NSTextField(labelWithString: "Config").withFont(.systemFont(ofSize: 13, weight: .semibold)),
            configStatus, presetRow,
            startButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.setCustomSpacing(22, after: configStatus)
        stack.setCustomSpacing(22, after: presetRow)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 540).isActive = true
        intro.preferredMaxLayoutWidth = 492
        configStatus.preferredMaxLayoutWidth = 492
        self.stack = stack

        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "wm setup"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        window.contentView = stack
        self.window = window
    }

    /// A name, a sentence under it, and on the right the status and a Grant button.
    private func row(_ name: String, _ note: String, _ status: NSTextField, _ button: NSButton) -> NSView {
        let label = NSTextField(labelWithString: name).withFont(.systemFont(ofSize: 13, weight: .semibold))
        let detail = NSTextField(wrappingLabelWithString: note)
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: 12)
        detail.preferredMaxLayoutWidth = 330
        let text = NSStackView(views: [label, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        status.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [text, NSView(), status, button])
        row.alignment = .centerY
        row.spacing = 10
        row.widthAnchor.constraint(equalToConstant: 492).isActive = true
        return row
    }

    // MARK: - State

    private func refresh() {
        let trusted = AXIsProcessTrusted()
        let recording = CGPreflightScreenCaptureAccess()
        accessibilityStatus.stringValue = trusted ? "✓ Granted" : "Not granted"
        screenStatus.stringValue = recording ? "✓ Granted" : "Not granted"
        accessibilityGrant.isEnabled = !trusted
        screenGrant.isEnabled = !recording
        let hasConfig = FileManager.default.fileExists(atPath: configURL.path)
        configStatus.stringValue = hasConfig
            ? "wm uses \(configURL.path)."
            : "There is no config yet, so wm has no key binds. Pick a starter and write it to \(configURL.path)."
        // The popups and the button share one row: a config that exists hides all of it.
        presetPopup.superview?.isHidden = hasConfig
        startButton.isEnabled = !gated || trusted
        if let stack, let window { window.setContentSize(stack.fittingSize) }
    }

    @objc private func grantAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    @objc private func grantScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    @objc private func presetChanged() {
        let index = presetPopup.indexOfSelectedItem
        guard InitTemplate.allCases.indices.contains(index) else { return }
        modPopup.selectItem(withTitle: InitTemplate.allCases[index].defaultMod)
    }

    @objc private func writeConfig() {
        let index = presetPopup.indexOfSelectedItem
        guard InitTemplate.allCases.indices.contains(index) else { return }
        let template = InitTemplate.allCases[index]
        do {
            _ = try writeInitConfig(initConfig(template, mod: modPopup.titleOfSelectedItem ?? template.defaultMod), to: configURL, force: false)
        } catch {
            configStatus.stringValue = "Cannot write \(configURL.path): \(error.localizedDescription)"
            return
        }
        refresh()
    }

    @objc private func start() {
        window?.close()
        if gated { onStart() }
    }
}

private extension NSTextField {
    func withFont(_ font: NSFont) -> NSTextField {
        self.font = font
        return self
    }
}
