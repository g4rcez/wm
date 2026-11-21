import Core
import Foundation
import Testing
@testable import Scripting

struct AppearanceConfigTests {
    let host: LuaHost
    let dir: ConfigDir

    init() throws {
        host = LuaHost(bridge: FakeBridge())
        dir = try ConfigDir()
    }

    @Test func withoutTheKeyTheLookIsNative() throws {
        let config = try host.load(configURL: dir.write("init.lua", "wm.config { layout = 'tiling' }"))
        #expect(config.settings.appearance == AppearanceSettings())
        #expect(config.settings.appearance.style == .native)
        #expect(config.settings.appearance.density == .comfortable)
    }

    @Test func aFullTableParses() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.config {
          appearance = {
            style = "hud", density = "spacious", theme = "dark", material = "sidebar", accent = "#ff0000", background = "#00000080",
            foreground = "#ffffff", secondary = "#999999", selection = "#333333", border = "#444444", border_width = 2,
            radius = 6, shadow = false, font = "Menlo", font_size = 15, mono_font = "SF Mono", animation = 0,
          },
        }
        """))
        let appearance = config.settings.appearance

        #expect(appearance.style == .hud)
        #expect(appearance.density == .spacious)
        #expect(appearance.theme == .dark)
        #expect(appearance.material == .sidebar)
        #expect(appearance.accent == Color(red: 1, green: 0, blue: 0))
        #expect(appearance.background == Color(red: 0, green: 0, blue: 0, alpha: 128.0 / 255))
        #expect(appearance.borderWidth == 2)
        #expect(appearance.radius == 6)
        #expect(appearance.shadow == false)
        #expect(appearance.font == "Menlo")
        #expect(appearance.fontSize == 15)
        #expect(appearance.monoFont == "SF Mono")
        #expect(appearance.animation == 0)
    }

    @Test func removedKeysStillLoadAsAppearance() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.config {
          prefix = { label = { accent = "#ff0000", background = "#000000", font_size = 20 } },
          switcher = { selected = "#00ff00" },
          appearance = { accent = "#0000ff" },
        }
        """))
        let appearance = config.settings.appearance

        #expect(appearance.accent == Color(red: 0, green: 0, blue: 1), "an explicit appearance wins over a removed key")
        #expect(appearance.background == Color(red: 0, green: 0, blue: 0))
        #expect(appearance.fontSize == 20)
    }

    @Test func twoCallsMergeKeyByKey() throws {
        let config = try host.load(configURL: dir.write("init.lua", """
        wm.config { appearance = { radius = 8, density = "compact" } }
        wm.config { appearance = { accent = "#00ff00" } }
        """))
        let appearance = config.settings.appearance

        #expect(appearance.radius == 8)
        #expect(appearance.density == .compact)
        #expect(appearance.accent == Color(red: 0, green: 1, blue: 0))
    }

    @Test(arguments: [
        ("wm.config { appearance = { style = 'glass' } }", "'appearance.style' must be one of"),
        ("wm.config { appearance = { density = 'tiny' } }", "'appearance.density' must be one of"),
        ("wm.config { appearance = { theme = 'sepia' } }", "'appearance.theme' must be one of"),
        ("wm.config { appearance = { material = 'glass' } }", "'appearance.material' must be one of"),
        ("wm.config { appearance = { accent = 'blue' } }", "'appearance.accent' must be a color"),
        ("wm.config { appearance = { radius = 99 } }", "'appearance.radius' must be between 0 and 48"),
        ("wm.config { appearance = { shadow = 'yes' } }", "'appearance.shadow' must be true or false"),
        ("wm.config { appearance = { font_size = 2 } }", "'appearance.font_size' must be between 8 and 40"),
        ("wm.config { appearance = { palette = { radius = 4 } } }", "unknown key 'appearance.palette'"),
        ("wm.config { appearance = { width = 500 } }", "unknown key 'appearance.width'"),
    ])
    func badAppearanceIsAnError(source: String, message: String) throws {
        #expect(throws: (any Error).self) { try host.load(configURL: dir.write("init.lua", source)) }
        do {
            _ = try host.load(configURL: dir.write("init.lua", source))
        } catch {
            #expect("\(error)".contains(message), "\(error)")
        }
    }
}
