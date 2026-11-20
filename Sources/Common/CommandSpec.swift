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
        CommandSpec(
            "focus", "<dir>", "[--wrap]", "Focus the window in that direction; --wrap goes around.",
            details: "The nearest window in that direction gets the focus. Without --wrap the focus stops at the edge; with it, it goes\naround to the other side.",
            example: "wm focus left --wrap"),
        CommandSpec(
            "focus back", "", "", "Focus the previous window.",
            details: "The window that had the focus before this one on the workspace. It fails when there is none.",
            example: "wm focus back"),
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
        CommandSpec(
            "focus layer", "[floating|tiling]", "", "Switch focus between floating and tiling windows.",
            details: "Without an argument it goes to the other layer than the one of the focused window. The window of that layer on this\nworkspace that had the focus last gets it; the command fails when the layer has no window.",
            example: "wm focus layer floating"),
        CommandSpec(
            "move", "<dir> [points]", "[--wrap]", "Move the window; at the edge it goes to the next monitor.",
            details: "A floating window moves by `points` (40 if you leave it out) and stops at the edge of its monitor. With --wrap, or wrap_focus in the\nconfig, a tiled window at the edge goes around to the other end of the workspace instead of to the next monitor."),
        CommandSpec(
            "swap", "<dir>", "[--wrap]", "Exchange places with the window in that direction.",
            details: "With --wrap, or wrap_focus in the config, the window at the edge trades places with the window at the other end."),
        CommandSpec(
            "resize", "<width|height|smart> <+n|-n>", "", "Grow or shrink the window by n points.",
            details: "`width`, `height` and `smart` change the size. A floating window keeps its top left corner for `width` and `height`; `smart` changes both\naround its center (bigger and smaller). A side\n(`left`, `right`, `up` or `down`, as `wm resize left +50`) moves the edge on that side: +n pushes it outward, -n pulls it inward, and the other edges stay.\nA tiled window moves the divider on that side, so a side at the edge of the screen fails (use the opposite side). A floating window stays on its monitor.\n`resize dir <direction> <n>` moves the nearest divider on that axis n points toward the direction, so a window on the far side grows and one on the near side shrinks. It passes on to the next split when one is at its limit, and fails when there is no divider on that axis. A floating window grows for right and down and shrinks for left and up.",
            example: "wm resize width +50"),
    ]),
    CommandSection(title: "Windows", specs: [
        CommandSpec(
            "window close", "", "", "Close the window.",
            details: "It presses the close button of the window, so the app can still ask to save. Use --window to close another one.",
            example: "wm --window app:Safari window close"),
        CommandSpec(
            "window float", "[on|off]", "", "Float the window and center it, or tile it again.",
            details: "Without an argument it switches between floating and tiled. `on` and `off` set the state, so running them again\nchanges nothing: the right choice for a script.",
            example: "wm window float on"),
        CommandSpec(
            "window center", "", "", "Float the window (a tiled one first), centered.",
            details: "The size stays; only the place changes. It fails for a window that is minimized or in native fullscreen.",
            example: "wm window center"),
        CommandSpec(
            "window sticky", "", "", "Show the window on every workspace of its monitor.",
            details: "A tiled window floats first. The window follows the workspace that the monitor shows (also a special workspace). Again\nto end it; the window then stays floating on the workspace that it is on. `window remember` keeps it.",
            example: "wm window sticky"),
        CommandSpec(
            "window snap", "<place>", "", "Float the window into a part of the screen.",
            details: "`place` is left, right, top, bottom, top-left, top-right, bottom-left, bottom-right, top-center, bottom-center or center. The window floats (a tiled window\nfirst) and fills that part of the work area inside the gaps. The same place again goes on to the next size: half, a third, two thirds\n(center: 60%, 80%, 40%).",
            example: "wm window snap left"),
        CommandSpec(
            "window place", "<pattern> <n>", "", "Float the window into cell n of a tile pattern.",
            details: "`pattern` is one of `layout tile` (2, 2+1, 2/3, 1-over-2, corner-tl ...), or a template of your config. Cells count from 1, in reading\norder. The window floats (a tiled one first) and fills the cell inside the gaps; the other windows do not move.\n`workspace float-all <pattern>` places all the windows at once.",
            example: "wm window place 2+1 2"),
        CommandSpec(
            "window move-to", "<x> <y>", "", "Move the floating window to a point of the work area.",
            details: "x and y are points from the top left corner of the work area, or a percent of its width and height (`50%`). The size stays\nand the window stays inside the area, so a point near the edge moves it the least that fits. A tiled window floats first.",
            example: "wm window move-to 40 80"),
        CommandSpec(
            "window minimize", "", "", "Minimize the window.",
            details: "It sets the minimized state of the window, as the yellow button does. A minimized window has no place in the layout.",
            example: "wm window minimize"),
        CommandSpec(
            "window swipe", "<left|right|up|down>", "", "What a swipe on the title bar does.",
            details: "A floating window snaps to the left or right half (`window snap`), or fills the screen (up, `window fullscreen`). A tiled\nwindow moves in its layout (`move`), or is maximized (up, `window maximize`). Down minimizes both. The built-in title bar\ngestures run this command; see `trackpad.title_bar`.",
            example: "wm window swipe left"),
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
            details: "Keeps the workspace and monitor, floating or tiled, the place and size of a floating window, maximized, pseudo, the column width and\nstrip, and the marks. When a window of the same app opens later, it gets them and the focus. With --title the window must\nalso have this exact title. Remembering again replaces the entry. Windows that are open when wm starts are not moved.\n`wm memory list` shows the entries and `wm memory forget` removes one.",
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
        CommandSpec(
            "workspace float-all", "[off|pattern]", "", "Float every window of this workspace, or tile them again.",
            details: "It acts on the workspace that the focused monitor shows. Each window floats where it is, as `window float on` does. `off` tiles\nthem all again. With a pattern of `layout tile` (2, 2+1, 2/3, 1-over-2, center ...) the windows float into its cells, the tiled ones in\nlayout order first; a window past the last cell stays where it is. All of them set the state, so running them twice changes nothing.\nA minimized window or one in native fullscreen is left alone.",
            example: "wm workspace float-all 2+1"),
        CommandSpec("workspace special", "[name]", "", "Show or hide a special workspace (default: special).", example: "wm workspace special term"),
    ]),
    CommandSection(title: "Layout", specs: [
        CommandSpec(
            "layout set", "<layout>", "", "Switch the layout of the workspace.",
            details: "`layout` is scrolling, tiling, master, monocle or floating. The layout belongs to the workspace: the other workspaces keep theirs. `wm list workspaces` shows each one.\n`floating` floats every window where it is, and a window that opens floats in the frame that tiling would give it. A switch to\nanother layout leaves the windows floating; only the windows that open later are tiled.",
            example: "wm layout set master"),
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
        CommandSpec(
            "layout rotate", "[cw|ccw]", "", "Move every window one slot around the layout.",
            details: "cw (the default) moves each window to the next slot, ccw to the previous one.",
            example: "wm layout rotate ccw"),
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
            "overview", "[open|close|toggle]", "", "Show all workspaces; type to search a window.",
            details: "Every workspace is a small copy of its screen, in one column that scrolls; yours is in the middle. Typing searches, the\narrows move, Return focuses, Cmd-W closes the selected window, and dragging a window onto another workspace moves it there.\nWithout an argument it opens or closes the overview; `open` and `close` do only that (the swipes of 4 fingers use them)."),
        CommandSpec(
            "hints", "[open|close|toggle]", "[--wait]", "Label every clickable element; type a label to click it.",
            details: "Every button, link, field and tab of the focused window (web pages too), the menu bar, the menu extras and the Dock gets a\nlabel of two letters, as in the flash plugin of Neovim. Typing the label clicks the element; Shift on the second letter\nright-clicks and Cmd Cmd-clicks. / starts a search as in fzf: words in any order, each with its letters in order (`sv as` finds\nSave As). The matches keep their labels, and a letter that could continue the word is never the first letter of a label.\nBackspace undoes a letter. Return clicks the focused (Tab, Down, Ctrl-N) or only match, and again soon after double-clicks.\nEscape closes. With --wait the search starts at once, a label only highlights its element (so does the first match), and\nReturn clicks it, Shift-Return right-clicks, Cmd-Return Cmd-clicks.",
            example: "wm hints --wait"),
        CommandSpec(
            "scroll", "[open|close|toggle]", "", "Scroll the focused window with h j k l.",
            details: "The scroll areas of the focused window get numbers; the largest one is active, and the pointer moves to it. h j k l scroll,\nShift makes them dash, d and u go half a page, gg and G go to the top and the bottom. Tab, the arrows, Ctrl-N and Ctrl-P, or\na digit, change the area. Escape closes.",
            example: "wm scroll toggle"),
        CommandSpec(
            "select", "[open|close|toggle]", "", "Search the text on the screen; copy it or right-click it.",
            details: "Reads the text of the windows on the focused display. Typing searches it: case and accents do not count, and the places\nof the text are highlighted. Tab, the arrows, Ctrl-N and Ctrl-P change the focused one, and Return selects it. Then the keys\nare commands: h l move by a character, w b e by a word, j k by a line, 0 and $ go to the ends of the line, and v extends the\nselection. The two letters of a label take the selection to that match, and a second label extends it to there. y, Cmd-C or\nReturn copies, Shift-Return right-clicks, / goes back to the search and Escape closes. `wm.config { select = { keys = ... } }` changes\nthese keys.",
            example: "wm select"),
        CommandSpec(
            "palette", "[list]", "[--cmdtab] [--reverse]", "Search apps, windows, tabs, commands and menu items.",
            details: "One text field. Without a prefix it lists the running apps with their windows, and typing also finds the tabs\nof Chromium browsers, of Rex and of tmux. `>` finds wm commands (Tab completes one, and after a command it lists\nwhat can follow) and `/` finds the menu items of the app that was in front. Up and down move, Return runs the row\nand Escape closes. The list to start in is windows, apps, tabs, commands or menu. The tabs list holds the tabs of\nbrowsers, Rex and tmux, and the windows of the apps that have no tabs: a window is the tab of such an app.\n--cmdtab works like the Cmd+Tab of macOS: it lists the running apps, selects the previous one, Tab and Shift+Tab move while you hold\nthe modifier, and letting go of it switches to the app. wm swallows those keys, so the macOS switcher does not open.\n--reverse starts from the last app (bind it to cmd-shift-tab).",
            example: "wm palette --cmdtab"),
        CommandSpec(
            "palette reset", "", "", "Put the palette back at its first place on the screen.",
            details: "The palette opens where you last dragged it. This forgets that spot: the palette opens centered, a little above the\nmiddle, again. Cmd-0 does the same while the palette is open.",
            example: "wm palette reset"),
        CommandSpec(
            "menu", "", "", "Show the menus of the app at the pointer.",
            details: "It reads the menu bar of the app of the window (the focused app) and shows it as a menu at the mouse pointer. An item\nthat you choose runs in that app. It shows what the app gives to the Accessibility API; an app that fills its menus\nonly when you open them can show fewer items.",
            example: "wm menu"),
        CommandSpec(
            "mode", "<name|back>", "", "Switch the binding mode (`back`: the one before).",
            details: "A mode is a set of key binds that the config defines. `wm list binds` shows them. The command fails for a mode that\ndoes not exist, and then lists the modes.",
            example: "wm mode resize"),
        CommandSpec(
            "pointer", "<window|monitor>", "", "Move the mouse pointer to the center of the target.",
            details: "`window` is the window that the command acts on; `monitor` is the work area of the focused monitor.",
            example: "wm pointer monitor"),
        CommandSpec(
            "exec", "[options] <command>", "", "Run a shell command (--window sets $WM_WINDOW_ID).",
            details: "Options make a rule for the window that the command opens: --float, --tile, --center, --maximize, --no-focus,\n--workspace <w>, --monitor <m>, --width <f>, --size <w>,<h>, --layout <kind>. End them with `--`. The window is found by\nprocess, so use the program itself, not `open -a`.",
            example: "wm exec --float --center --size 0.5,0.5 -- /Applications/Foo.app/Contents/MacOS/foo"),
        CommandSpec(
            "batch", "<commands>", "", "Run commands in order; stops at the first error.",
            details: "Separate the commands with `;` (quote a `;` that belongs to a command). They run in order, all on the window that\n--window names. The first one that fails stops the batch: its error and its exit code are the answer. A batch cannot\nhold another batch.",
            example: "wm batch 'workspace 2; layout set tiling'"),
        CommandSpec(
            "set", "<key> <value>", "", "Change a config value until the next reload.",
            details: "The key is the config path, for example gaps.inner or tiling.split_ratio. Lists are comma-separated\n(scrolling.presets 0.3,0.5,1). `workspaces` and `url` only change in the config file.",
            example: "wm set gaps.inner 4"),
        CommandSpec(
            "menubar set", "<text>", "", "Show this text in the menu bar icon.",
            details: "The icon shows the text as it is, in place of the workspaces, until `wm menubar reset` or a restart. It is for the\nLua config: a `wm.on` handler can build the text from `wm.query` and call `wm.dispatch(\"menubar set ...\")`.\nThe automatic text is set with `menubar` in `wm.config`.",
            example: "wm menubar set 'build: ok'"),
        CommandSpec("menubar reset", "", "", "Go back to the automatic menu bar text."),
        CommandSpec("notify", "<text>", "[--seconds=n]", "Show a message on screen for 2 seconds (or n).", example: "wm notify 'build done'"),
        CommandSpec(
            "key send", "<chord>", "", "Send a key to the window's app, without focusing it.",
            details: "Use --window to choose the app. For a global hotkey of an app: bind a chord to this command.",
            example: "wm --window app:OBS key send cmd-shift-r"),
        CommandSpec(
            "key press", "<chord>", "", "Type a key, as if you pressed it.",
            details: "A chord such as cmd-shift-4, or a media key: volume_up, volume_down, mute, play, next, previous,\nbrightness_up, brightness_down. In Lua: wm.press(\"play\").",
            example: "wm key press play"),
    ]),
    CommandSection(title: "Inspect", specs: [
        CommandSpec(
            "list", "[what]", "[--focused] [--json]", "List windows, workspaces, monitors, keyboards or binds.",
            details: "With no argument it lists the workspaces and their windows. `what` picks one kind of thing:\n  windows     every window that wm manages\n  workspaces  the workspaces, their layout and their windows\n  monitors    the monitors, with their frame and work area\n  keyboards   the keyboards, and whether the config enables each one\n  memory      the entries that `window remember` keeps\n  binds       every key bind, with its description\nUse --json when a script reads the answer.",
            example: "wm list windows --json"),
        CommandSpec(
            "query", "[what]", "[--focused] [--json]", "The same as `list`.",
            details: "`wm query keyboards` shows the keyboards: name, `vendor:product` id, transport, whether the config enables it\n(`keyboards` in `wm.config`) and whether CapsLock is the hyper key on it now. Use the name or the id in the config.",
            example: "wm query keyboards"),
        CommandSpec(
            "pick", "", "[--json]", "Click a window and print what wm knows about it.",
            details: "Waits for your next left click and swallows it, so the app under the pointer does not get it. Escape or a right click cancels,\nand so does waiting 30 seconds. It prints the id, app, bundle id, pid, title, role, workspace, state and frame, the `--window`\nselectors that find it and a `wm.rule` table. It works for windows that wm does not manage too. --json prints the same as one object.\nIt only works from the command line, not from a bind, `batch` or Lua.",
            example: "wm pick --json"),
        CommandSpec(
            "subscribe", "[--snapshot] [event ...]", "", "Print one JSON event per line until stopped.",
            details: "With event names, only those events. With --snapshot, the first line is the state of wm now (`event` is\n`snapshot`, `state` is `wm list --json`). The events: " + subscribableEvents.joined(separator: ", ") + ".",
            example: "wm subscribe --snapshot window_focus workspace_changed"),
        CommandSpec(
            "logs", "", "[--lines=n] [--follow] [--output=otel|json]", "Show the log of the daemon.",
            details: "Short forms: -n, -f, -o. The default output is text in the OpenTelemetry log data model: time, severity, message,\nattributes. -o json prints one JSON object per line (time, level, message, source). It shows the last 100 records;\n-n 0 shows all. --follow waits for new records. It reads the log file ($XDG_STATE_HOME/wm/wm.log, else\n~/.local/state/wm/wm.log), so it works when the daemon is not running.",
            example: "wm logs -f -o json"),
    ]),
    CommandSection(title: "Memory", specs: [
        CommandSpec(
            "memory list", "", "[--json]", "List the entries that `window remember` kept.",
            details: "One line for each entry: the app, the title (`-` for an entry of the whole app), the workspace, the monitor, the mode and the\nframe. `wm memory` alone does the same. The entries are in memory.json, next to state.json.",
            example: "wm memory list --json"),
        CommandSpec(
            "memory forget", "<app>", "[--title=<text>] [--all]", "Remove the entry of an app, with no window needed.",
            details: "`app` is the name or the bundle id of the app, as `wm memory list` shows it (the case does not matter). Without options it removes the\nentry of the whole app. --title removes the entry that has this exact title, and --all every entry of the app. A window that is\nopen is not moved; the next window of the app opens as if nothing was remembered.",
            example: "wm memory forget com.superlogical.rex"),
        CommandSpec(
            "memory clear", "", "", "Remove every entry.",
            details: "It forgets all the entries that `window remember` kept, for every app. It does not touch the places that floating windows keep\nin float-memory.json.",
            example: "wm memory clear"),
    ]),
    CommandSection(title: "Daemon", specs: [
        CommandSpec("daemon start", "", "", "Start wm in the background."),
        CommandSpec("daemon stop", "", "", "Stop wm. Hidden windows come back on screen."),
        CommandSpec(
            "daemon status", "", "[--json]", "Show whether wm runs and its state (exit 1 if not).",
            details: "The exit code tells a script whether wm runs: 0 when it does, 1 when it does not.",
            example: "wm daemon status || wm daemon start"),
        CommandSpec(
            "daemon reload", "", "", "Load the config again.",
            details: "Reads init.lua again. A value that `wm set` changed goes back to what the config says.",
            example: "wm daemon reload"),
        CommandSpec(
            "doctor", "", "[--json]", "Check the config, the daemon and the permissions.",
            details: "One line for each check: ok, warn, fail or skip, and a hint when it is not ok. It exits with 1 when a check\nfailed (a warning is not a failure). It works without the daemon: the checks that need it are skipped.",
            example: "wm doctor"),
        CommandSpec(
            "config check", "[path]", "", "Load the config without applying it.",
            details: "Runs the config file (default: the config path, see ENVIRONMENT) in a new Lua state. Nothing is applied and nothing\nstarts: wm.exec and wm.dispatch do nothing, and wm.query finds nothing. A script that needs a query result at load time\nfails here. It prints the error with the file and the line, and exits with 1. It works without the daemon.",
            example: "wm config check ~/dotfiles/wm/init.lua"),
        CommandSpec(
            "lsp", "", "[--write] [--force]", "Set up autocomplete for the config in your editor.",
            details: "Prints the folder of the type stubs and the .luarc.json that lua-language-server needs, and the .taplo.toml that\ngives shortcuts.toml completion in Taplo. --write saves them next to the config file; --force replaces the files that are\nalready there. It works without the daemon.",
            example: "wm lsp --write"),
        CommandSpec(
            "init", "<osx|windows|i3|hyprland|niri>", "[--mod=<alt|cmd|ctrl|hyper>] [--force]", "Write a starter init.lua with the binds of that system.",
            details: "The templates follow the keys of macOS, Windows, i3, Hyprland and Niri. The mod key is the main modifier of the binds (the Super key of Linux): without --mod, wm asks for it on a terminal, and uses the default of the template (ctrl for osx, alt for the others) in a script. The file is the config path (see ENVIRONMENT). When it exists, wm prints the template and leaves the file as it is; --force replaces the file. It works without the daemon.",
            example: "wm init niri --mod=alt"),
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

private let globalOptions: [CommandOption] = [
    CommandOption("--window <w>", "Act on that window, not the focused one.\nA window is an id, focused, app:<name>, title:<re>, mark:<name> or pid:<n>."),
    CommandOption("--json", "Machine-readable output (list, query, pick, daemon status)."),
    CommandOption("-v, --verbose", "Print the state after the command."),
    CommandOption("-h, --help", "Show the help of a command."),
]

private let usageRows: [(String, String)] = [
    ("wm <command> [args]", "Run a command on the focused window."),
    ("wm --window <w> <command>", "Run it on another window."),
    ("wm help [command]", "The list below, or the details and examples of one command."),
    ("open \"wm://<command>/<args>\"", "The same commands as a URL, from any app or page."),
]

private let exampleRows: [(String, String)] = [
    ("wm focus left --wrap", "Move the focus; go around at the edge."),
    ("wm window send workspace 3 --stay", "Send the window away and keep the view."),
    ("wm --window app:Safari window close", "Close a window that is not focused."),
    ("wm list windows --json", "The windows as JSON, for a script."),
]

private let urlRows: [(String, String)] = [
    ("wm://<command>/<arg>...", "open \"wm://workspace/2\""),
    ("wm://<command>?args=<args>", "open \"wm://window/send/workspace/3?args=--stay\""),
]

private let exitCodeRows: [(String, String)] = [
    ("0", "Done."),
    ("1", "The command could not run now: the daemon is off, no such window, nothing to act on."),
    ("2", "Wrong use: an unknown command or option, a missing argument."),
]

private let environmentRows: [(String, String)] = [
    ("WM_CONFIG", "The config file (default ~/.config/wm/init.lua)."),
    ("XDG_CONFIG_HOME", "The folder that holds wm/init.lua."),
    ("XDG_STATE_HOME", "The folder of the log and of the saved state."),
    ("NO_COLOR", "No colors in the help and in errors. CLICOLOR_FORCE=1 forces them."),
]

/// The text of `wm help` (no topic), or of `wm help <command>`. `nil` when the topic is not a command. `style` adds colors;
/// the default is plain text.
public func renderHelp(topic: String? = nil, style: HelpStyle = .plain) -> String? {
    guard let topic, !topic.isEmpty else { return overviewHelp(style: style) }
    let wanted = topic.split(separator: " ").map(String.init)
    let matches = commandSpecs.filter { Array($0.words.prefix(wanted.count)) == wanted }
    guard !matches.isEmpty else { return nil }
    var lines: [String] = []
    if let exact = matches.first(where: { $0.words == wanted }) {
        lines += commandPage(exact, style: style)
        let related = matches.filter { $0 != exact }
        if !related.isEmpty {
            lines += ["", style.heading("Related")]
            for spec in related { lines += ["  " + styledUsage(spec, style), "      " + spec.summary] }
        }
    } else {
        lines.append(style.heading(topic))
        for spec in matches { lines += ["  " + styledUsage(spec, style), "      " + spec.summary] }
        lines += ["", style.dim("Run `wm help <command>` for the details and examples of one command.")]
    }
    if matches.contains(where: { $0.args.contains("<dir>") || $0.args.contains("[dir]") }) {
        lines += ["", style.dim("<dir> is left, right, up or down.")]
    }
    return lines.joined(separator: "\n") + "\n"
}

/// `wm window send workspace <name> [--stay]`, with a color for each kind of word.
private func styledUsage(_ spec: CommandSpec, _ style: HelpStyle) -> String {
    ["wm", style.command(spec.path), style.argument(spec.args), style.option(spec.flags)].filter { !$0.isEmpty }.joined(separator: " ")
}

/// The whole page of one command: usage, what it does, its options and an example.
private func commandPage(_ spec: CommandSpec, style: HelpStyle) -> [String] {
    var lines = [styledUsage(spec, style), "", "  " + spec.summary]
    if let details = spec.details { lines += [""] + reflow(details, width: 98).map { "  " + $0 } }
    if let options = commandOptions[spec.path], !options.isEmpty {
        lines += ["", style.heading("Options")] + optionLines(options, style: style)
    }
    if let example = spec.example { lines += ["", style.heading("Example"), "  " + style.example(example)] }
    return lines
}

/// The text in lines of at most `width` columns. The details are written with line breaks that fit a wide screen; this
/// joins the lines of a paragraph and wraps them again. A line that starts with a space is a list item and stays as it is.
func reflow(_ text: String, width: Int) -> [String] {
    var lines: [String] = []
    var paragraph: [Substring] = []
    func flush() {
        var line = ""
        for word in paragraph.flatMap({ $0.split(separator: " ") }) {
            if !line.isEmpty, line.count + 1 + word.count > width {
                lines.append(line)
                line = ""
            }
            line += (line.isEmpty ? "" : " ") + word
        }
        if !line.isEmpty { lines.append(line) }
        paragraph = []
    }
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        if line.hasPrefix(" ") {
            flush()
            lines.append(String(line))
        } else if line.isEmpty {
            flush()
            lines.append("")
        } else {
            paragraph.append(line)
        }
    }
    flush()
    return lines
}

/// A table of options: the option, then what it does; a longer text goes on under the first line.
private func optionLines(_ options: [CommandOption], style: HelpStyle) -> [String] {
    let width = options.map(\.flag.count).max() ?? 0
    return options.flatMap { option -> [String] in
        let text = option.text.split(separator: "\n").map(String.init)
        let first = "  " + style.option(option.flag) + String(repeating: " ", count: width - option.flag.count) + "  " + (text.first ?? "")
        return [first] + text.dropFirst().map { "  " + String(repeating: " ", count: width) + "  " + style.dim($0) }
    }
}

/// Two columns: the left one padded to the widest plain text, so the colors do not move the right one.
private func rows(_ pairs: [(String, String)], paint: (String) -> String) -> [String] {
    let width = pairs.map(\.0.count).max() ?? 0
    return pairs.map { "  " + paint($0.0) + String(repeating: " ", count: width - $0.0.count) + "  " + $0.1 }
}

private func overviewHelp(style: HelpStyle) -> String {
    let width = commandSpecs.map(\.signature.count).max() ?? 0
    var lines = [style.command("wm") + "  a tiling window manager for macOS", ""]
    lines.append(style.heading("USAGE"))
    lines += rows(usageRows, paint: style.command)
    lines += ["", style.heading("EXAMPLES")]
    lines += rows(exampleRows, paint: style.example)
    for section in commandSections {
        lines += ["", style.heading(section.title.uppercased())]
        for spec in section.specs {
            let args = spec.args.isEmpty ? "" : " " + style.argument(spec.args)
            let padding = String(repeating: " ", count: width - spec.signature.count)
            lines.append("  " + style.command(spec.path) + args + padding + "  " + spec.summary)
        }
    }
    lines += ["", style.heading("GLOBAL OPTIONS")] + optionLines(globalOptions, style: style)
    lines += ["", style.heading("URL SCHEME")] + rows(urlRows, paint: style.command)
    lines.append("  " + style.dim("exec, key, daemon and subscribe are blocked for URLs, unless `url.allow` in the config lists them."))
    lines += ["", style.heading("EXIT CODES")] + rows(exitCodeRows, paint: style.command)
    lines += ["", style.heading("ENVIRONMENT")] + rows(environmentRows, paint: style.command)
    lines += ["", style.dim("Run `wm help <command>` for details and examples, for example `wm help window`."), style.dim("<dir> is left, right, up or down.")]
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
