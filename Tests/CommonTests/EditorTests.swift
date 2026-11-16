import Foundation
import Testing
@testable import Common

struct EditorTests {
    private let home = URL(fileURLWithPath: "/Users/test")

    @Test func theConfigIsInDotConfigByDefault() {
        #expect(defaultConfigURL(environment: [:], home: home).path == "/Users/test/.config/wm/init.lua")
    }

    @Test func xdgConfigHomeMovesTheConfig() {
        #expect(defaultConfigURL(environment: ["XDG_CONFIG_HOME": "/tmp/xdg"], home: home).path == "/tmp/xdg/wm/init.lua")
    }

    @Test func wmConfigNamesTheFileItself() {
        let environment = ["WM_CONFIG": "/tmp/custom/my.lua", "XDG_CONFIG_HOME": "/tmp/xdg"]
        #expect(defaultConfigURL(environment: environment, home: home).path == "/tmp/custom/my.lua")
    }

    @Test func emptyVariablesAreIgnored() {
        #expect(defaultConfigURL(environment: ["WM_CONFIG": "", "XDG_CONFIG_HOME": ""], home: home).path == "/Users/test/.config/wm/init.lua")
    }

    @Test func theLuarcPointsLuaLSAtTheStubs() throws {
        let text = luarcJSON(typesPath: "/Applications/wm.app/Contents/Resources/types")
        let object = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(object["runtime.version"] as? String == "Lua 5.4")
        #expect(object["workspace.library"] as? [String] == ["/Applications/wm.app/Contents/Resources/types"])
        #expect((object["diagnostics.neededFileStatus"] as? [String: String])?["undefined-field"] == "Any")
        // Slashes are not escaped, so the file is readable.
        #expect(text.contains("/Applications/wm.app/Contents/Resources/types"))
        #expect(text.hasSuffix("}\n"))
    }
}
