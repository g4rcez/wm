import AppKit
import ApplicationServices
import Common
import Core
import Foundation
import Platform
import Scripting

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let manager = WindowManager()
    private var controller: AppController!
    private var menu: MenuBar!
    private let secureInput = SecureInputWatcher()
    private var watcher: ConfigWatcher?
    private var accessibility: AccessibilityWatcher?
    private var windowControlStarted = false
    /// macOS refused the taps although the permission is there: wm tries again, and says so once.
    private var keyTapRefused = false
    private var setup: OnboardingWindow?
    private var shortcutsWindow: ShortcutsWindow?
    private var doctorWindow: DoctorWindow?
    private let prefixLabel = PrefixLabel()
    /// The steps of a sequence that waits for its next key; the label lists the keys that can follow while it waits.
    private var pendingSteps: [Chord]?
    /// A message from `wm notify`, which takes the label's place until its time is up.
    private var notice: String?
    private var noticeTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let configURL = defaultConfigURL()
        controller = AppController(manager: manager, configURL: configURL)
        menu = MenuBar(
            configFolder: configURL.deletingLastPathComponent(),
            reload: { [controller] in Task.detached { _ = controller!.reload() } },
            setup: { [weak self] in self?.showSetup() },
            shortcuts: { [weak self] in self?.showShortcuts() },
            doctor: { [weak self] in self?.showDoctor() },
            templates: { [manager] in manager.templates(of: manager.focused) },
            tile: { [controller] name in Task.detached { _ = controller!.run(["layout", "tile", name]) } }
        )
        // While a key sequence waits for its next key: the menu bar icon and a small floating label show it.
        controller.input.onPending = { [weak self] steps in
            guard let self else { return }
            menu.setPending(steps != nil && manager.settings.prefix.menuBar)
            pendingSteps = steps
            refreshLabel()
        }
        // A binding mode other than `main` changes the icon and keeps its name on screen until the mode ends.
        manager.onModeChange = { [weak self] mode in
            guard let self else { return }
            menu.setMode(mode == "main" ? nil : mode)
            refreshLabel()
        }
        controller.onConfigError = { [menu] message in menu?.setError(message) }
        controller.onShowDoctor = { [weak self] in self?.showDoctor() }
        controller.onNotify = { [weak self] text, seconds in
            guard let self else { return }
            noticeTimer?.invalidate()
            notice = text
            refreshLabel()
            noticeTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.notice = nil
                    self?.refreshLabel()
                }
            }
        }
        controller.trayVisible = { [menu] in menu?.isVisible ?? false }
        controller.trayDebug = { [menu] in menu?.details ?? "" }
        manager.onRelayout = { [menu] workspace, layout, label in menu?.setWorkspace(workspace ?? "", layout: layout, label: label) }
        do {
            try controller.startServer()
        } catch SocketError.alreadyRunning {
            Log.write(.error, "another instance is already running", source: "daemon", prefix: "wmd")
            exit(1)
        } catch {
            Log.write(.error, "cannot start the command socket: \(error)", source: "daemon", prefix: "wmd")
            exit(1)
        }
        watcher = ConfigWatcher(fileURL: configURL) { [controller] in
            Task.detached { _ = controller!.reload() }
        }
        Task.detached { [controller] in _ = controller!.reload(notify: false) }
        // wm moves no window until the user has pressed Start in the setup window, once.
        if Onboarding.isDone() {
            awaitAccessibility()
        } else {
            menu.setError("Finish the setup: wm moves no window yet")
            showSetup()
        }
    }

    private func showDoctor() {
        if doctorWindow == nil { doctorWindow = DoctorWindow() }
        doctorWindow?.show()
    }

    private func showShortcuts() {
        if shortcutsWindow == nil {
            shortcutsWindow = ShortcutsWindow(
                configURL: defaultConfigURL(), input: controller.input, tapRunning: { [controller] in controller?.keyTapRunning ?? false })
        }
        shortcutsWindow?.show()
    }

    /// The setup window. Before the first Start it is the gate; after it, the menu item opens it to look at the setup again.
    private func showSetup() {
        if setup == nil {
            let configURL = defaultConfigURL()
            setup = OnboardingWindow(configURL: configURL) { [weak self] in
                guard let self else { return }
                do {
                    try Onboarding.markDone()
                } catch {
                    Log.write(.error, "cannot write the setup marker: \(error)", source: "daemon")
                }
                menu.setError(nil)
                // A config that the window wrote may be there before the watcher sees the folder.
                Task.detached { [controller] in _ = controller!.reload() }
                awaitAccessibility()
            }
        }
        setup?.show(gated: !Onboarding.isDone())
    }

    /// What the label shows: a message from `wm notify`, else the sequence that waits for its next key, else the binding
    /// mode. The last two come with the keys that can be pressed next. It uses `prefix.label`.
    private func labelContent() -> LabelContent? {
        let settings = manager.settings.prefix.label
        if let notice { return LabelContent(text: notice) }
        let records = controller.bindRecords
        if let steps = pendingSteps {
            let keys = settings.showKeys ? WhichKey.entries(mode: manager.mode, pending: steps, records: records) : []
            return LabelContent(badge: steps.map(WhichKey.display).joined(separator: " "), entries: keys)
        }
        guard manager.mode != "main" else { return nil }
        let keys = settings.showKeys ? WhichKey.entries(mode: manager.mode, pending: [], records: records) : []
        return LabelContent(badge: manager.mode, entries: keys)
    }

    private func refreshLabel() {
        let label = manager.settings.prefix.label
        // A message that was asked for shows even when the key label is turned off.
        if let content = labelContent(), label.enabled || notice != nil, let monitor = manager.focusedMonitor {
            prefixLabel.show(content, settings: label, style: manager.settings.overlayStyle(), on: monitor.workArea)
        } else {
            prefixLabel.hide()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.restoreSystemShortcuts()
        controller.stopServer()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { controller.handle(url: url) }
    }

    /// Hotkeys and window control need the Accessibility permission. Ask, then follow it for as long as wm runs: start when it
    /// is granted, and let go of the keys when it is removed.
    private func awaitAccessibility() {
        guard accessibility == nil else { return }
        let prompt = "AXTrustedCheckOptionPrompt"
        if !AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary) {
            menu.setError("Grant Accessibility permission to wm")
        }
        let watcher = AccessibilityWatcher { [weak self] trusted in self?.accessibilityChecked(trusted: trusted) }
        accessibility = watcher
        watcher.start()
    }

    private func accessibilityChecked(trusted: Bool) {
        switch KeyTapAccess.action(trusted: trusted, listening: controller.keyTapRunning) {
        case .start: startListening()
        case .stop:
            controller.stopListening()
            menu.setError("Accessibility permission was removed: wm stopped listening for keys")
            Log.write(.warn, "Accessibility permission was removed: wm stopped listening for keys", source: "input", prefix: "wmd")
        // A tap that macOS disabled while the permission was away for a moment listens again.
        case .keep: if trusted { controller.input.tap.reenable() }
        }
    }

    private func startListening() {
        if !windowControlStarted {
            windowControlStarted = true
            startWindowControl()
        }
        guard controller.startListening() else {
            if !keyTapRefused { menu.setError("Cannot listen for keys: check Accessibility permission") }
            keyTapRefused = true
            return
        }
        keyTapRefused = false
        menu.setError(nil)
        manager.scheduleRefresh()
    }

    /// What runs once, with the first grant.
    private func startWindowControl() {
        // After sleep the keyboards may be set up again, and the CapsLock mapping with them.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.controller.keyboardsWoke()
                // The Mac may have shrunk or moved windows while it slept: look at them again.
                self?.manager.scheduleRefresh()
            }
        }
        controller.watchKeyboards()
        // Secure Event Input (a password field) hides the keys from wm: show a lock, and start the key state again when it changes.
        secureInput.onChange = { [weak self] holder in
            guard let self else { return }
            menu.setSecureInput(holder)
            controller.input.recoverFromSecureInput()
        }
        secureInput.start()
        manager.start()
    }
}

// `wmd --background` starts a detached copy of itself and returns at once, so a terminal can be closed afterwards.
if CommandLine.arguments.contains(where: { $0 == "--background" || $0 == "-d" }),
   ProcessInfo.processInfo.environment["WM_DETACHED"] == nil {
    let child = Process()
    child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    child.arguments = []
    child.environment = ProcessInfo.processInfo.environment.merging(["WM_DETACHED": "1"]) { $1 }
    child.standardInput = FileHandle.nullDevice
    child.standardOutput = FileHandle.nullDevice
    child.standardError = FileHandle.nullDevice
    do {
        try child.run()
        print("wmd started in the background (pid \(child.processIdentifier))")
        exit(0)
    } catch {
        Log.write(.error, "cannot start in the background: \(error)", source: "daemon", prefix: "wmd")
        exit(1)
    }
}
// A detached copy outlives its terminal.
if ProcessInfo.processInfo.environment["WM_DETACHED"] != nil { signal(SIGHUP, SIG_IGN) }

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)

// A signal (Ctrl-C, `kill`) quits through AppKit, so the socket file is removed.
let signalSources = [SIGINT, SIGTERM].map { number -> any DispatchSourceSignal in
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler { NSApplication.shared.terminate(nil) }
    source.resume()
    return source
}
withExtendedLifetime(signalSources) { application.run() }
