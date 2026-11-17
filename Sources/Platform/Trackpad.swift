import CoreGraphics
import Foundation
import PrivateApi

/// One finger on the trackpad.
public struct TouchSample: Sendable, Equatable {
    public var id: Int32
    public var x: Double
    public var y: Double
    /// The finger touches the pad (and is not just near it).
    public var touching: Bool

    public init(id: Int32, x: Double, y: Double, touching: Bool) {
        self.id = id
        self.x = x
        self.y = y
        self.touching = touching
    }
}

/// The trackpad frames of the private MultitouchSupport framework. The handler runs on a thread of the framework.
public enum Trackpad {
    public typealias Handler = @Sendable (_ touches: [TouchSample], _ time: Double) -> Void

    private final class Box: @unchecked Sendable {
        let handler: Handler
        init(_ handler: @escaping Handler) { self.handler = handler }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var box: Box?

    /// `false` when the framework, one of its functions, or a trackpad is missing.
    public static func start(_ handler: @escaping Handler) -> Bool {
        stop()
        let new = Box(handler)
        lock.withLock { box = new }
        let context = Unmanaged.passUnretained(new).toOpaque()
        let started = wm_multitouch_start({ touches, count, time, context in
            guard let touches, let context else { return }
            let box = Unmanaged<Box>.fromOpaque(context).takeUnretainedValue()
            let samples = (0..<Int(count)).map { index in
                TouchSample(id: touches[index].id, x: Double(touches[index].x), y: Double(touches[index].y), touching: touches[index].state == 4)
            }
            box.handler(samples, time)
        }, context)
        if !started { lock.withLock { box = nil } }
        return started
    }

    public static func stop() {
        wm_multitouch_stop()
        lock.withLock { box = nil }
    }
}
