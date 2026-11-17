import Testing
@testable import Scripting

@Suite("parseChord")
struct ChordTests {
    @Test(arguments: [
        ("alt-shift-h", Chord(modifiers: [.option, .shift], key: "h")),
        ("cmd + ctrl - 2", Chord(modifiers: [.command, .control], key: "2")),
        ("alt+minus", Chord(modifiers: [.option], key: "minus")),
        ("ctrl-alt-leftSquareBracket", Chord(modifiers: [.control, .option], key: "leftsquarebracket")),
        ("esc", Chord(modifiers: [], key: "esc")),
        ("shift-f12", Chord(modifiers: [.shift], key: "f12")),
        ("cmd-pageDown", Chord(modifiers: [.command], key: "pagedown")),
    ])
    func validChords(text: String, expected: Chord) throws {
        #expect(try parseChord(text) == expected)
    }

    @Test(arguments: [
        ("Alt-H", "alt-h"),
        ("opt-return", "alt-enter"),
        ("option-escape", "alt-esc"),
        ("command-leftarrow", "cmd-left"),
        ("control-downArrow", "ctrl-down"),
        ("alt-leftbracket", "alt-leftSquareBracket"),
        ("alt-rightBracket", "alt-rightsquarebracket"),
    ])
    func aliasesAndCaseGiveTheSameChord(text: String, same: String) throws {
        #expect(try parseChord(text) == parseChord(same))
    }

    @Test(arguments: [
        ("alt-foo", "unknown key 'foo'"),
        ("meta-h", "unknown modifier 'meta'"),
        ("alt-f21", "unknown key 'f21'"),
        ("alt-alt", "unknown key 'alt'"),
        ("", "it is empty"),
        ("alt-", "missing"),
        ("alt--h", "missing"),
    ])
    func invalidChords(text: String, reason: String) {
        let error = #expect(throws: ChordError.self) { try parseChord(text) }
        #expect(error?.message.contains(reason) == true)
        #expect(error?.message.contains("invalid chord '\(text)'") == true)
    }

    @Test(arguments: [
        ("alt-shift-h", "alt-shift-h"),
        ("cmd+ctrl-2", "ctrl-cmd-2"),
        ("cmd-shift-alt-ctrl-p", "ctrl-alt-shift-cmd-p"),
        ("option-escape", "alt-esc"),
        ("space", "space"),
    ])
    func descriptionIsCanonical(text: String, expected: String) throws {
        #expect(try parseChord(text).description == expected)
        #expect(try parseChord(expected) == parseChord(text))
    }
}

@Suite("screenshot shortcuts")
struct ScreenshotShortcutTests {
    @Test(arguments: ["cmd-shift-3", "cmd-shift-4", "cmd-shift-5", "cmd-shift-6", "cmd-ctrl-shift-4"])
    func macOSScreenshotShortcutsAreRecognized(text: String) throws {
        #expect(try parseChord(text).isScreenshotShortcut)
    }

    @Test(arguments: ["cmd-4", "shift-4", "cmd-shift-2", "cmd-shift-h", "cmd-alt-shift-4", "alt-shift-4"])
    func otherChordsAreNot(text: String) throws {
        #expect(!(try parseChord(text).isScreenshotShortcut))
    }
}
