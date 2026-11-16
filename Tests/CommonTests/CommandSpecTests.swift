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
            "wm workspace special [name]",
            "wm workspace row <up|down|N>",
        ])
        #expect(usageLines(for: "nothing") == [])
    }

    @Test func helpForACommandHasItsUsageAndExample() {
        let help = renderHelp(topic: "swap")
        #expect(help == """
        wm swap <dir>
            Exchange places with the window in that direction.

        <dir> is left, right, up or down.

        """)
        #expect(renderHelp(topic: "resize")?.contains("example: wm resize width +50") == true)
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
