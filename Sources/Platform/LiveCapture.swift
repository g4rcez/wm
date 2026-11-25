import AppKit
import Core
import CoreMedia
@preconcurrency import ScreenCaptureKit

/// The live picture of one window, wherever it is: wm parks hidden windows at the edge of the screen and ScreenCaptureKit
/// still sends their frames. It needs the Screen Recording permission; check it first, as starting without it shows the prompt.
public final class LiveCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let window: WindowID
    private let onFrame: @MainActor (IOSurface) -> Void
    private let onStop: @MainActor () -> Void
    @MainActor private var stream: SCStream?
    @MainActor private var stopped = false

    @MainActor public init(window: WindowID, onFrame: @escaping @MainActor (IOSurface) -> Void, onStop: @escaping @MainActor () -> Void) {
        self.window = window
        self.onFrame = onFrame
        self.onStop = onStop
    }

    private static func configuration(_ pixels: CGSize, fps: Int) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = max(Int(pixels.width), 2)
        config.height = max(Int(pixels.height), 2)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        return config
    }

    /// `false` when the window cannot be captured.
    @MainActor public func start(pixels: CGSize, fps: Int) async -> Bool {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let target = content.windows.first(where: { $0.windowID == window }), !stopped else { return false }
        let new = SCStream(filter: SCContentFilter(desktopIndependentWindow: target), configuration: Self.configuration(pixels, fps: fps), delegate: self)
        do {
            // On the main queue: a frame is only a surface to hand to a layer.
            try new.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
            try await new.startCapture()
        } catch { return false }
        if stopped {
            try? await new.stopCapture()
            return false
        }
        stream = new
        return true
    }

    @MainActor public func resize(pixels: CGSize, fps: Int) {
        stream?.updateConfiguration(Self.configuration(pixels, fps: fps)) { _ in }
    }

    @MainActor public func stop() {
        stopped = true
        stream?.stopCapture { _ in }
        stream = nil
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // A buffer without an image says that nothing changed.
        guard type == .screen, let image = CMSampleBufferGetImageBuffer(buffer),
              let surface = CVPixelBufferGetIOSurface(image)?.takeUnretainedValue() else { return }
        nonisolated(unsafe) let frame = unsafeBitCast(surface, to: IOSurface.self)
        MainActor.assumeIsolated { onFrame(frame) }
    }

    public func stream(_ stream: SCStream, didStopWithError error: any Error) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.stopped else { return }
                self.onStop()
            }
        }
    }
}
