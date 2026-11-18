import Foundation
import Testing
@testable import Scripting

@Suite("TOML subset")
struct TomlTests {
    @Test func readsEveryValueType() throws {
        let tables = try parseToml("""
            [[shortcut]]
            keys = "alt-h"
            hidden = true
            count = 3
            seconds = 0.8
            """)

        #expect(tables.count == 1)
        #expect(tables[0].name == "shortcut")
        #expect(tables[0].values == ["keys": .string("alt-h"), "hidden": .bool(true), "count": .int(3), "seconds": .double(0.8)])
        #expect(tables[0].keyLines["count"] == 4)
    }

    @Test func readsManyTablesInOrder() throws {
        let tables = try parseToml("[[a]]\nx = 1\n\n# note\n[[b]]\nx = 2\n")

        #expect(tables.map(\.name) == ["a", "b"])
        #expect(tables.map(\.line) == [1, 5])
    }

    @Test func readsEscapesInBasicStringsAndKeepsLiteralStringsAsTheyAre() throws {
        let tables = try parseToml(#"""
            [[a]]
            basic = "say \"hi\"\n\t\\ \u00E9"
            literal = 'C:\path\n'
            """#)

        #expect(tables[0].values["basic"] == .string("say \"hi\"\n\t\\ é"))
        #expect(tables[0].values["literal"] == .string(#"C:\path\n"#))
    }

    @Test func aHashInsideAStringIsNotAComment() throws {
        let tables = try parseToml("[[a]] # header comment\nx = \"a # b\" # comment\n")

        #expect(tables[0].values["x"] == .string("a # b"))
    }

    @Test func windowsLineEndingsKeepTheLineNumbers() throws {
        let tables = try parseToml("[[a]]\r\nx = 1\r\n[[b]]\r\n")

        #expect(tables.map(\.line) == [1, 3])
    }

    @Test(arguments: [
        ("[[a]]\nx = \"open", 2, "the string is not closed"),
        ("[a]\nx = 1", 1, "only [[name]] tables are supported"),
        ("x = 1", 1, "'x' is outside of a [[table]]"),
        ("[[a]]\nx = 1\nx = 2", 3, "the key 'x' is set twice"),
        ("[[a]]\nx = alt", 2, "'alt' is not a string, boolean or number (strings need quotes)"),
        ("[[a]]\nx = 1 2", 2, "unexpected text after the value: '2'"),
        ("[[a]]\nx =", 2, "the key has no value"),
        ("[[a]]\nx = \"\\q\"", 2, "the escape \\q is not valid"),
        ("[[a]]\njust text", 2, "expected `key = value`"),
    ])
    func rejectsWhatItDoesNotUnderstand(text: String, line: Int, message: String) {
        #expect(throws: TomlError(line: line, message: message)) { try parseToml(text) }
    }

    @Test func quotesAndEscapesStrings() {
        #expect(tomlString("plain") == "\"plain\"")
        #expect(tomlString("a\"b\\c\nd") == "\"a\\\"b\\\\c\\nd\"")
        #expect(tomlString("\u{1}") == "\"\\u0001\"")
    }

    @Test func aWrittenStringIsReadBack() throws {
        let text = "tab\there \"q\" \\ line\nend é \u{7f}"

        let tables = try parseToml("[[a]]\nx = \(tomlString(text))")

        #expect(tables[0].values["x"] == .string(text))
    }
}
