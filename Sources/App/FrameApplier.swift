import Core
import Foundation
import Platform

/// Sends frames to the real windows. A window has at most one AX call in flight; frames that arrive meanwhile
/// replace each other, so a slow app skips frames instead of building a queue.
@MainActor
final class FrameApplier {
    var watcher: (pid_t) -> AppWatcher? = { _ in nil }
    private var last: [WindowID: CGRect] = [:]
    private var inFlight: Set<WindowID> = []
    private var pending: [WindowID: CGRect] = [:]
    var stats = AnimationStats()

    func send(_ frames: [WindowID: CGRect], windows: [WindowID: ManagedWindow]) {
        for (id, raw) in frames {
            guard let pid = windows[id]?.info.pid else { continue }
            let frame = PixelFrame.rounded(raw)
            guard last[id] != frame else { continue }
            last[id] = frame
            stats.offered()
            if inFlight.contains(id) {
                if pending[id] != nil { stats.replaced() }
                pending[id] = frame
            } else {
                dispatch(id, pid: pid, frame, app: windows[id]?.info.appName ?? "?")
            }
        }
    }

    /// The frame that was sent last (rounded), or `nil` when there is none.
    func sentFrame(_ id: WindowID) -> CGRect? { last[id] }

    /// Whether a frame for this window is being written or waits to be.
    func isBusy(_ id: WindowID) -> Bool { inFlight.contains(id) || pending[id] != nil }

    /// Makes the next `send` write the whole frame, also when it equals the last one: the real window is not where wm put it.
    func resend(_ id: WindowID, pid: pid_t) {
        forget(id)
        watcher(pid)?.forgetSize(id)
    }

    func forget(_ id: WindowID) {
        last[id] = nil
        pending[id] = nil
    }

    private func dispatch(_ id: WindowID, pid: pid_t, _ frame: CGRect, app: String) {
        guard let watcher = watcher(pid) else { return }
        inFlight.insert(id)
        stats.written()
        watcher.setFrame(id, frame) { [weak self] seconds in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.stats.write(app: app, seconds: seconds)
                    self.inFlight.remove(id)
                    if let next = self.pending.removeValue(forKey: id) { self.dispatch(id, pid: pid, next, app: app) }
                }
            }
        }
    }
}
