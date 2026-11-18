import AppKit
import QuartzCore

/// A clock that ticks with the display refresh, at up to `fps` Hz, on the fastest screen. It replaces a fixed 60 Hz timer,
/// which cannot line up with the display and loses frames on ProMotion screens.
@MainActor
final class DisplayClock: NSObject {
    private var link: CADisplayLink?
    private let onTick: () -> Void

    init?(fps: Double, onTick: @escaping () -> Void) {
        self.onTick = onTick
        super.init()
        guard let screen = NSScreen.screens.max(by: { $0.maximumFramesPerSecond < $1.maximumFramesPerSecond }) else { return nil }
        let link = screen.displayLink(target: self, selector: #selector(fire))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, Float(fps)), maximum: Float(fps), preferred: Float(fps))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func fire() { onTick() }
}
