import Testing

@testable import Common

struct ToggleCommandTests {
    @Test func noArgumentsIsValidWithNoMode() {
        #expect(parseToggleArguments([]) == ToggleArguments(flags: [], mode: nil, isValid: true))
    }

    @Test(arguments: [("open", ToggleMode.open), ("close", .close), ("toggle", .toggle)])
    func eachModeWordIsValid(word: String, mode: ToggleMode) {
        #expect(parseToggleArguments([word]) == ToggleArguments(flags: [], mode: mode, isValid: true))
    }

    @Test func flagsAreCollectedWhateverTheirPlace() {
        #expect(parseToggleArguments(["--wait", "open"]) == ToggleArguments(flags: ["--wait"], mode: .open, isValid: true))
        #expect(parseToggleArguments(["open", "--wait"]) == ToggleArguments(flags: ["--wait"], mode: .open, isValid: true))
        #expect(parseToggleArguments(["--swap", "--close"]) == ToggleArguments(flags: ["--swap", "--close"], mode: nil, isValid: true))
    }

    @Test func anUnknownWordIsNotAMode() {
        #expect(parseToggleArguments(["bogus"]) == ToggleArguments(flags: [], mode: nil, isValid: false))
        #expect(parseToggleArguments(["Open"]).isValid == false)
    }

    @Test func twoWordsAreNotValidEvenWhenTheFirstIsAMode() {
        #expect(parseToggleArguments(["open", "close"]).isValid == false)
        #expect(parseToggleArguments(["open", "extra"]).isValid == false)
    }

    @Test func aBadModeStillReportsTheFlagsSoTheCallerCanCheckThemFirst() {
        // `wm hints --bogus bogus` must complain about the option, as it did before the words were parsed here.
        let parsed = parseToggleArguments(["--bogus", "bogus"])
        #expect(parsed.flags == ["--bogus"])
        #expect(!parsed.isValid)
    }

    @Test func hintsScopeDefaultsToAll() {
        let parsed = parseHintsArguments([])
        #expect(parsed.scope == .all)
        #expect(parsed.toggle == ToggleArguments(flags: [], mode: nil, isValid: true))
    }

    @Test func hintsScopeWordCanBeAnywhere() {
        let parsed = parseHintsArguments(["toggle", "window", "--wait"])
        #expect(parsed.scope == .window)
        #expect(parsed.toggle == ToggleArguments(flags: ["--wait"], mode: .toggle, isValid: true))
    }

    @Test func hintsTwoScopesOrAnUnknownWordAreNotValid() {
        #expect(parseHintsArguments(["all", "window"]).toggle.isValid == false)
        #expect(parseHintsArguments(["bogus"]).toggle.isValid == false)
    }
}
