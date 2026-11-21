import AppKit
import Core

/// A `ResolvedStyle` turned into what AppKit draws with. A color that the style leaves out is a system color, so the overlay follows
/// light and dark mode and the accent color of macOS.
public struct Theme: @unchecked Sendable {
    public let style: ResolvedStyle
    /// The appearance that the colors are resolved in: the one that `theme` forces, or the one of the system now.
    public let appearance: NSAppearance

    /// A theme in a given appearance. The overlays that are built before any show use `Theme.placeholder`.
    public init(_ style: ResolvedStyle, appearance: NSAppearance) {
        self.style = style
        self.appearance = appearance
    }

    public static var placeholder: Theme {
        Theme(AppearanceSettings().resolved(), appearance: NSAppearance(named: .darkAqua) ?? NSAppearance.currentDrawing())
    }

    @MainActor
    public init(_ style: ResolvedStyle) {
        self.style = style
        switch style.theme {
        case .light: appearance = NSAppearance(named: .aqua) ?? NSApp.effectiveAppearance
        case .dark: appearance = NSAppearance(named: .darkAqua) ?? NSApp.effectiveAppearance
        case .system: appearance = NSApp.effectiveAppearance
        }
    }

    public var isDark: Bool { appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    /// `nil` lets a view follow the system.
    public var forcedAppearance: NSAppearance? { style.theme == .system ? nil : appearance }

    public static func nsColor(_ color: Color) -> NSColor {
        NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    public static func cgColor(_ color: Color) -> CGColor {
        CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    // MARK: Colors

    public var foreground: NSColor { style.foreground.map(Self.nsColor) ?? .labelColor }
    public var secondary: NSColor { style.secondary.map(Self.nsColor) ?? .secondaryLabelColor }
    public var tertiary: NSColor { style.secondary.map(Self.nsColor)?.withAlphaComponent(0.6) ?? .tertiaryLabelColor }
    public var accent: NSColor { style.accent.map(Self.nsColor) ?? .controlAccentColor }
    /// The highlight of the selected row of a list. Native: the selection color of the system, like a menu.
    public var selection: NSColor {
        if let color = style.selection { return Self.nsColor(color) }
        return style.isNative ? .selectedContentBackgroundColor : NSColor.labelColor.withAlphaComponent(0.09)
    }
    /// With the system selection color the text of the selected row turns to the color that the system pairs with it.
    public var usesSystemSelection: Bool { style.isNative && style.selection == nil }
    /// The color of text that sits on `selection`: `normal` when the row is not selected.
    public func text(_ normal: NSColor, selected: Bool) -> NSColor {
        selected && usesSystemSelection ? .alternateSelectedControlTextColor : normal
    }
    public var border: NSColor? { style.border.map(Self.nsColor) }
    public var separator: NSColor { border ?? .separatorColor }
    public var tint: NSColor? { style.background.map(Self.nsColor) }
    /// The opposite of the text: what sits under a badge.
    public var scrim: NSColor { isDark ? .black : .white }

    /// `color` as a layer color, in the appearance of the overlay (a dynamic color is fixed here, so call this at each show).
    public func cg(_ color: NSColor, alpha: CGFloat? = nil) -> CGColor {
        var out = color.cgColor
        appearance.performAsCurrentDrawingAppearance {
            let resolved = alpha.map { color.withAlphaComponent($0) } ?? color
            out = resolved.cgColor
        }
        return out
    }

    /// The text color with `alpha`, for the lines and fills that were once `white` at some opacity.
    public func ink(_ alpha: CGFloat = 1) -> CGColor {
        var out = foreground.cgColor
        appearance.performAsCurrentDrawingAppearance { out = foreground.withAlphaComponent(foreground.alphaComponent * alpha).cgColor }
        return out
    }

    public func inkColor(_ alpha: CGFloat = 1) -> NSColor {
        var out = foreground
        appearance.performAsCurrentDrawingAppearance { out = foreground.usingColorSpace(.sRGB) ?? foreground }
        return out.withAlphaComponent(out.alphaComponent * alpha)
    }

    public func scrimCG(_ alpha: CGFloat) -> CGColor { scrim.withAlphaComponent(alpha).cgColor }

    // MARK: Type

    /// `base` scaled by `font_size`, where 13 is the size that the overlays use for their text by default.
    public func size(_ base: CGFloat) -> CGFloat {
        guard let size = style.fontSize else { return base }
        return (base * CGFloat(size) / 13).rounded()
    }

    public func font(_ base: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        let points = size(base)
        if let name = style.font, let font = NSFont(name: name, size: points) { return font }
        return .systemFont(ofSize: points, weight: weight)
    }

    public func monoFont(_ base: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        let points = size(base)
        if let name = style.monoFont, let font = NSFont(name: name, size: points) { return font }
        return .monospacedSystemFont(ofSize: points, weight: weight)
    }

    // MARK: Chrome

    public var cornerRadius: CGFloat { CGFloat(style.radius) }
    public var duration: TimeInterval { style.animation }

    /// Sets the blur of `effect`. `material = "none"` hides the blur, and then only `background` colors the overlay.
    @MainActor
    public func configure(_ effect: NSVisualEffectView) {
        effect.appearance = forcedAppearance
        effect.blendingMode = .behindWindow
        switch style.material {
        case .none:
            // A flat surface: no blur, the system color of a window.
            effect.isHidden = false
            effect.material = .windowBackground
            effect.state = .inactive
        case .popover: show(effect, .popover)
        case .menu: show(effect, .menu)
        case .hud: show(effect, .hudWindow)
        case .sidebar: show(effect, .sidebar)
        case .sheet: show(effect, .sheet)
        case .window: show(effect, .windowBackground)
        }
    }

    @MainActor
    private func show(_ effect: NSVisualEffectView, _ material: NSVisualEffectView.Material) {
        effect.isHidden = false
        effect.state = .active
        effect.material = material
    }

    /// A stretchable mask that rounds the corners of a blur view.
    @MainActor
    public static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
