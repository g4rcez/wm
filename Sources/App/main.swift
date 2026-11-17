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
    private var watcher: ConfigWatcher?
    private var permissionTimer: Timer?
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
        manager.onRelayout = { [menu] workspace, layout in menu?.setWorkspace(workspace ?? "", layout: layout) }
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
        awaitAccessibility()
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
            prefixLabel.show(content, settings: label, on: monitor.workArea)
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

    /// Hotkeys and window control need the Accessibility permission. Ask, then start as soon as it is granted.
    private func awaitAccessibility() {
        let prompt = "AXTrustedCheckOptionPrompt"
        if AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary) {
            startWindowControl()
            return
        }
        menu.setError("Grant Accessibility permission to wm")
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard AXIsProcessTrusted() else { return }
                self?.permissionTimer?.invalidate()
                self?.menu.setError(nil)
                self?.startWindowControl()
            }
        }
    }

    private func startWindowControl() {
        // After sleep the keyboards may be set up again, and the CapsLock mapping with them.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller.keyboardsWoke() }
        }
        manager.start()
        if !controller.input.start() {
            menu.setError("Cannot listen for keys: check Accessibility permission")
        }
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
