import Foundation

/// The look of the overlays (palette, cheatsheet, switcher, overview, template picker, key label). One look for all of them.
/// `native` follows macOS (system materials, light and dark, accent and selection colors); `hud` is a dark, rounded look.
public enum AppearanceStyle: String, Sendable, CaseIterable {
    case native, hud
}

/// Light, dark, or whatever the system uses now.
public enum ThemeMode: String, Sendable, CaseIterable {
    case system, light, dark
}

/// The blur behind an overlay. `none` is a flat system color without blur.
public enum OverlayMaterial: String, Sendable, CaseIterable {
    case popover, menu, hud, sidebar, sheet, window, none
}

/// How much room the overlays take: rows, panels, chips and paddings all scale together.
public enum Density: String, Sendable, CaseIterable {
    case compact, comfortable, spacious

    public var scale: Double {
        switch self {
        case .compact: 0.85
        case .comfortable: 1
        case .spacious: 1.2
        }
    }
}

/// What an overlay draws with. A color that is `nil` means "the system's semantic color" (`labelColor`, `controlAccentColor`...).
public struct ResolvedStyle: Sendable, Equatable {
    public var style: AppearanceStyle
    public var density: Density
    public var theme: ThemeMode
    public var material: OverlayMaterial
    public var accent: Color?
    public var background: Color?
    public var foreground: Color?
    public var secondary: Color?
    public var selection: Color?
    public var border: Color?
    public var borderWidth: Double
    public var radius: Double
    public var shadow: Bool
    public var font: String?
    public var fontSize: Double?
    public var monoFont: String?
    public var animation: Double

    /// The system look: nothing in this style is a fixed color.
    public var isNative: Bool { style == .native }
    public var scale: Double { density.scale }

    public static let defaultPaletteRowHeight = 38.0
    public static let defaultPaletteWidth = 750.0
    public static let defaultCheatsheetRowHeight = 32.0
    public static let defaultCheatsheetWidth = 1260.0
    public var paletteRowHeight: Double { (Self.defaultPaletteRowHeight * scale).rounded() }
    public var paletteWidth: Double { (Self.defaultPaletteWidth * scale).rounded() }
    public var cheatsheetRowHeight: Double { (Self.defaultCheatsheetRowHeight * scale).rounded() }
    public var cheatsheetWidth: Double { (Self.defaultCheatsheetWidth * scale).rounded() }

    /// The dim layer of the overview: the background, never more opaque than 0.85, so the wallpaper still shows.
    public var overviewBackdrop: Color? {
        background.map { Color(red: $0.red, green: $0.green, blue: $0.blue, alpha: min($0.alpha, 0.85)) }
    }
}

public struct AppearanceSettings: Sendable, Equatable {
    public static let radiusRange = 0.0...48.0
    public static let borderWidthRange = 0.0...6.0
    public static let fontSizeRange = 8.0...40.0
    public static let animationRange = 0.0...2.0

    public var style: AppearanceStyle = .native
    public var density: Density = .comfortable
    public var theme: ThemeMode?
    public var material: OverlayMaterial?
    /// Selected tile, active tab, mode chip. Absent: the system accent color.
    public var accent: Color?
    /// A tint over the material (and the dim layer of the overview).
    public var background: Color?
    public var foreground: Color?
    public var secondary: Color?
    /// The highlight of the selected row. Absent: the system selection color.
    public var selection: Color?
    public var border: Color?
    public var borderWidth: Double?
    public var radius: Double?
    public var shadow: Bool?
    public var font: String?
    public var fontSize: Double?
    public var monoFont: String?
    /// Seconds of the fades; 0 turns them off.
    public var animation: Double?
    public init() {}

    /// The look that every overlay draws with: the keys that are set, and the preset of `style` under them.
    public func resolved() -> ResolvedStyle {
        let preset = Self.preset(style)
        return ResolvedStyle(
            style: style, density: density, theme: theme ?? preset.theme, material: material ?? preset.material,
            accent: accent ?? preset.accent, background: background ?? preset.background, foreground: foreground, secondary: secondary,
            selection: selection, border: border, borderWidth: borderWidth ?? 1, radius: radius ?? preset.radius,
            shadow: shadow ?? true, font: font, fontSize: fontSize, monoFont: monoFont, animation: animation ?? 0.12)
    }

    private struct Preset {
        var theme: ThemeMode
        var material: OverlayMaterial
        var radius: Double
        var accent: Color?
        var background: Color?
    }

    /// `native` sets only the shape and leaves every color to the system. `hud` is a dark blur with big corners.
    private static func preset(_ style: AppearanceStyle) -> Preset {
        switch style {
        case .native: Preset(theme: .system, material: .popover, radius: 12)
        case .hud:
            Preset(
                theme: .dark, material: .hud, radius: 20, accent: Color(red: 0.537, green: 0.706, blue: 0.980),
                background: Color(red: 0, green: 0, blue: 0, alpha: 0.35))
        }
    }
}
