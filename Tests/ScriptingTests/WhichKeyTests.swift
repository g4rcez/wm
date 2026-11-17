import Core
import Testing
@testable import Scripting

struct WhichKeyTests {
    private func record(_ mode: String, _ keys: String, _ action: String, description: String? = nil, hidden: Bool = false, trigger: BindTrigger = .press) -> BindRecord {
        BindRecord(mode: mode, keys: keys, trigger: trigger, action: action, options: BindOptions(description: description, hidden: hidden))
    }

    private var resize: [BindRecord] {
        [
            record("resize", "l", "resize width -50"),
            record("resize", "esc", "mode main"),
            record("resize", "h", "resize width +50", description: "Wider"),
            record("resize", "k", "resize height -50", hidden: true),
            record("resize", "cmd-h", "noop"),
            record("resize", "j", "resize height +50", trigger: .release),
            record("main", "alt-r", "mode resize"),
            record("gesture", "alt-scroll left", "workspace prev"),
        ]
    }

    @Test func aHoldBindShowsOnceAndOnlyWhenTheKeyHasNoPlainBind() {
        let records = [
            record("main", "alt-a", "focus left"),
            record("main", "alt-a", "focus right", trigger: .hold),
            record("main", "alt-b", "focus up", trigger: .hold),
        ]
        #expect(WhichKey.entries(mode: "main", pending: [], records: records) == [
            LabelEntry(key: "⌥a", text: "focus left"),
            LabelEntry(key: "⌥b", text: "focus up"),
        ])
    }

    @Test func aModeListsItsOwnKeysInAFixedOrder() {
        #expect(WhichKey.entries(mode: "resize", pending: [], records: resize) == [
            LabelEntry(key: "h", text: "Wider"),
            LabelEntry(key: "l", text: "resize width -50"),
            LabelEntry(key: "esc", text: "exit"),
        ])
    }

    @Test func universalBindsAreInEveryMode() {
        let records = resize + [record(universalMode, "alt-q", "window close", description: "Close")]
        #expect(WhichKey.entries(mode: "resize", pending: [], records: records).map(\.key) == ["h", "l", "⌥q", "esc"])
        #expect(WhichKey.entries(mode: "main", pending: [], records: records).map(\.key) == ["⌥q", "⌥r"])
    }

    @Test func aLongCommandIsCut() {
        let records = [record("m", "a", "layout column width cycle then something longer")]
        #expect(WhichKey.entries(mode: "m", pending: [], records: records) == [
            LabelEntry(key: "a", text: "layout column width cycle t…"),
        ])
    }

    @Test func aPrefixListsTheKeysThatCanFollowIt() throws {
        let records = [
            record("main", "alt-space>h", "focus left"),
            record("main", "alt-space>l", "focus right", description: "Right"),
            record("main", "alt-space>w>n", "workspace next"),
            record("main", "alt-space>w>p", "workspace prev"),
            record("main", "ctrl-p>x", "close"),
            record("main", "alt-a", "balance"),
        ]
        let prefix = try parseChord("alt-space")
        #expect(WhichKey.entries(mode: "main", pending: [prefix], records: records) == [
            LabelEntry(key: "h", text: "focus left"),
            LabelEntry(key: "l", text: "Right"),
            LabelEntry(key: "w", text: "…"),
        ])
        #expect(WhichKey.entries(mode: "main", pending: [prefix, try parseChord("w")], records: records) == [
            LabelEntry(key: "n", text: "workspace next"),
            LabelEntry(key: "p", text: "workspace prev"),
        ])
    }

    @Test func aModeWithoutKeysHasNoEntries() {
        #expect(WhichKey.entries(mode: "empty", pending: [], records: resize) == [])
    }

    @Test func chordsAreDrawnWithSymbolsAndTheLetterAsItWasWritten() throws {
        #expect(WhichKey.display(try parseChord("ctrl-alt-shift-cmd-k")) == "⌃⌥⇧⌘k")
        #expect(WhichKey.display(try parseChord("hyper-w")) == "✦w")
        #expect(WhichKey.display(try parseChord("shift-y")) == "⇧y")
        #expect(WhichKey.display(try parseChord("esc")) == "esc")
        #expect(WhichKey.display(try parseChord("2")) == "2")
        #expect(WhichKey.display(try parseChord("f5")) == "f5")
    }

    @Test(arguments: [
        ("leftsquarebracket", "["), ("rightsquarebracket", "]"), ("comma", ","), ("period", "."), ("minus", "-"), ("equal", "="),
        ("slash", "/"), ("backslash", "\\"), ("semicolon", ";"), ("quote", "'"), ("backtick", "`"),
        ("left", "←"), ("right", "→"), ("up", "↑"), ("down", "↓"),
        ("space", "␣"), ("tab", "⇥"), ("enter", "↩"), ("backspace", "⌫"), ("delete", "⌦"), ("pageup", "⇞"), ("pagedown", "⇟"),
    ])
    func namedKeysAreDrawnAsGlyphs(name: String, glyph: String) throws {
        #expect(WhichKey.display(try parseChord(name)) == glyph)
        #expect(WhichKey.display(try parseChord("cmd-" + name)) == "⌘" + glyph)
    }
}
