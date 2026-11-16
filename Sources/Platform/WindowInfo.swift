import CoreGraphics
import Core

public struct WindowInfo: Sendable, Equatable {
    public var id: WindowID
    public var pid: Int32
    public var bundleID: String
    public var appName: String
    public var title: String
    public var role: String
    public var subrole: String
    public var frame: CGRect
    public var isMinimized: Bool
    public var isFullscreen: Bool

    /// Standard windows are tiled; dialogs and palettes float; everything else (popups, helpers) is ignored.
    public var kind: Kind {
        switch subrole {
        case "AXStandardWindow": .standard
        case "AXDialog", "AXSystemDialog", "AXFloatingWindow": .floating
        default: .ignored
        }
    }

    public enum Kind: Sendable { case standard, floating, ignored }
}
