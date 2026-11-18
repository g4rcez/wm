import Foundation
import Testing
@testable import Scripting

@Suite("shortcuts.toml", .serialized)
struct ShortcutsTests {
    let dir: ConfigDir

    init() throws { dir = try ConfigDir() }

    @Test func aMissingFileHasNoShortcuts() throws {
        #expect(try readShortcuts(at: dir.url.appendingPathComponent("shortcuts.toml")).isEmpty)
    }

    @Test func readsEveryOption() throws {
        let url = try dir.write("shortcuts.toml", """
            [[shortcut]]
            keys = "alt-h"
            action = "focus left"
            description = "Focus left"

            [[shortcut]]
            keys = "hyper-k"
            remap = "up"

            [[shortcut]]
            keys = "alt-r"
            mode = "resize"
            action = "mode main"
            long_press = 0.8
            hidden = true
            """)

        #expect(try readShortcuts(at: url) == [
            Shortcut(keys: "alt-h", action: "focus left", description: "Focus left"),
            Shortcut(keys: "hyper-k", remap: "up"),
            Shortcut(keys: "alt-r", action: "mode main", mode: "resize", longPress: .seconds(0.8), hidden: true),
        ])
    }

    @Test func rendersTheFileInAFixedOrder() {
        let text = renderShortcuts([
            Shortcut(keys: "alt-h", action: "focus left", description: "Focus \"left\""),
            Shortcut(keys: "alt-r", action: "mode main", mode: "resize", repeating: false, longPress: .on, universal: true),
        ])

        #expect(text == """
            # Managed by wm: the Shortcuts window rewrites this file and drops the comments.
            # init.lua loads it with wm.shortcuts(); a wm.bind in init.lua for the same keys replaces the shortcut.

            [[shortcut]]
            keys = "alt-h"
            action = "focus left"
            description = "Focus \\"left\\""

            [[shortcut]]
            keys = "alt-r"
            mode = "resize"
            action = "mode main"
            repeating = false
            long_press = true
            universal = true

            """)
    }

    @Test func whatIsWrittenIsReadBack() throws {
        let list = [
            Shortcut(keys: "ctrl-p>h", action: "focus left", description: "Sequence"),
            Shortcut(keys: "alt-j", action: "focus down", repeating: true),
            Shortcut(keys: "alt-k", action: "focus up", release: true),
            Shortcut(keys: "hyper-k", remap: "cmd-right"),
        ]
        let url = dir.url.appendingPathComponent("shortcuts.toml")

        try writeShortcuts(list, to: url)

        #expect(try readShortcuts(at: url) == list)
    }

    @Test func aWriteWithAnInvalidShortcutLeavesTheFileAsItIs() throws {
        let url = try dir.write("shortcuts.toml", "# mine\n")

        #expect(throws: ConfigError(message: "shortcut 1: keys 'alt-foo': invalid chord 'alt-foo': unknown key 'foo'")) {
            try writeShortcuts([Shortcut(keys: "alt-foo", action: "x")], to: url)
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "# mine\n")
    }

    @Test(arguments: [
        ("[[shortcut]]\nkeys = \"alt-h\"", "shortcuts.toml line 1: 'alt-h' needs an 'action' or a 'remap'"),
        ("[[shortcut]]\nkeys = \"alt-h\"\naction = \"a\"\nremap = \"up\"", "shortcuts.toml line 1: 'alt-h' has both 'action' and 'remap': use one"),
        ("[[shortcut]]\naction = \"a\"", "shortcuts.toml line 1: the shortcut needs 'keys'"),
        ("[[shortcut]]\nkeys = \"alt-h\"\naction = \"a\"\nspeed = 1", "shortcuts.toml line 4: unknown key 'speed' (allowed: action, description, hidden, keys, long_press, mode, release, remap, repeating, universal)"),
        ("[[shortcut]]\nkeys = \"alt-h\"\naction = 5", "shortcuts.toml line 3: 'action' must be a string"),
        ("[[shortcut]]\nkeys = \"alt-h\"\naction = \"a\"\nhidden = \"yes\"", "shortcuts.toml line 4: 'hidden' must be true or false"),
        ("[[shortcut]]\nkeys = \"alt-h\"\naction = \"a\"\nlong_press = 9", "shortcuts.toml line 1: 'long_press' for 'alt-h' must be between 0.1 and 3 seconds"),
        ("[[other]]\nkeys = \"alt-h\"", "shortcuts.toml line 1: unknown table [[other]]; the only table is [[shortcut]]"),
        ("[[shortcut]]\nkeys = \"alt-h\"\naction = \"a\"\n[[shortcut]]\nkeys = \"Alt-H\"\naction = \"b\"", "shortcuts.toml line 4: 'Alt-H' is the same bind as the shortcut at line 1"),
        ("[[shortcut]]\nkeys = \"alt-p\"\naction = \"a\"\n[[shortcut]]\nkeys = \"alt-p>h\"\naction = \"b\"", "shortcuts.toml line 4: 'alt-p>h' conflicts with 'alt-p' at line 1: a chord cannot also start a sequence"),
        ("[[shortcut]]\nkeys = \"alt-h\"\nremap = \"hyper-k\"", "shortcuts.toml line 1: remap of 'alt-h': 'hyper' is not a key that wm can type"),
        ("[[shortcut]]\nkeys = \"alt-h\"\naction = \"a\"\nx", "shortcuts.toml line 4: expected `key = value`"),
    ])
    func saysWhatIsWrongAndWhere(text: String, message: String) throws {
        let url = try dir.write("shortcuts.toml", text)

        #expect(throws: ConfigError(message: message)) { try readShortcuts(at: url) }
    }

    @Test func aPressAndAHoldOnTheSameKeysAreNotTheSameBind() throws {
        let list = [Shortcut(keys: "alt-j", action: "a"), Shortcut(keys: "alt-j", action: "b", repeating: true)]

        try validateShortcuts(list)
    }
}

/// The schema is for the completion of the editor: it has to describe the keys that wm reads.
struct ShortcutsSchemaTests {
    private func schema() throws -> [String: Any] {
        // Tests/ScriptingTests/ShortcutsTests.swift -> the repository root.
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appendingPathComponent("types/shortcuts.schema.json"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func theSchemaListsEveryKeyOfAShortcut() throws {
        let table = try #require(((try schema()["properties"] as? [String: Any])?["shortcut"] as? [String: Any])?["items"] as? [String: Any])
        let properties = try #require(table["properties"] as? [String: Any])

        #expect(Set(properties.keys) == Set(shortcutKeys))
        #expect(table["required"] as? [String] == ["keys"])
        #expect(table["additionalProperties"] as? Bool == false)
    }
}
