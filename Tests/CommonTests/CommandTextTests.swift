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
        #expect(urlBlockedCommands == ["exec", "daemon", "subscribe", "key"])
    }

    @Test func aBatchCannotCarryABlockedCommandForUrls() {
        #expect(urlBlockedCommand(in: ["exec", "open -a Calculator"], allowed: []) == "exec")
        #expect(urlBlockedCommand(in: ["batch", "focus left; exec 'touch x'"], allowed: []) == "exec")
        #expect(urlBlockedCommand(in: ["batch", "focus left; exec 'touch x'"], allowed: ["exec"]) == nil)
        #expect(urlBlockedCommand(in: ["batch", "focus left; workspace 2"], allowed: []) == nil)
        #expect(urlBlockedCommand(in: ["workspace", "2"], allowed: []) == nil)
        #expect(urlBlockedCommand(in: ["key", "press", "cmd-space"], allowed: []) == "key")
        #expect(urlBlockedCommand(in: ["batch", "key send cmd-q"], allowed: []) == "key")
    }

    @Test func aLeadingGlobalFlagDoesNotHideABlockedCommand() {
        #expect(urlBlockedCommand(in: ["--verbose", "exec", "open -a Calculator"], allowed: []) == "exec")
        #expect(urlBlockedCommand(in: ["--verbose", "key", "press", "cmd-space"], allowed: []) == "key")
        #expect(urlBlockedCommand(in: ["--verbose", "daemon", "stop"], allowed: []) == "daemon")
        #expect(urlBlockedCommand(in: ["-v", "exec", "x"], allowed: []) == "exec")
        #expect(urlBlockedCommand(in: ["--verbose", "--verbose", "exec", "x"], allowed: []) == "exec")
        #expect(urlBlockedCommand(in: ["batch", "--verbose exec 'touch x'"], allowed: []) == "exec")
        #expect(urlBlockedCommand(in: ["--verbose", "exec", "x"], allowed: ["exec"]) == nil)
        #expect(urlBlockedCommand(in: ["--verbose", "workspace", "2"], allowed: []) == nil)
        #expect(urlBlockedCommand(in: ["--verbose"], allowed: []) == nil)
    }

    @Test func aUrlThatStartsWithAFlagIsStillBlocked() throws {
        let url = try #require(URL(string: "wm://--verbose/exec?args=open%20-a%20Calculator"))
        let request = try #require(commandRequest(fromURL: url))
        #expect(urlBlockedCommand(in: request.args, allowed: []) == "exec")
    }

    @Test func verboseBeforeTheCommandOrAfterANormalCommandIsTheFlag() {
        #expect(stripVerbose(["focus", "left", "--verbose"]) == (["focus", "left"], true))
        #expect(stripVerbose(["--verbose", "focus", "left"]) == (["focus", "left"], true))
        #expect(stripVerbose(["list"]) == (["list"], false))
    }

    @Test func verboseAfterExecBelongsToTheShellCommand() {
        #expect(stripVerbose(["exec", "make", "--verbose"]) == (["exec", "make", "--verbose"], false))
        #expect(stripVerbose(["--verbose", "exec", "make", "--verbose"]) == (["exec", "make", "--verbose"], true))
    }

    @Test func batchSplitsAtSemicolonsOutsideQuotes() {
        #expect(splitBatch("workspace 2; layout set tiling") == ["workspace 2", "layout set tiling"])
        #expect(splitBatch("exec 'echo a; echo b'; focus left") == ["exec 'echo a; echo b'", "focus left"])
        #expect(splitBatch(" ; focus left ;; ") == ["focus left"])
        #expect(splitBatch("") == [])
    }
}
