import Common
import Foundation

import Darwin

func write(_ text: String, to handle: FileHandle) { handle.write(Data(text.utf8)) }

/// Error lines get colors only on a terminal, and never with NO_COLOR set.
let colorErrors = isatty(STDERR_FILENO) == 1 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

func printError(_ text: String) {
    guard colorErrors else { return write(text, to: .standardError) }
    let styled = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
        if line.hasPrefix("wm: error:") { return "\u{1B}[1;31mwm: error:\u{1B}[0m" + line.dropFirst("wm: error:".count) }
        if line.hasPrefix("hint:") { return "\u{1B}[36mhint:\u{1B}[0m" + line.dropFirst("hint:".count) }
        if line.hasPrefix("usage:") { return "\u{1B}[2musage:\u{1B}[0m" + line.dropFirst("usage:".count) }
        return String(line)
    }
    write(styled.joined(separator: "\n"), to: .standardError)
}

func die(_ message: String, hint: String? = nil, code: Int32 = 1) -> Never {
    printError("wm: error: \(message)\n" + (hint.map { "hint: \($0)\n" } ?? ""))
    exit(code)
}

var arguments = Array(CommandLine.arguments.dropFirst())

// `wm __complete <words>` is what the completion scripts call. It must see the words as typed, so it runs before the
// options are parsed. The daemon gives the windows, workspaces and modes; without it only the fixed words complete.
if arguments.first == "__complete" {
    func live(_ args: [String]) -> Data {
        (try? sendRequest(ClientRequest(args: args), timeoutSeconds: 1)).map { Data($0.stdout.utf8) } ?? Data()
    }
    var source = CompletionSource()
    source.windows = { parseLiveWindows(live(["list", "windows", "--json"])) }
    source.workspaces = { parseLiveWorkspaces(live(["list", "workspaces", "--json"])) }
    source.modes = { parseLiveModes(live(["list", "binds", "--json"])) }
    source.marks = { parseLiveMarks(live(["list", "windows", "--json"])) }
    write(renderCompletion(complete(Array(arguments.dropFirst()), source: source)), to: .standardOutput)
    exit(0)
}
/// `wm --window <id> <command>`: the command acts on that window instead of the focused one.
var windowId: UInt32?
var windowSelector: String?
do {
    let parsed = try parseWindowFlag(arguments)
    windowId = parsed.windowId
    windowSelector = parsed.selector
    arguments = parsed.rest
} catch let error as WindowFlagError {
    die(error.message, hint: "see `wm list windows`; selectors: focused, app:<name>, title:<regex>, mark:<name>, pid:<n>", code: 2)
}
// `-v` and `-h` are the short forms of --verbose and --help. Everything after `exec` belongs to the shell command.
if arguments.first != "exec" {
    arguments = arguments.map { $0 == "-v" ? "--verbose" : $0 == "-h" ? "--help" : $0 }
}

// Help and the version need no daemon.
if arguments.isEmpty {
    write(renderHelp() ?? "", to: .standardError)
    exit(2)
}
if arguments.first != "exec", arguments.contains("--help") || arguments.first == "help" {
    let topic = arguments.filter { $0 != "--help" && $0 != "help" && !$0.hasPrefix("--") }.joined(separator: " ")
    guard let text = renderHelp(topic: topic) else {
        die("no help for '\(topic)'", hint: unknownCommandHint(topic.split(separator: " ").first.map(String.init) ?? topic) ?? "run `wm help` to see the commands", code: 2)
    }
    write(text, to: .standardOutput)
    exit(0)
}
if arguments == ["version"] || arguments == ["--version"] {
    print("wm \(wmVersion)")
    exit(0)
}
if let first = arguments.first, !commandNames.contains(first) {
    die("unknown command '\(first)'", hint: unknownCommandHint(first) ?? "run `wm help` to see the commands", code: 2)
}
let localCommands = [["daemon", "start"], ["daemon", "stop"], ["subscribe"], ["logs"]]
if windowId != nil || windowSelector != nil, localCommands.contains(where: { Array(arguments.prefix($0.count)) == $0 }) {
    die("--window does not apply to '\(arguments.prefix(2).filter { !$0.hasPrefix("--") }.joined(separator: " "))'", code: 2)
}

/// The wm.app that this `wm` belongs to: `wm` lives in wm.app/Contents/MacOS, also when reached through a symlink.
func appBundle() -> URL? {
    var size: UInt32 = 0
    _NSGetExecutablePath(nil, &size)
    var buffer = [CChar](repeating: 0, count: Int(size))
    guard _NSGetExecutablePath(&buffer, &size) == 0, let real = realpath(buffer, nil) else { return nil }
    defer { free(real) }
    let bundle = URL(fileURLWithPath: String(cString: real)).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    if bundle.pathExtension == "app" { return bundle }
    let home = FileManager.default.homeDirectoryForCurrentUser
    return [URL(fileURLWithPath: "/Applications/wm.app"), home.appendingPathComponent("Applications/wm.app")]
        .first { FileManager.default.fileExists(atPath: $0.path) }
}

if arguments.first == "completion" {
    guard arguments.count == 2, let shell = CompletionShell(rawValue: arguments[1]) else {
        die("expected a shell name", hint: "usage: wm completion <\(CompletionShell.allCases.map(\.rawValue).joined(separator: "|"))>", code: 2)
    }
    print(completionScript(for: shell), terminator: "")
    exit(0)
}

if arguments.first == "logs" {
    let options: LogsOptions
    do { options = try LogsOptions(parsing: Array(arguments.dropFirst())) } catch let error as LogsOptions.Failure {
        die(error.message, hint: "usage: \(LogsOptions.usage)", code: 2)
    }
    let url = defaultLogURL()
    let tail = LogFile.tail(options.lines, from: url)
    if tail.records.isEmpty, !options.follow, !FileManager.default.fileExists(atPath: url.path) {
        printError("wm: no log yet (\(url.path))\n")
        exit(0)
    }
    func show(_ records: [LogRecord]) {
        guard !records.isEmpty else { return }
        write(records.map { options.format.render($0) + "\n" }.joined(), to: .standardOutput)
    }
    show(tail.records)
    guard options.follow else { exit(0) }
    var follower = LogFollower(offset: tail.offset)
    while true {
        usleep(250_000)
        show(follower.poll(url: url))
    }
}

if arguments.first == "lsp" {
    let flags = Set(arguments.dropFirst())
    if let unknown = flags.subtracting(["--write", "--force"]).sorted().first {
        die("unknown option \(unknown)", hint: "usage: wm lsp [--write] [--force]", code: 2)
    }
    guard let bundle = appBundle() else {
        die("cannot find wm.app", hint: "run `wm` from inside wm.app, or install wm.app in /Applications")
    }
    let types = bundle.appendingPathComponent("Contents/Resources/types")
    guard FileManager.default.fileExists(atPath: types.appendingPathComponent("wm.lua").path) else {
        die("this wm.app has no type stubs", hint: "build it again with ./build-app.sh")
    }
    let config = defaultConfigURL()
    let luarc = config.deletingLastPathComponent().appendingPathComponent(".luarc.json")
    let text = luarcJSON(typesPath: types.path)
    if flags.contains("--write") {
        if FileManager.default.fileExists(atPath: luarc.path), !flags.contains("--force") {
            die("\(luarc.path) exists already", hint: "use --force to replace it, or add \(types.path) to its workspace.library")
        }
        do {
            try FileManager.default.createDirectory(at: luarc.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: luarc, options: .atomic)
        } catch {
            die("cannot write \(luarc.path): \(error)")
        }
        print("wrote \(luarc.path)")
        print("Open \(config.path) in an editor with lua-language-server and it completes the wm API.")
    } else {
        print("type stubs  \(types.path)")
        print("config      \(config.path)")
        print("")
        print("Save this as \(luarc.path) (or run `wm lsp --write`):")
        print(text, terminator: "")
    }
    exit(0)
}

if arguments == ["daemon", "start"] {
    if (try? sendRequest(ClientRequest(args: ["version"]))) != nil {
        print("wm is already running")
        exit(0)
    }
    guard let bundle = appBundle() else {
        die("cannot find wm.app", hint: "run `wm` from inside wm.app, or install wm.app in /Applications")
    }
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-g", bundle.path]
    do { try open.run() } catch { die("cannot start \(bundle.path): \(error)") }
    open.waitUntilExit()
    for _ in 0..<50 {
        if (try? sendRequest(ClientRequest(args: ["version"]))) != nil {
            print("wm started in the background")
            exit(0)
        }
        usleep(100_000)
    }
    die("started \(bundle.path) but it did not answer within 5 seconds", hint: "grant Accessibility to wm when macOS asks, then run `wm daemon status`")
}

if arguments == ["daemon", "stop"] {
    do {
        _ = try sendRequest(ClientRequest(args: ["daemon", "stop"]))
        print("wm stopped")
    } catch {
        print("wm is not running")
    }
    exit(0)
}

if arguments == ["subscribe"] {
    // One JSON event per line until the daemon goes away.
    do {
        let connection = try connectToServer(path: defaultSocketPath(), timeoutSeconds: 0)
        try writeFrame(connection, JSONEncoder().encode(ClientRequest(args: arguments)))
        _ = try readFrame(connection)
        while true {
            let event = try readFrame(connection)
            FileHandle.standardOutput.write(event + Data("\n".utf8))
        }
    } catch SocketError.closed {
        exit(0)
    } catch {
        die("subscription ended: \(error)")
    }
}

do {
    let answer = try sendRequest(ClientRequest(args: arguments, windowId: windowId, windowSelector: windowSelector))
    write(answer.stdout, to: .standardOutput)
    printError(answer.stderr)
    exit(answer.exitCode)
} catch {
    // `daemon status` is how a script asks whether wm runs: answer it without an error.
    if arguments.first == "daemon", arguments.dropFirst().first == "status" {
        print(arguments.contains("--json") ? "{\"running\":false}" : "wm is not running")
        exit(1)
    }
    die("cannot reach the daemon: \(error)", hint: "start it with `wm daemon start`")
}
