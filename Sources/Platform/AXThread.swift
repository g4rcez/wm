import CoreFoundation
import Foundation

/// A thread with its own run loop. One per application, so one hung app cannot block the others.
final class AXThread: @unchecked Sendable {
    private final class Holder: @unchecked Sendable { var loop: CFRunLoop? }
    private let holder = Holder()

    init(name: String) {
        let ready = DispatchSemaphore(value: 0)
        let holder = holder
        let thread = Thread {
            holder.loop = CFRunLoopGetCurrent()
            // A port keeps the run loop alive while it has no other source.
            RunLoop.current.add(Port(), forMode: .default)
            ready.signal()
            CFRunLoopRun()
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

    func run<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            async { continuation.resume(returning: body()) }
        }
    }

    func stop() {
        CFRunLoopStop(runLoop)
    }
}
