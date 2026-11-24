import Cheatsheet
import Common
import Foundation
import Scripting

import Darwin

func write(_ text: String, to handle: FileHandle) { handle.write(Data(text.utf8)) }

/// Colors only on a terminal, and never with NO_COLOR set. One style for each stream, because either one can be a pipe.
let errorStyle = HelpStyle.detect(isTerminal: isatty(STDERR_FILENO) == 1, environment: ProcessInfo.processInfo.environment)
let outputStyle = HelpStyle.detect(isTerminal: isatty(STDOUT_FILENO) == 1, environment: ProcessInfo.processInfo.environment)

func printError(_ text: String) {
    guard errorStyle.enabled else { return write(text, to: .standardError) }
    let styled = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
        if line.hasPrefix("wm: error:") { return errorStyle.error("wm: error:") + line.dropFirst("wm: error:".count) }
        if line.hasPrefix("hint:") { return errorStyle.hint("hint:") + line.dropFirst("hint:".count) }
        if line.hasPrefix("usage:") { return errorStyle.dim("usage:") + line.dropFirst("usage:".count) }
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
    // `windows` and `marks` read the same list: ask the daemon once, and only when one of them is needed.
    var windowsJson: Data?
    func liveWindows() -> Data {
        if let windowsJson { return windowsJson }
        let data = live(["list", "windows", "--json"])
        windowsJson = data
        return data
    }
    source.windows = { parseLiveWindows(liveWindows()) }
    source.workspaces = { parseLiveWorkspaces(live(["list", "workspaces", "--json"])) }
    source.modes = { parseLiveModes(live(["list", "binds", "--json"])) }
    source.marks = { parseLiveMarks(liveWindows()) }
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
    write(renderHelp(style: errorStyle) ?? "", to: .standardError)
    exit(2)
}
if arguments.first != "exec", arguments.contains("--help") || arguments.first == "help" {
    let topic = arguments.filter { $0 != "--help" && $0 != "help" && !$0.hasPrefix("--") }.joined(separator: " ")
    guard let text = renderHelp(topic: topic, style: outputStyle) else {
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
let localCommands = [["daemon", "start"], ["daemon", "stop"], ["subscribe"], ["logs"], ["pick"], ["init"], ["config", "check"], ["doctor"], ["cheatsheet"], ["skills"]]
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

if arguments.first == "cheatsheet" {
    let words = Array(arguments.dropFirst())
    let usage = "usage: wm cheatsheet [tui|gui|cli]"
    guard words.count <= 1, words.first.map({ ["tui", "gui", "cli"].contains($0) }) ?? true else {
        die("expected tui, gui or cli", hint: usage, code: 2)
    }
    // Without a word: a terminal gets the sheet in the terminal; a bind, a script or a launcher (no terminal) gets the panel.
    let onTerminal = isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
    if words.first == "gui" || (words.isEmpty && !onTerminal) {
        arguments = ["cheatsheet", "gui"]
    } else {
        var binds: [CheatBind] = []
        var mode: String?
        if let answer = try? sendRequest(ClientRequest(args: ["list", "binds", "--json"]), timeoutSeconds: 2), answer.exitCode == 0 {
            binds = CheatBind.decode(json: Data(answer.stdout.utf8))
            if let status = try? sendRequest(ClientRequest(args: ["daemon", "status", "--json"]), timeoutSeconds: 2),
               let object = try? JSONSerialization.jsonObject(with: Data(status.stdout.utf8)) as? [String: Any] {
                mode = object["mode"] as? String
            }
        } else {
            // wm does not run: the sheet reads the config, as `wm config check` does.
            let config = defaultConfigURL()
            switch loadBindRecords(at: config) {
            case .success(let records): binds = records.map(CheatBind.init)
            case .failure(let error): die(error.message, hint: "run `wm init <osx|windows|i3|hyprland|niri>` to make a config, or `wm daemon start`")
            }
        }
        let sheet = buildCheatsheet(binds)
        if words.first == "cli" {
            // The keys as plain text, one bind per line, for grep, less, more and cat.
            write(renderPlainCheatsheet(sheet), to: .standardOutput)
            exit(0)
        }
        if onTerminal, ProcessInfo.processInfo.environment["TERM"] != "dumb", !sheet.pages.isEmpty {
            runCheatsheetScreen(sheet, mode: mode, color: outputStyle.enabled)
        } else {
            printCheatsheet(sheet, color: outputStyle.enabled)
        }
        exit(0)
    }
}

if arguments.first == "skills" {
    guard arguments.count == 1 else { die("skills takes no argument", hint: "usage: wm skills", code: 2) }
    write(renderSkill(), to: .standardOutput)
    exit(0)
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
    // An app built before `shortcuts.toml` has no schema: then there is nothing to set up for it.
    let schema = types.appendingPathComponent("shortcuts.schema.json")
    let taplo = config.deletingLastPathComponent().appendingPathComponent(".taplo.toml")
    let taploText = FileManager.default.fileExists(atPath: schema.path) ? taploConfig(schemaURL: schema.absoluteString) : nil
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
        if let taploText {
            if FileManager.default.fileExists(atPath: taplo.path), !flags.contains("--force") {
                print("\n\(taplo.path) exists already: add this to it, or use --force to replace it:")
                print(taploText, terminator: "")
            } else {
                do { try Data(taploText.utf8).write(to: taplo, options: .atomic) } catch { die("cannot write \(taplo.path): \(error)") }
                print("wrote \(taplo.path)")
                print("An editor with Taplo (Even Better TOML) completes and checks shortcuts.toml.")
            }
        }
    } else {
        print("type stubs  \(types.path)")
        print("config      \(config.path)")
        print("")
        print("Save this as \(luarc.path) (or run `wm lsp --write`):")
        print(text, terminator: "")
        if let taploText { print("\nFor shortcuts.toml, save this as \(taplo.path):\n\(taploText)", terminator: "") }
    }
    exit(0)
}

if arguments.first == "init" {
    let usage = "usage: wm init [<\(InitTemplate.allCases.map(\.rawValue).joined(separator: "|"))>] [--mod=<\(initModKeys.joined(separator: "|"))>] [--lua] [--force]"
    var rest = Array(arguments.dropFirst())
    let force = rest.contains("--force")
    rest.removeAll { $0 == "--force" }
    let luaOnly = rest.contains("--lua")
    rest.removeAll { $0 == "--lua" }
    var mod = rest.first { $0.hasPrefix("--mod=") }.map { String($0.dropFirst("--mod=".count)) }
    rest.removeAll { $0.hasPrefix("--mod=") }
    // No name: the first template, Omarchy.
    guard rest.count <= 1, let template = rest.isEmpty ? InitTemplate.allCases.first : InitTemplate(rawValue: rest[0]) else {
        die("expected one template name", hint: usage, code: 2)
    }
    if let given = mod, !initModKeys.contains(given) { die("unknown mod key '\(given)'", hint: usage, code: 2) }
    if let given = mod, !template.mods.contains(given) { die("the \(template.rawValue) template cannot use '\(given)' as its mod key", hint: "use one of: \(template.mods.joined(separator: ", "))", code: 2) }
    if mod == nil {
        if isatty(STDIN_FILENO) == 1 {
            // Enter alone takes the default of the template; another answer is asked again.
            while mod == nil {
                write("mod key [\(template.mods.joined(separator: "|"))] (default \(template.defaultMod)): ", to: .standardError)
                guard let answer = readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespaces).lowercased() else { exit(1) }
                if answer.isEmpty { mod = template.defaultMod } else if template.mods.contains(answer) { mod = answer }
            }
        } else {
            mod = template.defaultMod
            printError("wm: mod key is \(template.defaultMod) (use --mod=<key> to choose another)\n")
        }
    }
    let chosenMod = mod ?? template.defaultMod
    let config = defaultConfigURL()
    do {
        if luaOnly {
            let text = initConfig(template, mod: chosenMod)
            if try writeInitConfig(text, to: config, force: force) {
                print("wrote \(config.path)")
            } else {
                printError("wm: \(config.path) exists; printed the template instead (use --force to replace the file)\n")
                print(text, terminator: "")
                exit(0)
            }
        } else {
            let files = try initFiles(template, mod: chosenMod)
            if try writeInitFiles(files, to: config, force: force) {
                print("wrote \(config.path)")
                print("wrote \(shortcutsURL(for: config).path)")
            } else {
                printError("wm: \(config.path) or \(shortcutsFileName) exists; printed the template instead (use --force to replace the files)\n")
                print("-- \(config.lastPathComponent)\n\(files.lua)\n# \(shortcutsFileName)\n\(files.shortcuts)", terminator: "")
                exit(0)
            }
        }
        print("wm loads it when it starts, and again each time that you save it. `wm daemon start` starts wm.")
    } catch {
        die("cannot write \(config.path): \(error)")
    }
    exit(0)
}

if arguments.first == "config" {
    guard arguments.count <= 3, arguments.count >= 2, arguments[1] == "check" else {
        die("expected `check [path]`", hint: "usage: wm config check [path]", code: 2)
    }
    let url = arguments.count == 3 ? URL(fileURLWithPath: arguments[2]) : defaultConfigURL()
    switch checkConfig(at: url) {
    case .success(let summary):
        print("ok: \(url.path) (\(summary.binds) binds)")
        for conflict in summary.overrides { print("warn: \(conflict)") }
        exit(0)
    case .failure(let error):
        die(error.message)
    }
}

if arguments.first == "doctor" {
    let flags = Set(arguments.dropFirst())
    if let unknown = flags.subtracting(["--json"]).sorted().first {
        die("unknown option \(unknown)", hint: "usage: wm doctor [--json]", code: 2)
    }
    var checks: [DoctorCheck] = []
    let config = defaultConfigURL()
    var summary = ConfigSummary(binds: 0)
    if !FileManager.default.fileExists(atPath: config.path) {
        checks.append(DoctorCheck("config", .warn, "no config at \(config.path): wm has no key binds", hint: "run `wm init <osx|windows|i3|hyprland|niri>`"))
    } else {
        switch checkConfig(at: config) {
        case .success(let result):
            summary = result
            checks.append(DoctorCheck("config", .ok, "\(config.path) (\(result.binds) binds)"))
        case .failure(let error): checks.append(DoctorCheck("config", .fail, error.message, hint: "fix the line, then save: wm loads the file again"))
        }
    }
    let shortcutsFile = shortcutsURL(for: config)
    var shortcutCount = 0
    var shortcutProblem: String?
    do { shortcutCount = try readShortcuts(at: shortcutsFile).count } catch { shortcutProblem = "\(error)" }
    checks.append(shortcutsCheck(
        fileExists: FileManager.default.fileExists(atPath: shortcutsFile.path), imported: summary.shortcutsImported,
        count: shortcutCount, problem: shortcutProblem, overrides: summary.overrides.map(\.description)))
    if let answer = try? sendRequest(ClientRequest(args: ["version"]), timeoutSeconds: 2), answer.exitCode == 0 {
        // "wm 0.1.0 (Lua 5.4)": the daemon may be an older build than this `wm`.
        let running = answer.stdout.split(separator: " ").dropFirst().first.map(String.init) ?? "?"
        checks.append(
            running == wmVersion
                ? DoctorCheck("daemon", .ok, "runs, version \(running)")
                : DoctorCheck("daemon", .warn, "runs version \(running), and this wm is \(wmVersion)", hint: "run `wm daemon stop`, then `wm daemon start`"))
        if let facts = try? sendRequest(ClientRequest(args: ["doctor"]), timeoutSeconds: 2),
           let decoded = try? JSONDecoder().decode(DoctorFacts.self, from: Data(facts.stdout.utf8)) {
            checks += daemonChecks(decoded)
        } else {
            checks.append(DoctorCheck("permissions", .warn, "the daemon did not answer the checks", hint: "it may be older than this wm: run `wm daemon stop`, then `wm daemon start`"))
        }
    } else {
        checks.append(DoctorCheck("daemon", .fail, "wm does not run", hint: "run `wm daemon start`"))
        checks.append(DoctorCheck("permissions", .skip, "they need the daemon"))
    }
    if flags.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        print(String(decoding: (try? encoder.encode(checks)) ?? Data("[]".utf8), as: UTF8.self))
    } else {
        print(renderDoctor(checks), terminator: "")
    }
    exit(doctorExitCode(checks))
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

if arguments.first == "subscribe" {
    // One JSON event per line until the daemon goes away. `wm subscribe window_focus` keeps the events with these names, and
    // `--snapshot` makes the first line the state of wm now.
    do {
        let connection = try connectToServer(path: defaultSocketPath(), timeoutSeconds: 0)
        try writeFrame(connection, JSONEncoder().encode(ClientRequest(args: arguments)))
        let answer = try JSONDecoder().decode(ServerAnswer.self, from: readFrame(connection))
        guard answer.exitCode == 0 else {
            printError(answer.stderr)
            exit(answer.exitCode)
        }
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
    // `pick` waits for a click: the daemon gives up after 30 seconds, so the client waits a little longer.
    let answer = try sendRequest(
        ClientRequest(args: arguments, windowId: windowId, windowSelector: windowSelector),
        timeoutSeconds: arguments.first == "pick" ? 35 : 5)
    write(answer.stdout, to: .standardOutput)
    // A daemon that started before an upgrade does not know the commands that came after it.
    if answer.exitCode == 2, let first = arguments.first, answer.stderr.contains("unknown command '\(first)'") {
        printError("wm: error: the running daemon does not know '\(first)'\nhint: it is older than this wm (\(wmVersion)): run `wm daemon stop`, then `wm daemon start`\n")
        exit(2)
    }
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
