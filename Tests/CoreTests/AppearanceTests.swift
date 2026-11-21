import Foundation
import Testing
@testable import Core

struct AppearanceTests {
    private let red = Color(red: 1, green: 0, blue: 0)

    @Test func nativeLeavesEveryColorToTheSystem() {
        let style = AppearanceSettings().resolved()
        #expect(style.isNative)
        #expect(style.theme == .system)
        #expect(style.material == .popover)
        #expect(style.radius == 12)
        #expect(style.accent == nil && style.foreground == nil && style.selection == nil && style.border == nil)
        #expect(style.background == nil)
        #expect(style.overviewBackdrop == nil)
    }

    @Test func hudIsOneDarkLookForEveryOverlay() {
        var settings = AppearanceSettings()
        settings.style = .hud
        let style = settings.resolved()
        #expect(style.theme == .dark)
        #expect(style.material == .hud)
        #expect(style.radius == 20)
        #expect(style.accent == Color(red: 0.537, green: 0.706, blue: 0.980))
        #expect(style.background == Color(red: 0, green: 0, blue: 0, alpha: 0.35))
    }

    @Test func aKeyThatIsSetBeatsThePreset() {
        var settings = AppearanceSettings()
        settings.style = .hud
        settings.radius = 5
        settings.accent = red
        settings.theme = .light
        let style = settings.resolved()
        #expect(style.radius == 5)
        #expect(style.accent == red)
        #expect(style.theme == .light)
        #expect(style.material == .hud)
    }

    @Test func densityScalesTheSizes() {
        var settings = AppearanceSettings()
        #expect(settings.resolved().paletteRowHeight == 38)
        #expect(settings.resolved().paletteWidth == 750)
        #expect(settings.resolved().cheatsheetRowHeight == 32)
        settings.density = .compact
        #expect(settings.resolved().paletteRowHeight == 32)
        #expect(settings.resolved().paletteWidth == 638)
        settings.density = .spacious
        #expect(settings.resolved().paletteRowHeight == 46)
        #expect(settings.resolved().paletteWidth == 900)
        #expect(settings.resolved().cheatsheetRowHeight == 38)
        #expect(settings.resolved().scale == 1.2)
    }

    @Test func theOverviewBackdropIsTheBackgroundButNeverFullyOpaque() {
        var settings = AppearanceSettings()
        settings.background = Color(red: 0.1, green: 0.1, blue: 0.2)
        #expect(settings.resolved().overviewBackdrop == Color(red: 0.1, green: 0.1, blue: 0.2, alpha: 0.85))
        settings.background = Color(red: 0.1, green: 0.1, blue: 0.2, alpha: 0.4)
        #expect(settings.resolved().overviewBackdrop?.alpha == 0.4)
    }
}
