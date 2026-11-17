import Testing
@testable import Scripting
import Core

struct RuntimeInputTests {
    @Test func execWithoutOptionsKeepsTheCommandAsItIs() throws {
        let parsed = try parseExecRule("open -a Notes")
        #expect(parsed.rule == nil)
        #expect(parsed.command == "open -a Notes")
    }

    @Test func execOptionsMakeARuleForTheNewWindow() throws {
        let parsed = try parseExecRule("--float --center --size 0.5,0.4 --workspace 3 -- /Applications/Foo.app/Contents/MacOS/foo --flag")
        #expect(parsed.rule == WindowRule(float: true, center: true, stop: true).with {
            $0.workspace = "3"
            $0.size = RuleSize(width: 0.5, height: 0.4)
        })
        #expect(parsed.command == "/Applications/Foo.app/Contents/MacOS/foo --flag")
    }

    @Test func optionsMayUseAnEqualsSign() throws {
        let parsed = try parseExecRule("--width=0.4 --monitor=LG --maximize --no-focus foo")
        #expect(parsed.rule?.width == 0.4)
        #expect(parsed.rule?.monitor == "LG")
        #expect(parsed.rule?.maximize == true)
        #expect(parsed.rule?.focus == false)
        #expect(parsed.command == "foo")
    }

    @Test func anOptionWeDoNotKnowStartsTheCommand() throws {
        let parsed = try parseExecRule("--float --verbose-tool run")
        #expect(parsed.rule?.float == true)
        #expect(parsed.command == "--verbose-tool run")
    }

    @Test(arguments: [
        ("--workspace", "exec: --workspace needs a value"),
        ("--width 2 foo", "exec: --width must be between 0.05 and 1"),
        ("--size 5 foo", "exec: --size needs <width>,<height>"),
        ("--layout grid foo", "exec: --layout must be scrolling, tiling or master"),
    ])
    func badExecOptionsAreErrors(text: String, expected: String) {
        let error = #expect(throws: ConfigError.self) { _ = try parseExecRule(text) }
        #expect(error?.message.contains(expected) == true)
    }

    @Test func setChangesOneValueByItsPath() throws {
        var settings = Settings()
        try applyRuntimeSetting(path: "gaps.inner", value: "4", to: &settings)
        try applyRuntimeSetting(path: "tiling.split_ratio", value: "0.6", to: &settings)
        try applyRuntimeSetting(path: "border.enabled", value: "true", to: &settings)
        try applyRuntimeSetting(path: "scrolling.presets", value: "0.25,0.5,1", to: &settings)
        try applyRuntimeSetting(path: "layout", value: "scrolling", to: &settings)
        #expect(settings.gaps.inner == 4)
        #expect(settings.tiling.splitRatio == 0.6)
        #expect(settings.border.enabled)
        #expect(settings.scrolling.presets == [0.25, 0.5, 1])
        #expect(settings.layout == .scrolling)
    }

    @Test(arguments: [
        ("gaps.innr", "4", "unknown key 'gaps.innr'"),
        ("gaps.inner", "-1", "'gaps.inner' must be at least 0"),
        ("tiling.split_ratio", "high", "'tiling.split_ratio' must be a number"),
        ("workspaces", "native", "can only change in the config file"),
        ("url.allow", "exec", "can only change in the config file"),
        ("gaps..inner", "1", "is not a setting name"),
    ])
    func badSettingsAreErrors(path: String, value: String, expected: String) {
        var settings = Settings()
        let error = #expect(throws: ConfigError.self) { try applyRuntimeSetting(path: path, value: value, to: &settings) }
        #expect(error?.message.contains(expected) == true)
    }
}

private extension WindowRule {
    func with(_ change: (inout WindowRule) -> Void) -> WindowRule {
        var copy = self
        change(&copy)
        return copy
    }
}
