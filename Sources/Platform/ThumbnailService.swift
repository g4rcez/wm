import CoreGraphics
import Core
import Foundation
import PrivateApi
@preconcurrency import ScreenCaptureKit

/// Takes pictures of single windows with ScreenCaptureKit for the window switcher, the overview and the palette. A window
/// that ScreenCaptureKit cannot give (one that wm parked off screen) comes from SkyLight instead.
/// It never calls ScreenCaptureKit without the Screen Recording permission, because that would show the system prompt.
public actor ThumbnailService {
    private struct Image: @unchecked Sendable { let value: CGImage }
    /// `SCWindow` is not Sendable; each one is used by exactly one capture task.
    private struct Target: @unchecked Sendable { let window: SCWindow }

    private static let promptedKey = "wm.screenCapturePrompted"
    private static let maxConcurrent = 4

    private var content: SCShareableContent?

    public init() {}

    public static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Asks macOS for the permission at most once ever. Later calls do nothing.
    public static func requestOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: promptedKey), !hasPermission else { return }
        defaults.set(true, forKey: promptedKey)
        _ = CGRequestScreenCaptureAccess()
    }

    /// Windows that fail or give a blank picture are left out, so the caller keeps the image it has.
    public func capture(_ ids: [WindowID], maxPixel: Int = 480) async -> [WindowID: CGImage] {
        guard Self.hasPermission, !ids.isEmpty, maxPixel > 0 else { return [:] }
        let windows = await resolve(ids) ?? []

        var result: [WindowID: CGImage] = [:]
        await withTaskGroup(of: (WindowID, Image?).self) { group in
            var pending = windows.map(Target.init).makeIterator()
            func addNext() {
                guard let target = pending.next() else { return }
                group.addTask { (target.window.windowID, await Self.shoot(target.window, maxPixel: maxPixel)) }
            }
            for _ in 0..<Self.maxConcurrent { addNext() }
            while let (id, image) = await group.next() {
                if let image { result[id] = image.value }
                addNext()
            }
        }
        let missing = ids.filter { result[$0] == nil }
        if !missing.isEmpty {
            await withTaskGroup(of: (WindowID, Image?).self) { group in
                for id in missing { group.addTask { (id, Self.shootOffScreen(id, maxPixel: maxPixel)) } }
                for await (id, image) in group { if let image { result[id] = image.value } }
            }
        }
        return result
    }

    /// The picture of a window that is not on screen. Blank pictures are left out, like in `shoot`.
    private static func shootOffScreen(_ id: WindowID, maxPixel: Int) -> Image? {
        guard let image = wm_capture_window(id), let scaled = scaled(image, maxPixel: maxPixel), !isBlank(scaled) else { return nil }
        return Image(value: scaled)
    }

    /// The image with its longest side at most `maxPixel`.
    private static func scaled(_ image: CGImage, maxPixel: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > 0 else { return nil }
        guard longest > maxPixel else { return image }
        let factor = CGFloat(maxPixel) / CGFloat(longest)
        let width = max(1, Int((CGFloat(image.width) * factor).rounded())), height = max(1, Int((CGFloat(image.height) * factor).rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Finds the `SCWindow` of each id. The cached list is refreshed once when an id is missing.
    /// An id that is still missing afterwards (window gone, not capturable) is left out.
    private func resolve(_ ids: [WindowID]) async -> [SCWindow]? {
        let wanted = Set(ids)
        func found() -> [SCWindow] { content?.windows.filter { wanted.contains($0.windowID) } ?? [] }
        if Set(found().map(\.windowID)) != wanted {
            content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        }
        return content == nil ? nil : found()
    }

    private static func shoot(_ window: SCWindow, maxPixel: Int) async -> Image? {
        let width = window.frame.width, height = window.frame.height
        guard width >= 1, height >= 1 else { return nil }
        let scale = CGFloat(maxPixel) / max(width, height)
        let config = SCStreamConfiguration()
        config.width = max(1, Int((width * scale).rounded()))
        config.height = max(1, Int((height * scale).rounded()))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let filter = SCContentFilter(desktopIndependentWindow: window)
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
              !isBlank(image) else { return nil }
        return Image(value: image)
    }

    /// Blank means every pixel of an 8x8 version is transparent or black.
    private static func isBlank(_ image: CGImage) -> Bool {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }
        // Premultiplied: a transparent pixel is all zero, so "all channels zero" covers both transparent and black.
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i] != 0 || pixels[i + 1] != 0 || pixels[i + 2] != 0 {
            return false
        }
        return true
    }
}
