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
        CommandSpec(
            "focus next", "", "[--wrap]", "Focus the next window in layout order.",
            details: "The order is the tiled windows as the layout lists them (columns from left to right), then the floating windows.\nWith --wrap, or wrap_focus in the config, the last window goes on to the first."),
        CommandSpec("focus prev", "", "[--wrap]", "Focus the previous window in layout order."),
        CommandSpec("focus mark", "<name>", "", "Focus the window that has this mark.", example: "wm focus mark mail"),
        CommandSpec(
            "focus app", "<name>", "[--launch]", "Focus a window of the app, or start it (run or raise).",
            details: "`name` is the name or the bundle id of the app, as `--window app:<name>` takes it. The most recent window of the app gets the\nfocus; when the focus is on the app already, the next window of it (so a key pressed again walks through them). With --launch an\napp without a window starts.",
            example: "wm focus app Safari --launch"),
        CommandSpec(
            "focus column", "<first|last|n>", "", "Focus a column of the strip (scrolling).",
            details: "The number counts from 1; a number that is too large means the last column. The window that had the focus last\nin that column gets it.",
            example: "wm focus column 2"),
        CommandSpec(
            "focus stack", "<first|last|n>", "", "Focus a window of this column (scrolling).",
            example: "wm focus stack first"),
        CommandSpec("focus window", "<id>", "", "Focus a window by id (see `wm list windows`).", example: "wm focus window 3042"),
        CommandSpec(
            "focus monitor", "<monitor>", "", "Focus another monitor.",
            details: "The monitor is a direction, next, prev, last (the one that had the focus before), a role (main, secondary,\ntertiary), a number (1 is the leftmost) or part of the name. main is the display with the menu bar.",
            example: "wm focus monitor last"),
        CommandSpec("focus layer", "[floating|tiling]", "", "Switch focus between floating and tiling windows."),
        CommandSpec("move", "<dir>", "", "Move the window; at the edge it goes to the next monitor."),
        CommandSpec("swap", "<dir>", "", "Exchange places with the window in that direction."),
        CommandSpec("resize", "<width|height|smart> <+n|-n>", "", "Grow or shrink the window by n points.", example: "wm resize width +50"),
    ]),
    CommandSection(title: "Windows", specs: [
        CommandSpec("window close", "", "", "Close the window."),
        CommandSpec("window float", "", "", "Float the window and center it, or tile it again."),
        CommandSpec(
            "window sticky", "", "", "Show the window on every workspace of its monitor.",
            details: "A tiled window floats first. The window follows the workspace that the monitor shows (also a special workspace). Again\nto end it; the window then stays floating on the workspace that it is on. `window remember` keeps it.",
            example: "wm window sticky"),
        CommandSpec(
            "window snap", "<place>", "", "Float the window into a part of the screen.",
            details: "`place` is left, right, top, bottom, top-left, top-right, bottom-left, bottom-right or center. The window floats (a tiled window\nfirst) and fills that part of the work area inside the gaps. The same place again goes on to the next size: half, a third, two thirds\n(center: 60%, 80%, 40%).",
            example: "wm window snap left"),
        CommandSpec("window fullscreen", "", "", "Fill the work area with no gaps, or go back."),
        CommandSpec("window maximize", "", "", "Fill the work area inside the gaps, or go back."),
        CommandSpec("window raise-floating", "", "", "Bring the floating windows to the front."),
        CommandSpec("window rescue", "", "", "Move floating windows that are off screen back onto it."),
        CommandSpec(
            "window native-fullscreen", "", "", "Enter or leave macOS fullscreen.",
            details: "The window goes to a Space of its own and wm leaves it out of the layout. When it leaves fullscreen it comes back\nto its workspace."),
        CommandSpec(
            "window mark", "<name>", "", "Give the window a name.",
            details: "A name belongs to one window; marking another window with it moves the mark. Marks last until the window closes\nand are saved with the layout. `wm --window mark:<name> ...` and `wm focus mark <name>` find the window.",
            example: "wm window mark mail"),
        CommandSpec("window unmark", "[name]", "", "Remove one mark, or all marks of the window."),
        CommandSpec(
            "window remember", "", "[--title]", "Keep this window's state for the next window of the app.",
            details: "Keeps the workspace and monitor, floating or tiled, the place and size of a floating window, maximized, pseudo, the column width and\nstrip, and the marks. When a window of the same app opens later, it gets them and the focus. With --title the window must\nalso have this exact title. Remembering again replaces the entry. Windows that are open when wm starts are not moved.\n`wm list memory` shows the entries.",
            example: "wm window remember --title"),
        CommandSpec("window forget", "", "[--title]", "Forget what `window remember` kept for this app.", example: "wm window forget"),
        CommandSpec(
            "window pseudo", "", "", "Keep the window's own size, centered in its tile.",
            details: "The window keeps the size it has now. A tile that is smaller than that cuts it down. Run it again to tile the\nwindow normally."),
        CommandSpec(
            "window send workspace", "<name>", "[--stay] [--tile] [--column]", "Send the window to a workspace; --stay keeps the view.",
            details: "The name can also be next, prev or empty (see `wm help workspace`). On an empty workspace the window arrives maximized; on one that has windows it joins the layout and the\nlayout is balanced. With --tile it only joins the layout. `special:<name>` is a special workspace.\nWith --column the whole column goes (scrolling), with its stack, width and tabs, and joins the layout like --tile.",
            example: "wm window send workspace 3 --stay"),
        CommandSpec(
            "window send monitor", "<monitor>", "[--tile] [--column]", "Send the window to another monitor and follow it.",
            details: "The monitor is the same as in `wm help focus monitor`. --column sends the whole column (see `wm help window send workspace`).",
            example: "wm window send monitor main"),
        CommandSpec("window send strip", "<horizontal|vertical>", "", "Move the window to the other strip (scrolling)."),
    ]),
    CommandSection(title: "Workspaces", specs: [
        CommandSpec(
            "workspace", "<name|back>", "", "Show a workspace on the focused monitor.",
            details: "Names with a meaning: back (the previous workspace), next and prev (the workspaces in use, wrapping around)\nand empty (the lowest free number).",
            example: "wm workspace next"),
        CommandSpec(
            "workspace move monitor", "<monitor>", "", "Move this workspace to another monitor.",
            details: "That monitor shows the workspace from now on, and this monitor shows the lowest free workspace number. A workspace\nthat a wm.workspace rule binds to a monitor stays there. The monitor is the same as in `wm help focus monitor`.",
            example: "wm workspace move monitor right"),
        CommandSpec("workspace special", "[name]", "", "Show or hide a special workspace (default: special).", example: "wm workspace special term"),
    ]),
    CommandSection(title: "Layout", specs: [
        CommandSpec("layout set", "<scrolling|tiling|master>", "", "Switch the layout of the workspace.", example: "wm layout set master"),
        CommandSpec(
            "layout master promote", "", "", "Swap the window with the master.",
            details: "The focused window and the first master change places. When the focused window is the master, the first window of the stack\ntakes its place."),
        CommandSpec(
            "layout master count", "<n>", "", "Set how many windows are masters (master layout).",
            details: "`n` sets the count (1 or more); +n and -n change it. With more masters than windows they all share the master area.",
            example: "wm layout master count +1"),
        CommandSpec(
            "layout master ratio", "<ratio>", "", "Set the share of the master area (master layout).",
            details: "A ratio from 0.1 to 0.9 sets it; +0.05 and -0.05 change it. `resize width` and the mouse change it too.",
            example: "wm layout master ratio 0.6"),
        CommandSpec(
            "layout master orientation", "[place]", "", "Move the master area (master layout).",
            details: "`place` is left, right, top, bottom, center or next. left, right, top and bottom put the master on that side. center puts it in the middle with the stack on both sides.\nWithout a name, or with next, it goes to the next one in that order.",
            example: "wm layout master orientation center"),
        CommandSpec("layout balance", "", "", "Give every window (or column) an equal share."),
        CommandSpec("layout rotate", "[cw|ccw]", "", "Move every window one slot around the layout."),
        CommandSpec("layout flip", "", "", "Turn every split from side by side to stacked (tiling)."),
        CommandSpec(
            "layout tile", "[pattern|chain]", "", "Arrange windows in a pattern; no pattern opens a picker.",
            details: "Patterns: 2, 3, 4, 5, 6, 2+1, 1+2, 2/3, 3/4 (big window on the left), 1/4 (big window on the right), center (tiling: the windows share the middle two thirds, any number of them). `chain` goes back to the plain layout. A config can list its own patterns with `templates` in `tiling` and `scrolling`.\nScrolling: the window and the next ones fill one screen. Tiling: all windows take the pattern, so their number must match.",
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
        CommandSpec("layout column expand", "", "", "Grow this column into the free room (scrolling)."),
        CommandSpec("layout column center", "", "", "Scroll the strip to center this column (scrolling)."),
        CommandSpec("layout column center-visible", "", "", "Center the columns that are fully on screen (scrolling)."),
        CommandSpec(
            "layout column move", "<first|last|n>", "", "Move this column to a place in the strip (scrolling).",
            example: "wm layout column move first"),
        CommandSpec(
            "layout stack", "<join|leave|tabs|equalize>", "", "Join the left column, leave it, tabs, even heights.",
            details: "join and leave take a side: `layout stack join right` puts the window at the bottom of the column on its right,\n`layout stack leave left` puts it in a new column on its left. Without a side, join goes left and leave goes right.\nIn the vertical strip left and right mean up and down."),
        CommandSpec("layout stack height", "<fraction|cycle>", "", "Set the height of the window in its stack (scrolling).", example: "wm layout stack height 0.5"),
    ]),
    CommandSection(title: "Interface", specs: [
        CommandSpec(
            "switcher", "[next|prev|commit|cancel]", "[--all]", "Open the Alt+Tab window switcher.",
            details: "It shows the windows of the workspace. With --all it lists the windows of every workspace, most recent first, and\nchoosing one shows its workspace. Cmd-W closes the selected window; the panel stays open without it.",
            example: "wm switcher --all"),
        CommandSpec(
            "zen", "[on|off]", "", "Show only the focused window, centered; hide the others.",
            details: "The other windows of the workspace are moved off screen, like the windows of a hidden workspace; the layout is not changed.\nFocusing another window shows that one instead. `zen.width` in the config sets the width (default 0.7 of the work area).\nWithout an argument it turns the mode on or off. A fullscreen window wins over it.",
            example: "wm zen"),
        CommandSpec(
            "overview", "", "", "Show all workspaces; type to search a window.",
            details: "Each row is a workspace in its own layout. Typing searches, Return focuses, Cmd-W closes the selected window, and\ndragging a window onto another row moves it there."),
        CommandSpec(
            "palette", "[windows|apps|commands|menu]", "[--cmdtab] [--reverse]", "Search running apps, windows, commands and menu items.",
            details: "One text field. Without a prefix it lists the running apps with their windows. `>` finds wm commands (Tab completes one, and after a\ncommand it lists what can follow) and `/` finds the menu items of the app that was in front. Up and down move, Return\nruns the row and Escape closes. The word picks the list to start in.\n--cmdtab works like the Cmd+Tab of macOS: it lists the running apps, selects the previous one, Tab and Shift+Tab move while you hold\nthe modifier, and letting go of it switches to the app. wm swallows those keys, so the macOS switcher does not open.\n--reverse starts from the last app (bind it to cmd-shift-tab).",
            example: "wm palette --cmdtab"),
        CommandSpec(
            "menu", "", "", "Show the menus of the app at the pointer.",
            details: "It reads the menu bar of the app of the window (the focused app) and shows it as a menu at the mouse pointer. An item\nthat you choose runs in that app. It shows what the app gives to the Accessibility API; an app that fills its menus\nonly when you open them can show fewer items.",
            example: "wm menu"),
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
            details: "`what` is windows, workspaces, monitors, memory or binds. With no argument it lists the workspaces and their windows. --focused lists only the focused window (or, with monitors, the focused monitor).\n--json prints JSON for scripts. `list binds` shows every key bind with its description.",
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
  --window <w>    act on that window: an id, focused, app:<name>, title:<re>, mark:<name> or pid:<n>
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
            lines.append("  " + spec.signature.padded(to: width) + "  " + spec.summary)
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
    "focus-monitor": "focus monitor <monitor>",
    "movetomonitor": "window send monitor <monitor>",
    "movetoworkspace": "window send workspace <name>",
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
