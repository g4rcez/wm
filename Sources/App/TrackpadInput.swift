import Foundation
import Platform
import Scripting

/// The trackpad frames, from the thread of the private framework to the main thread. The tracker runs under a lock where
/// the frames arrive; the events wait in a list, and at most one hop to the main thread is pending, so a fast stream of
/// frames never queues up work. Nothing touches the window manager off the main thread.
final class TrackpadInput: @unchecked Sendable {
    private let lock = NSLock()
    private var tracker = FingerTracker()
    private var pinchTracker = PinchTracker()
    private var pending: [FingerTracker.Event] = []
    private var pendingPinches: [PinchTracker.Event] = []
    private var scheduled = false
    private let deliver: @MainActor @Sendable ([FingerTracker.Event]) -> Void
    private let deliverPinch: @MainActor @Sendable (PinchTracker.Event) -> Void

    init(
        deliver: @escaping @MainActor @Sendable ([FingerTracker.Event]) -> Void,
        pinch: @escaping @MainActor @Sendable (PinchTracker.Event) -> Void
    ) {
        self.deliver = deliver
        self.deliverPinch = pinch
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
            pinchTracker = PinchTracker()
            pending = []
            pendingPinches = []
        }
    }

    private func frame(_ points: [TouchPoint], _ time: Double) {
        let hop: Bool = lock.withLock {
            pending += tracker.frame(points, time: time)
            if let pinch = pinchTracker.frame(points) { pendingPinches.append(pinch) }
            guard !pending.isEmpty || !pendingPinches.isEmpty, !scheduled else { return false }
            scheduled = true
            return true
        }
        guard hop else { return }
        DispatchQueue.main.async { [self] in
            let (events, pinches): ([FingerTracker.Event], [PinchTracker.Event]) = lock.withLock {
                scheduled = false
                defer { pending = []; pendingPinches = [] }
                return (pending, pendingPinches)
            }
            MainActor.assumeIsolated {
                if !events.isEmpty { deliver(events) }
                pinches.forEach(deliverPinch)
            }
        }
    }
}
