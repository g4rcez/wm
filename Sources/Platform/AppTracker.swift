import AppKit
import Core

/// Keeps one `AppWatcher` per regular running app and reports anything that may change the window list.
@MainActor
public final class AppTracker {
    private var watchers: [pid_t: AppWatcher] = [:]
    private var tokens: [NSObjectProtocol] = []
    private let onChange: @MainActor () -> Void

    /// Why wm must not read or move windows now. While the Mac sleeps or is locked, displays and apps are not stable.
    private enum Pause: Hashable { case sleep, screens, session, lock }
    private var pauses: Set<Pause> = []
    private var settle: Timer?

    /// `true` while the Mac sleeps, its screens sleep, the user session is not active, or the screen is locked, and
    /// during the short delay after that.
    public var isPaused: Bool { !pauses.isEmpty || settle != nil }

    public init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        let center = NSWorkspace.shared.notificationCenter
        let pauseEvents: [(Notification.Name, Pause, Bool)] = [
            (NSWorkspace.willSleepNotification, .sleep, true), (NSWorkspace.didWakeNotification, .sleep, false),
            (NSWorkspace.screensDidSleepNotification, .screens, true), (NSWorkspace.screensDidWakeNotification, .screens, false),
            (NSWorkspace.sessionDidResignActiveNotification, .session, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, .session, false),
        ]
        for (name, reason, on) in pauseEvents {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.set(reason, on) }
            })
        }
        let distributed = DistributedNotificationCenter.default()
        for (name, on) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            tokens.append(distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.set(.lock, on) }
            })
        }
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
        ]
        tokens += names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncWatchers(); self?.onChange() }
            }
        }
        // Plugging or unplugging a display is posted on the default center, not the workspace one.
        tokens.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange() }
        })
        syncWatchers()
    }

    private func set(_ reason: Pause, _ on: Bool) {
        settle?.invalidate()
        settle = nil
        if on {
            pauses.insert(reason)
            return
        }
        pauses.remove(reason)
        guard pauses.isEmpty else { return }
        // Displays and apps need a moment to come back before the windows are read again.
        settle = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.settle = nil
                self?.syncWatchers()
                self?.onChange()
            }
        }
    }

    /// Starts watchers for new apps and stops those of apps that quit.
    public func syncWatchers() {
        let me = ProcessInfo.processInfo.processIdentifier
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != me && !$0.isTerminated
        }
        let alive = Set(running.map(\.processIdentifier))
        for (pid, watcher) in watchers where !alive.contains(pid) {
            watcher.stop()
            watchers[pid] = nil
        }
        for app in running where watchers[app.processIdentifier] == nil {
            watchers[app.processIdentifier] = AppWatcher(application: app) { [weak self] _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.onChange() } }
            }
        }
    }

    public func watcher(for pid: pid_t) -> AppWatcher? { watchers[pid] }

    /// Watchers of the apps that are not hidden.
    private func visibleWatchers() -> [AppWatcher] {
        let hidden = Set(NSWorkspace.shared.runningApplications.filter(\.isHidden).map(\.processIdentifier))
        return watchers.filter { !hidden.contains($0.key) }.map(\.value)
    }

    /// Windows of every watched app, read in parallel. Apps that are hidden report no windows. `unread` holds the apps
    /// that could not be read: their windows are not known to be gone.
    public func snapshot() async -> (windows: [WindowInfo], unread: Set<pid_t>) {
        let active = visibleWatchers()
        return await withTaskGroup(of: (pid_t, [WindowInfo]?).self) { group in
            for watcher in active { group.addTask { (watcher.pid, await watcher.snapshot()) } }
            var all: [WindowInfo] = []
            var unread: Set<pid_t> = []
            for await (pid, windows) in group {
                if let windows { all += windows } else { unread.insert(pid) }
            }
            return (all, unread)
        }
    }

    /// The frames of every window of the same apps as `snapshot`, with far fewer AX calls. For the mouse gesture,
    /// which only compares frames.
    public func frameSnapshot() async -> [WindowID: CGRect] {
        let active = visibleWatchers()
        return await withTaskGroup(of: [WindowID: CGRect].self) { group in
            for watcher in active { group.addTask { await watcher.frames() } }
            var all: [WindowID: CGRect] = [:]
            for await frames in group { all.merge(frames) { first, _ in first } }
            return all
        }
    }

    /// The focused window of the frontmost app.
    public func focusedWindow() async -> WindowID? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let watcher = watchers[pid] else { return nil }
        return await watcher.focusedWindow()
    }
}
