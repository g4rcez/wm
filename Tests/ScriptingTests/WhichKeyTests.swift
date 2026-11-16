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

    @Test func aModeListsItsOwnKeysInAFixedOrder() {
        #expect(WhichKey.entries(mode: "resize", pending: [], records: resize) == [
            LabelEntry(key: "H", text: "Wider"),
            LabelEntry(key: "L", text: "resize width -50"),
            LabelEntry(key: "esc", text: "exit"),
        ])
    }

    @Test func universalBindsAreInEveryMode() {
        let records = resize + [record(universalMode, "alt-q", "window close", description: "Close")]
        #expect(WhichKey.entries(mode: "resize", pending: [], records: records).map(\.key) == ["H", "L", "⌥Q", "esc"])
        #expect(WhichKey.entries(mode: "main", pending: [], records: records).map(\.key) == ["⌥R", "⌥Q"].sorted())
    }

    @Test func aLongCommandIsCut() {
        let records = [record("m", "a", "layout column width cycle then something longer")]
        #expect(WhichKey.entries(mode: "m", pending: [], records: records) == [
            LabelEntry(key: "A", text: "layout column width cycle t…"),
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
            LabelEntry(key: "H", text: "focus left"),
            LabelEntry(key: "L", text: "Right"),
            LabelEntry(key: "W", text: "…"),
        ])
        #expect(WhichKey.entries(mode: "main", pending: [prefix, try parseChord("w")], records: records) == [
            LabelEntry(key: "N", text: "workspace next"),
            LabelEntry(key: "P", text: "workspace prev"),
        ])
    }

    @Test func aModeWithoutKeysHasNoEntries() {
        #expect(WhichKey.entries(mode: "empty", pending: [], records: resize) == [])
    }

    @Test func chordsAreDrawnWithSymbolsAndCapitalLetters() throws {
        #expect(WhichKey.display(try parseChord("ctrl-alt-shift-cmd-k")) == "⌃⌥⇧⌘K")
        #expect(WhichKey.display(try parseChord("esc")) == "esc")
        #expect(WhichKey.display(try parseChord("space")) == "space")
        #expect(WhichKey.display(try parseChord("2")) == "2")
    }
}
