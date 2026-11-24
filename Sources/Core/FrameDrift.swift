import CoreGraphics

/// Decides when a window that wm sent to a frame has since moved or shrunk behind its back (macOS after a display change or a
/// wake, an app that restores its own size), so wm sends the frame again. An app that refuses the size (a minimum size, a
/// terminal that rounds to whole lines) is tried `maxRetries` times for one target and then left alone.
public struct FrameDrift: Sendable {
    /// Points per edge that a window may be off before it counts as drifted.
    public static let tolerance: CGFloat = 4
    public static let maxRetries = 2

    private var retries: [WindowID: (target: CGRect, count: Int)] = [:]

    public init() {}

    /// Whether `actual` is far enough from `sent` to send again, and the retries for this target are not used up.
    public mutating func shouldResend(_ id: WindowID, actual: CGRect, sent: CGRect) -> Bool {
        if Self.matches(actual, sent) {
            retries[id] = nil
            return false
        }
        var entry = retries[id]
        if entry?.target != sent { entry = (sent, 0) }
        guard let current = entry, current.count < Self.maxRetries else {
            retries[id] = entry
            return false
        }
        retries[id] = (sent, current.count + 1)
        return true
    }

    public mutating func forget(_ id: WindowID) { retries[id] = nil }

    private static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.maxX - b.maxX) <= tolerance && abs(a.maxY - b.maxY) <= tolerance
    }
}
