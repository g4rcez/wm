import Foundation
import Platform
import Scripting

/// The trackpad frames, from the thread of the private framework to the main thread. The tracker runs under a lock where
/// the frames arrive; the events wait in a list, and at most one hop to the main thread is pending, so a fast stream of
/// frames never queues up work. Nothing touches the window manager off the main thread.
final class TrackpadInput: @unchecked Sendable {
    private let lock = NSLock()
    private var tracker = FingerTracker()
    private var pending: [FingerTracker.Event] = []
    private var scheduled = false
    private let deliver: @MainActor @Sendable ([FingerTracker.Event]) -> Void

    init(deliver: @escaping @MainActor @Sendable ([FingerTracker.Event]) -> Void) {
        self.deliver = deliver
    }

    /// `false` when the framework or a trackpad is missing.
    func start() -> Bool {
        reset()
        return Trackpad.start { [self] samples, time in
            frame(samples.map { TouchPoint(id: $0.id, x: $0.x, y: $0.y, touching: $0.touching) }, time)
        }
    }

    func stop() {
        Trackpad.stop()
        reset()
    }

    private func reset() {
        lock.withLock {
            tracker = FingerTracker()
            pending = []
        }
    }

    private func frame(_ points: [TouchPoint], _ time: Double) {
        let hop: Bool = lock.withLock {
            pending += tracker.frame(points, time: time)
            guard !pending.isEmpty, !scheduled else { return false }
            scheduled = true
            return true
        }
        guard hop else { return }
        DispatchQueue.main.async { [self] in
            let events: [FingerTracker.Event] = lock.withLock {
                scheduled = false
                defer { pending = [] }
                return pending
            }
            MainActor.assumeIsolated { deliver(events) }
        }
    }
}
