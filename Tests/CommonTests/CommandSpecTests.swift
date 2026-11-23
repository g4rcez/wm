import Foundation
import Testing
@testable import Common

struct CommandSpecTests {
    @Test func everyRenamedCommandPointsToACommandThatExists() {
        // `layout rotate cw` -> the words that are not placeholders must start with the words of one command.
        for (old, replacement) in renamedCommands {
            let words = replacement.split(separator: " ").map(String.init).filter { !$0.hasPrefix("<") && !$0.hasPrefix("[") }
            let found = commandSpecs.contains { Array(words.prefix($0.words.count)) == $0.words }
            #expect(found, "\(old) -> \(replacement)")
        }
    }

    /// Weak on purpose: it checks the last word of each command path in the table of cli.md, so a multi-word command can hide behind a
    /// common last word. It still catches the usual drift: a command that has no row at all.
    @Test func everyCommandIsInTheCliDoc() throws {
        // Tests/CommonTests/CommandSpecTests.swift -> the repository root.
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { root.deleteLastPathComponent() }
        let doc = try String(contentsOf: root.appendingPathComponent("docs/src/content/docs/cli.md"), encoding: .utf8)
        let fence = "```"
        let parts = doc.components(separatedBy: fence)
        try #require(parts.count >= 3, "cli.md has no fenced command table")
        let table = parts[1]
        func isWordCharacter(_ character: Character) -> Bool { character.isLetter || character.isNumber || character == "-" }
        func contains(word: String) -> Bool {
            var rest = table[...]
            while let range = rest.range(of: word) {
                let before = range.lowerBound == table.startIndex ? nil : table[table.index(before: range.lowerBound)]
                let after = range.upperBound == table.endIndex ? nil : table[range.upperBound]
                if !(before.map(isWordCharacter) ?? false), !(after.map(isWordCharacter) ?? false) { return true }
                rest = rest[range.upperBound...]
            }
            return false
        }
        let missing = commandSpecs.filter { !contains(word: $0.words.last ?? "") }.map(\.path)
        #expect(missing.isEmpty, "cli.md has no row for: \(missing)")
    }

    @Test func noOldNameIsAlsoANewName() {
        #expect(commandNames.isDisjoint(with: renamedCommands.keys))
    }

    @Test func aRenamedCommandSaysItsNewName() {
        #expect(unknownCommandHint("togglefloating") == "'togglefloating' is now `wm window float`")
        #expect(unknownCommandHint("movetoworkspace") == "'movetoworkspace' is now `wm window send workspace <name>`")
    }

    @Test func aTypoGetsTheClosestCommand() {
        #expect(unknownCommandHint("fcous") == "did you mean `wm focus`?")
        #expect(unknownCommandHint("layuot") == "did you mean `wm layout`?")
    }

    @Test func aWordThatIsNotCloseToAnythingGetsNoHint() {
        #expect(unknownCommandHint("zzzzzzzz") == nil)
    }

    @Test func usageListsEveryCommandOfAGroup() {
        #expect(usageLines(for: "layout split") == [
            "wm layout split <toggle|swap>",
            "wm layout split root",
            "wm layout split ratio <0.1-0.9|+n|-n>",
        ])
        #expect(usageLines(for: "workspace") == [
            "wm workspace <name|back>",
            "wm workspace all <layout>",
            "wm workspace move monitor <monitor>",
            "wm workspace float-all [off|pattern]",
            "wm workspace special [name]",
        ])
        #expect(usageLines(for: "nothing") == [])
    }

    @Test func helpForACommandHasItsUsageAndExample() {
        #expect(renderHelp(topic: "swap") == """
        wm swap <dir> [--wrap]

          Exchange places with the window in that direction.

          With --wrap, or wrap_focus in the config, the window at the edge trades places with the window at
          the other end.

        Options
          --wrap  At the edge of the workspace, trade places with the window at the other end.

        <dir> is left, right, up or down.

        """)
        #expect(renderHelp(topic: "resize")?.contains("Example\n  wm resize width +50") == true)
    }

    @Test func helpForACommandWithOptionsExplainsEachOne() {
        let help = renderHelp(topic: "window send workspace") ?? ""
        #expect(help.contains("Options\n  --stay    Keep the view where it is; do not follow the window."))
        #expect(help.contains("  --column  Send the whole column"))
    }

    @Test func helpForAGroupListsItsCommandsWithTheirSummary() {
        #expect(renderHelp(topic: "workspace special") == """
        wm workspace special [name]

          Show or hide a special workspace (default: special).

        Example
          wm workspace special term

        """)
        #expect(renderHelp(topic: "layout split")?.contains("Related\n  wm layout split root\n      Make the window a child of the root: half the screen.") == true)
        #expect(renderHelp(topic: "window")?.hasPrefix("window\n  wm window close\n      Close the window.\n") == true)
    }

    @Test func colorsWrapEachKindOfWordAndNothingElse() {
        #expect(renderHelp(topic: "swap", style: HelpStyle(enabled: true)) == """
        wm \u{1B}[1mswap\u{1B}[0m \u{1B}[36m<dir>\u{1B}[0m \u{1B}[33m[--wrap]\u{1B}[0m

          Exchange places with the window in that direction.

          With --wrap, or wrap_focus in the config, the window at the edge trades places with the window at
          the other end.

        \u{1B}[1;36mOptions\u{1B}[0m
          \u{1B}[33m--wrap\u{1B}[0m  At the edge of the workspace, trade places with the window at the other end.

        \u{1B}[2m<dir> is left, right, up or down.\u{1B}[0m

        """)
    }

    @Test func everyOptionOfACommandIsExplained() {
        for spec in commandSpecs {
            let named = spec.flags.split(whereSeparator: { " []=".contains($0) }).filter { $0.hasPrefix("-") }.map(String.init)
            let explained = (commandOptions[spec.path] ?? []).flatMap { $0.flag.split(whereSeparator: { ", =".contains($0) }) }.map(String.init)
            for flag in named {
                #expect(explained.contains(flag), "\(spec.path) \(flag)")
            }
        }
    }

    @Test func optionsAreOnlyExplainedForCommandsThatExist() {
        let paths = Set(commandSpecs.map(\.path))
        #expect(Set(commandOptions.keys).isSubset(of: paths))
    }

    @Test func reflowJoinsAParagraphAndKeepsAListAsItIs() {
        #expect(reflow("one two\nthree four five\n  item a\n  item b\n\nsix", width: 12) == ["one two", "three four", "five", "  item a", "  item b", "", "six"])
    }

    @Test func colorsAreOffWithoutATerminalOrWithNoColor() {
        #expect(HelpStyle.detect(isTerminal: true, environment: [:]).enabled)
        #expect(!HelpStyle.detect(isTerminal: false, environment: [:]).enabled)
        #expect(!HelpStyle.detect(isTerminal: true, environment: ["NO_COLOR": "1"]).enabled)
        #expect(!HelpStyle.detect(isTerminal: true, environment: ["TERM": "dumb"]).enabled)
        #expect(HelpStyle.detect(isTerminal: false, environment: ["CLICOLOR_FORCE": "1"]).enabled)
        #expect(!HelpStyle.detect(isTerminal: false, environment: ["CLICOLOR_FORCE": "0"]).enabled)
        #expect(!HelpStyle.detect(isTerminal: true, environment: ["CLICOLOR_FORCE": "1", "NO_COLOR": "1"]).enabled)
    }

    @Test func helpForUnknownTopicIsNil() {
        #expect(renderHelp(topic: "togglefloating") == nil)
    }

    @Test func overviewMentionsEveryCommandOnce() {
        let overview = renderHelp() ?? ""
        for spec in commandSpecs {
            #expect(overview.contains("  " + spec.signature), "\(spec.path)")
        }
    }

    @Test func overviewLinesStayInsideAHundredColumns() {
        for line in (renderHelp() ?? "").split(separator: "\n") {
            #expect(line.count <= 100, "\(line)")
        }
    }
}
