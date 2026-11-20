import Foundation
import Testing
@testable import Common

private func words(_ result: CompletionResult) -> [String] {
    guard case let .candidates(list) = result else { return [] }
    return list.map(\.word)
}

private func source() -> CompletionSource {
    var source = CompletionSource()
    source.windows = { [LiveWindow(id: 71, app: "Writeme", title: "Notes"), LiveWindow(id: 55, app: "Telegram", title: "")] }
    source.workspaces = { ["1", "2", "special:term", "special"] }
    source.modes = { ["main", "resize"] }
    source.marks = { ["mail", "term"] }
    return source
}

@Suite("Completion")
struct CompletionTests {
    @Test func theRootCompletesEveryCommand() {
        let found = words(complete([""]))
        #expect(found.prefix(3) == ["focus", "move", "swap"])
        #expect(found.contains("completion"))
    }

    @Test func aCommandWithSubcommandsAndADirectionCompletesBoth() {
        #expect(words(complete(["focus", ""])) == ["back", "urgent", "urgent-or-last", "next", "prev", "mark", "app", "column", "stack", "window", "monitor", "layer", "left", "right", "up", "down"])
    }

    @Test func aGroupCompletesItsSubcommandsWithTheirSummary() {
        #expect(complete(["window", "send", ""]) == .candidates([
            CompletionCandidate("workspace", "Send the window to a workspace; --stay keeps the view."),
            CompletionCandidate("monitor", "Send the window to another monitor and follow it."),
            CompletionCandidate("strip", "Move the window to the other strip (scrolling)."),
        ]))
    }

    @Test func aPlaceholderIsNotACompletion() {
        // `<name|back>` completes `back`, never the word `name`; `<0.1-0.9|+n|-n>` completes nothing.
        #expect(words(complete(["workspace", ""])) == ["move", "float-all", "special", "back", "next", "prev", "empty"])
        #expect(words(complete(["layout", "split", "ratio", ""])) == [])
    }

    @Test func optionsComeFromTheCommandAndFromEveryCommand() {
        #expect(words(complete(["window", "send", "workspace", "3", "--"])) == ["--stay", "--tile", "--column", "--window", "--json", "--verbose", "--help"])
    }

    @Test func onlyTheFirstArgumentCompletes() {
        #expect(words(complete(["focus", "left", ""])) == [])
    }

    @Test func theWindowOptionTakesItsValueOutOfTheCommandPath() {
        #expect(words(complete(["--window", "focused", "layout", "column", ""])) == ["width", "match", "expand", "center", "center-visible", "move"])
    }

    @Test func execCompletesACommandThenFiles() {
        #expect(complete(["exec", ""]) == .command)
        #expect(complete(["exec", "--float", "open", ""]) == .file)
    }

    @Test func focusWindowCompletesTheIdsOfTheRunningWindows() {
        #expect(complete(["focus", "window", ""], source: source()) == .candidates([
            CompletionCandidate("55", "Telegram"),
            CompletionCandidate("71", "Writeme - Notes"),
        ]))
    }

    @Test func theWindowOptionCompletesSelectors() {
        #expect(words(complete(["--window", ""], source: source())) == ["focused", "55", "71", "app:Telegram", "app:Writeme"])
    }

    @Test func focusMarkCompletesTheMarksOfTheRunningWindows() {
        #expect(words(complete(["focus", "mark", ""], source: source())) == ["mail", "term"])
        #expect(words(complete(["window", "unmark", ""], source: source())) == ["mail", "term"])
    }

    @Test func marksComeFromTheListOfWindows() {
        let json = Data(#"[{"id":1,"marks":["term","mail"]},{"id":2,"marks":["mail"]},{"id":3,"marks":[]}]"#.utf8)
        #expect(parseLiveMarks(json) == ["mail", "term"])
    }

    @Test func workspaceCompletesTheExistingWorkspacesButNotTheSpecialOnes() {
        #expect(words(complete(["workspace", ""], source: source())) == ["move", "float-all", "special", "back", "next", "prev", "empty", "1", "2"])
        #expect(words(complete(["workspace", "special", ""], source: source())) == ["term"])
    }

    @Test func modeCompletesTheModesThatHaveBindsAndBack() {
        #expect(words(complete(["mode", "r"], source: source())) == ["back", "main", "resize"])
    }

    @Test func withoutTheDaemonOnlyTheFixedWordsComplete() {
        #expect(words(complete(["focus", "window", ""])) == [])
        #expect(words(complete(["workspace", ""])) == ["move", "float-all", "special", "back", "next", "prev", "empty"])
    }

    @Test func theOutputHasOneCandidatePerLine() {
        #expect(renderCompletion(.candidates([CompletionCandidate("71", "Writeme\n- Notes"), CompletionCandidate("left")])) == "71\tWriteme - Notes\nleft\n")
        #expect(renderCompletion(.command) == "@command\n")
    }

    @Test func theDaemonDocumentsBecomeCompletionData() {
        let windows = Data(#"[{"id":71,"app_name":"Writeme","title":"Notes"},{"title":"no id"}]"#.utf8)
        #expect(parseLiveWindows(windows) == [LiveWindow(id: 71, app: "Writeme", title: "Notes")])
        #expect(parseLiveWorkspaces(Data(#"[{"name":"1"},{"name":"special:term"}]"#.utf8)) == ["1", "special:term"])
        #expect(parseLiveModes(Data(#"[{"mode":"resize"},{"mode":"main"},{"mode":"main"}]"#.utf8)) == ["main", "resize"])
        #expect(parseLiveModes(Data()) == [])
    }

    @Test func eachShellScriptAsksTheCommandForCandidates() {
        let zsh = completionScript(for: .zsh)
        #expect(zsh.contains("compdef _wm wm"))
        #expect(zsh.contains("command wm __complete"))
        let bash = completionScript(for: .bash)
        #expect(bash.contains("complete -F _wm wm"))
        #expect(bash.contains("command wm __complete"))
    }
}

struct CommandSuggestionsTests {
    @Test func theFirstWordSuggestsCommandsThatStartWithIt() {
        let result = commandSuggestions(for: "foc")

        #expect(result.partial == "foc")
        #expect(result.words == ["focus"])
    }

    @Test func aSpaceSuggestsTheNextWords() {
        let result = commandSuggestions(for: "layout set ")

        #expect(result.partial == "")
        #expect(result.words == ["scrolling", "tiling", "master", "monocle", "floating"])
    }

    @Test func theLastWordFiltersTheNextWords() {
        let result = commandSuggestions(for: "layout set t")

        #expect(result.partial == "t")
        #expect(result.words == ["tiling"])
    }

    @Test func aFinishedWordSuggestsNothingForItself() {
        #expect(commandSuggestions(for: "layout set tiling").words == [])
    }

    @Test func anEmptyTextSuggestsEveryCommand() {
        let result = commandSuggestions(for: "")

        #expect(result.words.starts(with: ["focus", "move", "swap"]))
    }

    @Test func execHasNoSuggestions() {
        #expect(commandSuggestions(for: "exec op").words == [])
    }
}
