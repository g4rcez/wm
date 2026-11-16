import AppKit
import CoreGraphics

public struct DisplayInfo: Sendable, Equatable {
    public var id: UInt32
    public var name: String
    /// Full frame and usable frame (menu bar and Dock removed), in Accessibility coordinates (origin top-left).
    public var frame: CGRect
    public var workArea: CGRect
    public var isMain: Bool
}

public enum Displays {
    /// The primary screen's height is the pivot between Cocoa (origin bottom-left) and Accessibility coordinates.
    @MainActor private static var pivot: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    @MainActor public static func all() -> [DisplayInfo] {
        let pivot = pivot
        func flip(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: pivot - rect.maxY, width: rect.width, height: rect.height)
        }
        return NSScreen.screens.enumerated().compactMap { index, screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return DisplayInfo(
                id: number.uint32Value,
                name: screen.localizedName,
                frame: flip(screen.frame),
                workArea: flip(screen.visibleFrame),
                isMain: index == 0
            )
        }
    }

    /// Accessibility rectangle -> Cocoa rectangle, for overlay windows.
    @MainActor public static func cocoaRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: pivot - rect.maxY, width: rect.width, height: rect.height)
    }
}
