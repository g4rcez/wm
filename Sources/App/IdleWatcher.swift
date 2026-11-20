import CoreGraphics
import Core
import Foundation
import Scripting

/// Reads the time since the last keyboard or mouse input and reports the `idle` and `resume` events (see `IdleState`). The reading
/// needs no permission. It runs only while the config has an `idle` handler.
@MainActor
final class IdleWatcher {
    private var state = IdleState(thresholds: [])
    private var timer: Timer?
    private let emit: (_ name: String, _ payload: [String: LuaValue]) -> Void
    /// The Mac sleeps or is locked: there is nothing to read.
    private let isPaused: () -> Bool

    init(emit: @escaping (_ name: String, _ payload: [String: LuaValue]) -> Void, isPaused: @escaping () -> Bool) {
        self.emit = emit
        self.isPaused = isPaused
    }

    /// The thresholds of the config (`wm.on("idle", { seconds = N }, ...)`). A reload with the same ones changes nothing.
    func configure(thresholds: [Double]) {
        let next = IdleState(thresholds: thresholds)
        guard next.thresholds != state.thresholds else { return }
        timer?.invalidate()
        timer = nil
        state = next
        guard let interval = next.pollInterval else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        guard !isPaused() else { return }
        // The time since the last event of the system, for any kind of input. It needs no permission.
        let idle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
        for change in state.update(idleSeconds: idle) {
            switch change {
            case .idle(let seconds): emit("idle", ["seconds": .number(seconds)])
            case .resumed(let idle): emit("resume", ["idle": .number(idle.rounded())])
            }
        }
    }
}
