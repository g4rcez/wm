import Foundation

/// One option of a command, with what it does.
public struct CommandOption: Sendable, Equatable {
    /// The option as typed, with its short form and value: `-n, --lines=<n>`.
    public let flag: String
    public let text: String

    public init(_ flag: String, _ text: String) {
        self.flag = flag
        self.text = text
    }
}

/// What the options of each command do, by the words of the command. `wm help <command>` prints them under `Options`. The
/// spec table names the options of a command in `flags`; a test checks that every one of them is explained here.
public let commandOptions: [String: [CommandOption]] = [
    "focus": [CommandOption("--wrap", "Go around to the other side instead of stopping at the edge.")],
    "move": [CommandOption("--wrap", "At the edge of the workspace, go around to the other end (a tiled window).")],
    "swap": [CommandOption("--wrap", "At the edge of the workspace, trade places with the window at the other end.")],
    "focus next": [CommandOption("--wrap", "Go from the last window to the first.")],
    "focus prev": [CommandOption("--wrap", "Go from the first window to the last.")],
    "focus app": [CommandOption("--launch", "Start the app when it has no window.")],
    "window remember": [CommandOption("--title", "Match only a window with this exact title, not every window of the app.")],
    "window forget": [CommandOption("--title", "Forget the entry that has this window's exact title.")],
    "window send workspace": [
        CommandOption("--stay", "Keep the view where it is; do not follow the window."),
        CommandOption("--tile", "Only join the layout; on an empty workspace the window does not arrive maximized."),
        CommandOption("--column", "Send the whole column with its stack, width and tabs (scrolling)."),
    ],
    "window send monitor": [
        CommandOption("--tile", "Only join the layout of the other monitor."),
        CommandOption("--column", "Send the whole column (scrolling)."),
    ],
    "switcher": [CommandOption("--all", "List the windows of every workspace, not only of this one.")],
    "palette": [
        CommandOption("--cmdtab", "Work like Cmd+Tab: list the apps, and switch when you let go of the modifier."),
        CommandOption("--reverse", "With --cmdtab, start from the last app (bind it to cmd-shift-tab)."),
    ],
    "hints": [CommandOption("--wait", "Start in search mode; a label only highlights, and Return clicks.")],
    "jump": [
        CommandOption("--swap", "Swap the picked window with the focused one (tiled windows of one workspace), instead of focusing it."),
        CommandOption("--close", "Close the picked window instead of focusing it."),
    ],
    "notify": [CommandOption("--seconds=<n>", "How long the message stays (default 2).")],
    "list": [
        CommandOption("--focused", "Only the focused window (with `monitors`: the focused monitor)."),
        CommandOption("--json", "Print JSON for scripts."),
    ],
    "query": [
        CommandOption("--focused", "Only the focused window (with `monitors`: the focused monitor)."),
        CommandOption("--json", "Print JSON for scripts."),
    ],
    "memory list": [CommandOption("--json", "Print JSON for scripts.")],
    "memory forget": [
        CommandOption("--title=<text>", "Remove the entry that has this exact title, not the entry of the whole app."),
        CommandOption("--all", "Remove every entry of the app, whatever its title."),
    ],
    "session open": [CommandOption("--no-launch", "Do not start the apps that have no window.")],
    "session list": [CommandOption("--json", "Print JSON for scripts.")],
    "pick": [CommandOption("--json", "Print one JSON object.")],
    "subscribe": [CommandOption("--snapshot", "Start with one line that holds the state of wm now.")],
    "logs": [
        CommandOption("-n, --lines=<n>", "How many records to show (default 100; 0 shows all)."),
        CommandOption("-f, --follow", "Wait for new records."),
        CommandOption("-o, --output=<otel|json>", "Text in the OpenTelemetry log model (default), or one JSON object per line."),
    ],
    "daemon status": [CommandOption("--json", "Print JSON for scripts.")],
    "animations": [CommandOption("--json", "Print the animations and their state as JSON for scripts.")],
    "doctor": [CommandOption("--json", "Print the checks as JSON for scripts.")],
    "lsp": [
        CommandOption("--write", "Save .luarc.json next to the config file."),
        CommandOption("--force", "Replace a .luarc.json that is there already."),
    ],
    "init": [
        CommandOption("--mod=<key>", "The main modifier of the binds: alt, cmd, ctrl or hyper (CapsLock). Without it wm asks."),
        CommandOption("--lua", "Write all of it to init.lua, as Lua, and no shortcuts.toml."),
        CommandOption("--force", "Replace the config files that are there already."),
    ],
    "exec": [
        CommandOption("--float, --tile", "The window opens floating, or tiled."),
        CommandOption("--center, --maximize", "The window opens centered, or maximized."),
        CommandOption("--no-focus", "The window does not take the focus when it opens."),
        CommandOption("--workspace <w>, --monitor <m>", "The window opens on that workspace or monitor."),
        CommandOption("--width <f>, --size <w>,<h>", "A column width, or a size (fractions of the work area)."),
        CommandOption("--layout <kind>", "The layout kind of the rule."),
    ],
]
