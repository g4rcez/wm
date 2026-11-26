import AppKit
import Common
import Platform

/// The Doctor window: what `wm doctor` finds, and a button that runs `wm doctor fix`. Both run the `wm` next to this daemon,
/// so the window and the terminal say the same. A fix may restart wm: the helper then opens this window in the new one.
@MainActor
final class DoctorWindow: NSObject {
    private var window: NSWindow?
    private var checks: [DoctorCheck] = []
    private var fixing = false
    private let summary = NSTextField(wrappingLabelWithString: "")
    private let rows = TopStackView()
    private let plan = NSTextField(wrappingLabelWithString: "")
    private let checkButton = NSButton()
    private let copyButton = NSButton()
    private let fixButton = NSButton()

    private static let width: CGFloat = 580
    private static let margin: CGFloat = 20

    /// `brew upgrade` deletes the folder that this wm runs from: the stable path then holds the new `wm`, which finds this
    /// daemon out of date and restarts it.
    private var cli: URL? {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("wm")
        }
        return URL(fileURLWithPath: stableBundlePath(Bundle.main.bundlePath)).appendingPathComponent("Contents/MacOS/wm")
    }

    func show() {
        if window == nil { build() }
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
        refresh()
    }

    // MARK: - Build

    private func build() {
        summary.font = .systemFont(ofSize: 17, weight: .semibold)
        summary.preferredMaxLayoutWidth = Self.width - 2 * Self.margin
        plan.font = .systemFont(ofSize: 12)
        plan.textColor = .secondaryLabelColor
        plan.preferredMaxLayoutWidth = Self.width - 2 * Self.margin

        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 12
        rows.edgeInsets = NSEdgeInsets(top: 3, left: 0, bottom: 3, right: 0)
        rows.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = rows
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            rows.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 400),
            scroll.widthAnchor.constraint(equalToConstant: Self.width - 2 * Self.margin),
        ])

        for (button, title, action) in [
            (checkButton, "Check Again", #selector(checkAgain)),
            (copyButton, "Copy Report", #selector(copyReport)),
            (fixButton, "Fix Problems", #selector(fixProblems)),
        ] {
            button.title = title
            button.bezelStyle = .rounded
            button.target = self
            button.action = action
        }
        // No button answers Return: a key that was meant for another window must not change the system.
        let buttons = NSStackView(views: [checkButton, copyButton, NSView(), fixButton])
        buttons.spacing = 8
        buttons.widthAnchor.constraint(equalToConstant: Self.width - 2 * Self.margin).isActive = true

        let stack = NSStackView(views: [summary, scroll, plan, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: Self.margin, left: Self.margin, bottom: Self.margin, right: Self.margin)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Self.width).isActive = true

        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "wm doctor"
        window.isReleasedWhenClosed = false
        window.contentView = stack
        self.window = window
    }

    // MARK: - Check

    private func refresh() {
        guard !fixing else { return }
        summary.stringValue = "Checking…"
        setButtons(enabled: false)
        guard let cli else { return display(nil) }
        Task { [weak self] in
            // The exit code says that a check failed: the report is there all the same.
            let output = await Subprocess.output(cli.path, ["doctor", "fix", "--dry-run", "--json"], timeout: 30, anyExit: true)
            self?.display(output.flatMap { try? JSONDecoder().decode(DoctorReport.self, from: Data($0.utf8)) })
        }
    }

    private func display(_ report: DoctorReport?) {
        guard !fixing else { return }
        checks = report?.checks ?? []
        for row in rows.arrangedSubviews { row.removeFromSuperview() }
        // The problems come first: the list is longer than the window.
        let order: [DoctorStatus] = [.fail, .warn, .ok, .skip]
        for status in order {
            for check in checks where check.status == status { rows.addArrangedSubview(row(check)) }
        }
        setButtons(enabled: true)
        copyButton.isEnabled = report != nil
        fixButton.isEnabled = report?.fixes.isEmpty == false
        guard let report else {
            summary.stringValue = "wm could not run its checks"
            plan.stringValue = "Run `wm doctor` in a terminal to see why."
            return
        }
        let problems = report.checks.filter { $0.status == .fail || $0.status == .warn }.count
        summary.stringValue = problems == 0 ? "Everything works" : problems == 1 ? "1 problem" : "\(problems) problems"
        if !report.fixes.isEmpty {
            plan.stringValue = "Fix Problems will:\n" + report.fixes.map { "• \($0)" }.joined(separator: "\n")
        } else {
            plan.stringValue = problems == 0 ? "" : "wm cannot repair these by itself: follow the hint of each one."
        }
    }

    private func row(_ check: DoctorCheck) -> NSView {
        let (symbol, color): (String, NSColor) = switch check.status {
        case .ok: ("checkmark.circle.fill", .systemGreen)
        case .warn: ("exclamationmark.triangle.fill", .systemOrange)
        case .fail: ("xmark.octagon.fill", .systemRed)
        case .skip: ("minus.circle", .secondaryLabelColor)
        }
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: check.status.rawValue)
        icon.contentTintColor = color
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true

        let name = NSTextField(labelWithString: check.name)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        var lines: [NSView] = [name, label(check.detail, color: .labelColor)]
        if let hint = check.hint, check.status != .ok { lines.append(label(hint, color: .secondaryLabelColor)) }
        let text = NSStackView(views: lines)
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        let row = NSStackView(views: [icon, text])
        row.alignment = .top
        row.spacing = 10
        return row
    }

    private func label(_ text: String, color: NSColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = color
        label.preferredMaxLayoutWidth = Self.width - 2 * Self.margin - 50
        return label
    }

    private func setButtons(enabled: Bool) {
        for button in [checkButton, copyButton, fixButton] { button.isEnabled = enabled }
    }

    // MARK: - Actions

    @objc private func checkAgain() { refresh() }

    @objc private func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(renderDoctor(checks), forType: .string)
    }

    @objc private func fixProblems() {
        guard let cli else { return }
        // Not a pipe to this process: the fix may quit this wm, and a write to a closed pipe would end the helper half way.
        let log = defaultLogURL().deletingLastPathComponent().appendingPathComponent("doctor.log")
        _ = FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let output = (try? FileHandle(forWritingTo: log)) ?? FileHandle.nullDevice
        let process = Process()
        process.executableURL = cli
        // `--show` also puts the helper in its own session, so that it stays when this wm quits.
        process.arguments = ["doctor", "fix", "--show"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.fixing = false
                if self?.window?.isVisible == true { self?.refresh() }
            }
        }
        fixing = true
        setButtons(enabled: false)
        summary.stringValue = "Fixing… If wm restarts, this window opens again."
        do {
            try process.run()
        } catch {
            fixing = false
            Log.write(.error, "cannot run wm doctor fix: \(error)", source: "doctor")
            refresh()
        }
    }
}

/// A stack that starts at the top of its scroll view.
private final class TopStackView: NSStackView {
    override var isFlipped: Bool { true }
}
