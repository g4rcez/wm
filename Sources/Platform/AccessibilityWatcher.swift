import ApplicationServices
import Foundation

/// Reports whether this process has the Accessibility permission: each second, and right after macOS says that the permissions
/// changed. Not every change is announced, so both are needed.
@MainActor
public final class AccessibilityWatcher {
    private let onCheck: @MainActor (_ trusted: Bool) -> Void
    private var timer: Timer?
    private var observer: (any NSObjectProtocol)?

    public init(onCheck: @escaping @MainActor (_ trusted: Bool) -> Void) {
        self.onCheck = onCheck
    }

    /// Checks at once, and then until the process ends.
    public func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        // `.common`: it also runs while a menu is open or a window is dragged.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSoon() }
        }
        check()
    }

    /// `AXIsProcessTrusted` can still give the old answer when the notification arrives.
    private func checkSoon() {
        for delay in [0.1, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.check() }
            }
        }
    }

    private func check() { onCheck(AXIsProcessTrusted()) }
}
