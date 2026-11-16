import Common
import Foundation
import Testing

struct CommandTextTests {
    @Test func splitsOnWhitespace() {
        #expect(splitCommand("focus left") == ["focus", "left"])
    }

    @Test func quotesGroupWords() {
        #expect(splitCommand("resize width \"+50\"") == ["resize", "width", "+50"])
        #expect(splitCommand("layout 'a b'") == ["layout", "a b"])
    }

    @Test func execKeepsItsRestVerbatim() {
        #expect(splitCommand("exec touch '/tmp/a b' && echo done") == ["exec", "touch '/tmp/a b' && echo done"])
    }

    @Test func emptyCommandHasNoWords() {
        #expect(splitCommand("   ") == [])
    }

    @Test func urlHostIsTheCommandAndArgsQueryItsArguments() {
        #expect(commandWords(fromURL: URL(string: "wm://focus?args=left")!) == ["focus", "left"])
    }

    @Test func urlPathComponentsAreArguments() {
        #expect(commandWords(fromURL: URL(string: "wm://workspace/2")!) == ["workspace", "2"])
        #expect(commandWords(fromURL: URL(string: "wm://window/send/workspace/2?args=--stay")!) == ["window", "send", "workspace", "2", "--stay"])
    }

    @Test func urlArgsArePercentDecoded() {
        #expect(commandWords(fromURL: URL(string: "wm://resize?args=width%20%2B50")!) == ["resize", "width", "+50"])
    }

    @Test func urlExecKeepsOneShellString() {
        #expect(commandWords(fromURL: URL(string: "wm://exec?args=open%20-a%20%27Visual%20Studio%20Code%27")!) == ["exec", "open -a 'Visual Studio Code'"])
    }

    @Test func otherSchemesAndEmptyUrlsAreRejected() {
        #expect(commandWords(fromURL: URL(string: "https://focus?args=left")!) == nil)
        #expect(commandWords(fromURL: URL(string: "wm://")!) == nil)
    }

    @Test func dangerousCommandsAreBlockedForUrls() {
        #expect(urlBlockedCommands == ["exec", "daemon", "subscribe"])
    }

    @Test func batchSplitsAtSemicolonsOutsideQuotes() {
        #expect(splitBatch("workspace 2; layout set tiling") == ["workspace 2", "layout set tiling"])
        #expect(splitBatch("exec 'echo a; echo b'; focus left") == ["exec 'echo a; echo b'", "focus left"])
        #expect(splitBatch(" ; focus left ;; ") == ["focus left"])
        #expect(splitBatch("") == [])
    }
}
