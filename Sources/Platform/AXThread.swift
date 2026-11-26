import CoreFoundation
import Foundation

/// A thread with its own run loop. One per application, so one hung app cannot block the others.
final class AXThread: @unchecked Sendable {
    private final class Holder: @unchecked Sendable { var loop: CFRunLoop? }
    private let holder = Holder()
    /// The calls of `run(orElse:)` that wait for their block. When the loop stops, the blocks that it never ran answer with
    /// their fallback: a caller must not wait for a thread that is gone (an app quit while wm was reading its windows).
    private let lock = NSLock()
    private var pending: [UInt64: @Sendable () -> Void] = [:]
    private var nextCall: UInt64 = 0
    private var stopped = false

    init(name: String) {
        let ready = DispatchSemaphore(value: 0)
        let holder = holder
        let thread = Thread { [weak self] in
            holder.loop = CFRunLoopGetCurrent()
            // A port keeps the run loop alive while it has no other source.
            RunLoop.current.add(Port(), forMode: .default)
            ready.signal()
            CFRunLoopRun()
            self?.answerPending()
        }
        thread.name = name
        thread.start()
        ready.wait()
    }

    /// The run loop of this thread, for adding observer sources.
    var runLoop: CFRunLoop { holder.loop! }

    func async(_ body: @escaping @Sendable () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, body)
        CFRunLoopWakeUp(runLoop)
    }

    /// Runs `body` on this thread. Only for a thread that never stops: a block queued after `stop()` never runs, and the
    /// caller would wait for ever. A thread that can stop uses `run(orElse:_:)`.
    func run<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            async { continuation.resume(returning: body()) }
        }
    }

    /// Runs `body` on this thread, or answers `fallback` when the thread has stopped before it ran the block.
    func run<T: Sendable>(orElse fallback: T, _ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            let call: UInt64? = lock.withLock {
                guard !stopped else { return nil }
                nextCall &+= 1
                pending[nextCall] = { continuation.resume(returning: fallback) }
                return nextCall
            }
            guard let call else { return continuation.resume(returning: fallback) }
            async { [self] in
                // Taken out under the lock, so the block and `answerPending` never both resume it.
                guard lock.withLock({ pending.removeValue(forKey: call) }) != nil else { return }
                continuation.resume(returning: body())
            }
        }
    }

    func stop() {
        CFRunLoopStop(runLoop)
    }

    private func answerPending() {
        let waiting: [@Sendable () -> Void] = lock.withLock {
            stopped = true
            defer { pending = [:] }
            return Array(pending.values)
        }
        for answer in waiting { answer() }
    }
}
