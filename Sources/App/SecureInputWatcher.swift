import AppKit
import Common
import Platform

/// Watches Secure Event Input. macOS sends no notification for it, so it looks every second and when another app comes to the
/// front (a password field is usually in the app that just got focus). `onChange` runs when the state changes, with the name of the
/// app that holds it, or `nil` when it ended.
@MainActor
final class SecureInputWatcher {
    var onChange: ((String?) -> Void)?
    private(set) var holder: String?
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        check()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }

    private func check() {
        let now = SecureInput.state()
        guard now != holder else { return }
        holder = now
        Log.write(.info, now.map { "secure input is on, held by \($0): key binds are paused" } ?? "secure input is off", source: "input", prefix: "wmd")
        onChange?(now)
    }
}
