import Foundation

/// One command of the CLI. This table is the single source for `wm help`, for the `usage:` line of an error, and for
/// the hint that names the new command when someone types an old one.
public struct CommandSpec: Sendable, Equatable {
    /// The command words, for example `window send workspace`.
    public let path: String
    /// Positional arguments, for example `<name>`.
    public let args: String
    /// Options, for example `[--stay] [--tile]`.
    public let flags: String
    public let summary: String
    /// More text for `wm help <command>`.
    public let details: String?
    public let example: String?

    public init(_ path: String, _ args: String = "", _ flags: String = "", _ summary: String, details: String? = nil, example: String? = nil) {
        self.path = path
        self.args = args
        self.flags = flags
        self.summary = summary
        self.details = details
        self.example = example
    }

    public var words: [String] { path.split(separator: " ").map(String.init) }

    /// The words and arguments without options, for example `window send workspace <name>`.
    public var signature: String { [path, args].filter { !$0.isEmpty }.joined(separator: " ") }

    /// For example `wm window send workspace <name> [--stay] [--tile]`.
    public var usage: String { ["wm", path, args, flags].filter { !$0.isEmpty }.joined(separator: " ") }
}

public struct CommandSection: Sendable {
    public let title: String
    public let specs: [CommandSpec]
}

public let commandSections: [CommandSection] = [
    CommandSection(title: "Focus and move", specs: [
        CommandSpec("focus", "<dir>", "[--wrap]", "Focus the window in that direction; --wrap goes around.", example: "wm focus left --wrap"),
        CommandSpec("focus back", "", "", "Focus the previous window."),
        CommandSpec("focus window", "<id>", "", "Focus a window by id (see `wm list windows`).", example: "wm focus window 3042"),
        CommandSpec("focus monitor", "<dir|next|prev>", "", "Focus another monitor."),
        CommandSpec("focus layer", "[floating|tiling]", "", "Switch focus between floating and tiling windows."),
        CommandSpec("move", "<dir>", "", "Move the window; at the edge it goes to the next monitor."),
        CommandSpec("swap", "<dir>", "", "Exchange places with the window in that direction."),
        CommandSpec("resize", "<width|height|smart> <+n|-n>", "", "Grow or shrink the window by n points.", example: "wm resize width +50"),
    ]),
    CommandSection(title: "Windows", specs: [
        CommandSpec("window close", "", "", "Close the window."),
        CommandSpec("window float", "", "", "Float the window, or tile it again."),
        CommandSpec("window fullscreen", "", "", "Fill the work area with no gaps, or go back."),
        CommandSpec("window maximize", "", "", "Fill the work area inside the gaps, or go back."),
        CommandSpec(
            "window pseudo", "", "", "Keep the window's own size, centered in its tile.",
            details: "The window keeps the size it has now. A tile that is smaller than that cuts it down. Run it again to tile the\nwindow normally."),
        CommandSpec(
            "window send workspace", "<name>", "[--stay] [--tile]", "Send the window to a workspace; --stay keeps the view.",
            details: "The name can also be next, prev or empty (see `wm help workspace`). On an empty workspace the window arrives maximized; on one that has windows it joins the layout and the\nlayout is balanced. With --tile it only joins the layout. `special:<name>` is a special workspace.",
            example: "wm window send workspace 3 --stay"),
        CommandSpec("window send monitor", "<dir|next|prev>", "[--tile]", "Send the window to another monitor and follow it."),
        CommandSpec("window send row", "<up|down|N>", "[--stay] [--tile]", "Send the window to a virtual row (native workspaces)."),
        CommandSpec("window send strip", "<horizontal|vertical>", "", "Move the window to the other strip (scrolling)."),
    ]),
    CommandSection(title: "Workspaces", specs: [
        CommandSpec(
            "workspace", "<name|back>", "", "Show a workspace on the focused monitor.",
            details: "Names with a meaning: back (the previous workspace), next and prev (the workspaces in use, wrapping around)\nand empty (the lowest free number). next, prev and empty need emulated workspaces.",
            example: "wm workspace next"),
        CommandSpec("workspace special", "[name]", "", "Show or hide a special workspace (default: special).", example: "wm workspace special term"),
        CommandSpec("workspace row", "<up|down|N>", "", "Show a virtual row of the desktop (native workspaces)."),
    ]),
    CommandSection(title: "Layout", specs: [
        CommandSpec("layout set", "<scrolling|tiling>", "", "Switch the layout of the workspace.", example: "wm layout set tiling"),
        CommandSpec("layout balance", "", "", "Give every window (or column) an equal share."),
        CommandSpec("layout rotate", "[cw|ccw]", "", "Move every window one slot around the layout."),
        CommandSpec("layout flip", "", "", "Turn every split from side by side to stacked (tiling)."),
        CommandSpec(
            "layout tile", "[pattern|chain]", "", "Arrange windows in a pattern; no pattern opens a picker.",
            details: "Patterns: 2, 3, 4, 5, 6, 2+1, 1+2, 2/3, 3/4 (big window on the left), 1/4 (big window on the right). `chain` goes back to the plain layout.\nScrolling: the window and the next ones fill one screen. Tiling: all windows take the pattern, so their number must match.",
            example: "wm layout tile 2+1"),
        CommandSpec("layout split", "<toggle|swap>", "", "Flip the window's split, or swap its two sides (tiling)."),
        CommandSpec("layout split root", "", "", "Make the window a child of the root: half the screen."),
        CommandSpec(
            "layout split ratio", "<0.1-0.9|+n|-n>", "", "Set or change the share of the window in its split.",
            example: "wm layout split ratio 0.7"),
        CommandSpec(
            "layout preselect", "<dir>", "", "The next window opens on that side, once (tiling).",
            example: "wm layout preselect down"),
        CommandSpec("layout column width", "<fraction|cycle>", "", "Set the column width (scrolling).", example: "wm layout column width 0.5"),
        CommandSpec("layout column match", "", "", "Give every column the width of this one (scrolling)."),
        CommandSpec("layout column center", "", "", "Scroll the strip to center this column (scrolling)."),
        CommandSpec("layout column center-visible", "", "", "Center the columns that are fully on screen (scrolling)."),
        CommandSpec("layout stack", "<join|leave|tabs|equalize>", "", "Join the left column, leave it, tabs, even heights."),
        CommandSpec("layout stack height", "<fraction|cycle>", "", "Set the height of the window in its stack (scrolling).", example: "wm layout stack height 0.5"),
    ]),
    CommandSection(title: "Interface", specs: [
        CommandSpec("switcher", "[next|prev|commit|cancel]", "", "Open the Alt+Tab window switcher."),
        CommandSpec("overview", "", "", "Show all workspaces; type a window's label to focus it."),
        CommandSpec("mode", "<name>", "", "Switch the binding mode (`main` is the default).", example: "wm mode resize"),
        CommandSpec("pointer", "<window|monitor>", "", "Move the mouse pointer to the center of the target."),
        CommandSpec(
            "exec", "[options] <command>", "", "Run a shell command (--window sets $WM_WINDOW_ID).",
            details: "Options make a rule for the window that the command opens: --float, --tile, --center, --maximize, --no-focus,\n--workspace <w>, --monitor <m>, --width <f>, --size <w>,<h>, --layout <kind>. End them with `--`. The window is found by\nprocess, so use the program itself, not `open -a`.",
            example: "wm exec --float --center --size 0.5,0.5 -- /Applications/Foo.app/Contents/MacOS/foo"),
        CommandSpec(
            "batch", "<commands>", "", "Run commands in order; stops at the first error.",
            example: "wm batch 'workspace 2; layout set tiling'"),
        CommandSpec(
            "set", "<key> <value>", "", "Change a config value until the next reload.",
            details: "The key is the config path, for example gaps.inner or tiling.split_ratio. Lists are comma-separated\n(scrolling.presets 0.3,0.5,1). `workspaces` and `url` only change in the config file.",
            example: "wm set gaps.inner 4"),
        CommandSpec("notify", "<text>", "[--seconds=n]", "Show a message on screen for 2 seconds (or n).", example: "wm notify 'build done'"),
        CommandSpec(
            "key send", "<chord>", "", "Send a key to the window's app, without focusing it.",
            details: "Use --window to choose the app. For a global hotkey of an app: bind a chord to this command.",
            example: "wm --window app:OBS key send cmd-shift-r"),
    ]),
    CommandSection(title: "Inspect", specs: [
        CommandSpec(
            "list", "[what]", "[--focused] [--json]", "List windows, workspaces, monitors or binds.",
            details: "`what` is windows, workspaces, monitors or binds. With no argument it lists the workspaces and their windows. --focused lists only the focused window.\n--json prints JSON for scripts. `list binds` shows every key bind with its description.",
            example: "wm list windows --json"),
        CommandSpec("subscribe", "", "", "Print one JSON event per line until stopped."),
    ]),
    CommandSection(title: "Daemon", specs: [
        CommandSpec("daemon start", "", "", "Start wm in the background."),
        CommandSpec("daemon stop", "", "", "Stop wm. Hidden windows come back on screen."),
        CommandSpec("daemon status", "", "[--json]", "Show whether wm runs and its state (exit 1 if not)."),
        CommandSpec("daemon reload", "", "", "Load the config again."),
        CommandSpec(
            "lsp", "", "[--write] [--force]", "Set up autocomplete for init.lua in your editor.",
            details: "Prints the folder of the type stubs and the .luarc.json that lua-language-server needs. --write saves it next to\nthe config file; --force replaces a .luarc.json that is already there. It works without the daemon.",
            example: "wm lsp --write"),
        CommandSpec(
            "completion", "<zsh|bash>", "", "Print the shell completion script.",
            details: "It completes the commands, their arguments and options, and (when the daemon runs) window ids, workspaces and modes.\nLoad it when the shell starts. The script itself works without the daemon.",
            example: "eval \"$(wm completion zsh)\""),
        CommandSpec("version", "", "", "Print the version."),
    ]),
]

public let commandSpecs: [CommandSpec] = commandSections.flatMap(\.specs)

/// The first words of all commands: `focus`, `window`, `layout`, ...
public let commandNames: Set<String> = Set(commandSpecs.compactMap(\.words.first))

/// The `usage:` lines of every command whose words start with `prefix` (`"window"`, `"layout column"`, ...).
public func usageLines(for prefix: String) -> [String] {
    let wanted = prefix.split(separator: " ").map(String.init)
    return commandSpecs.filter { Array($0.words.prefix(wanted.count)) == wanted }.map(\.usage)
}

private let globalOptions = """
Options for every command:
  --window <w>    act on that window: an id, app:<name>, title:<regex>, pid:<n> or focused
  --json          machine-readable output (list, daemon status)
  -v, --verbose   print the state after the command
  -h, --help      show help for a command
"""

/// The text of `wm help` (no topic), or of `wm help <command>`. `nil` when the topic is not a command.
public func renderHelp(topic: String? = nil) -> String? {
    guard let topic, !topic.isEmpty else { return overviewHelp() }
    let wanted = topic.split(separator: " ").map(String.init)
    let matches = commandSpecs.filter { Array($0.words.prefix(wanted.count)) == wanted }
    guard !matches.isEmpty else { return nil }
    var lines: [String] = []
    for spec in matches {
        lines.append(spec.usage)
        lines.append("    " + spec.summary)
        if let details = spec.details { lines += details.split(separator: "\n").map { "    " + $0 } }
        if let example = spec.example { lines.append("    example: " + example) }
        lines.append("")
    }
    lines.append("<dir> is left, right, up or down.")
    return lines.joined(separator: "\n") + "\n"
}

private func overviewHelp() -> String {
    let width = commandSpecs.map(\.signature.count).max() ?? 0
    var lines = ["wm: a tiling window manager for macOS", "", "Usage: wm [--window <id>] <command> [args]"]
    for section in commandSections {
        lines += ["", section.title.uppercased()]
        for spec in section.specs {
            lines.append("  " + spec.signature.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + spec.summary)
        }
    }
    lines += ["", "<dir> is left, right, up or down.", "", globalOptions, "", "Run `wm help <command>` for details and examples, for example `wm help window`.", "Config: ~/.config/wm/init.lua"]
    return lines.joined(separator: "\n") + "\n"
}

/// What to tell someone who typed `word`: the new name of a renamed command, or the closest command.
public func unknownCommandHint(_ word: String) -> String? {
    if let renamed = renamedCommands[word] { return "'\(word)' is now `wm \(renamed)`" }
    let limit = word.count <= 4 ? 1 : 2
    let near = commandNames.map { ($0, editDistance(word, $0)) }.filter { $0.1 <= limit }.min { $0.1 < $1.1 }
    return near.map { "did you mean `wm \($0.0)`?" }
}

/// The commands that changed their names. The key is the old first word; the value is the new command.
public let renamedCommands: [String: String] = [
    "focus-back": "focus back",
    "focus-window": "focus window <id>",
    "focus-monitor": "focus monitor <dir|next|prev>",
    "movetomonitor": "window send monitor <dir|next|prev>",
    "movetoworkspace": "window send workspace <name>",
    "movetorow": "window send row <up|down|N>",
    "row": "workspace row <up|down|N>",
    "togglespecialworkspace": "workspace special [name]",
    "togglefloating": "window float",
    "fullscreen": "window fullscreen",
    "close": "window close",
    "balance": "layout balance",
    "balance-sizes": "layout balance",
    "togglesplit": "layout split toggle",
    "swapsplit": "layout split swap",
    "column-width": "layout column width <fraction|cycle>",
    "match-width": "layout column match",
    "center": "layout column center",
    "equalize-stack": "layout stack equalize",
    "stack": "layout stack join",
    "unstack": "layout stack leave",
    "toggletabs": "layout stack tabs",
    "send-to-horizontal": "window send strip horizontal",
    "send-to-vertical": "window send strip vertical",
    "tile": "layout tile [pattern|chain]",
    "rotate-clockwise": "layout rotate cw",
    "rotate-counterclockwise": "layout rotate ccw",
    "rotate-layout": "layout flip",
    "move-mouse": "pointer <window|monitor>",
    "query": "list [windows|workspaces|monitors]",
    "status": "daemon status",
    "start": "daemon start",
    "stop": "daemon stop",
    "reload": "daemon reload",
    "quit": "daemon stop",
    "ping": "daemon status",
]

/// The number of single-character edits between two words.
func editDistance(_ a: String, _ b: String) -> Int {
    let a = Array(a), b = Array(b)
    var previous = Array(0...b.count)
    for (i, x) in a.enumerated() {
        var row = [i + 1]
        for (j, y) in b.enumerated() {
            row.append(min(previous[j + 1] + 1, row[j] + 1, previous[j] + (x == y ? 0 : 1)))
        }
        previous = row
    }
    return previous[b.count]
}
