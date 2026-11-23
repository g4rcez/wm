import Foundation

/// The text of `wm skills`: a skill (a SKILL.md file) that teaches an AI agent how to drive `wm`. The command reference
/// comes from `commandSections`, so it follows every new or changed command; only the framing is written here.
public func renderSkill() -> String {
    var lines: [String] = [
        "---",
        "name: wm",
        "description: Control the wm tiling window manager for macOS from the command line. Use it to focus, move, resize, float, tile or send windows, switch workspaces and layouts, read what wm manages as JSON, react to events, and check or fix the wm config and daemon.",
        "---",
        "",
        "# wm",
        "",
        "`wm` is a tiling window manager for macOS. The `wm` command talks to a background daemon (the wm app), so almost every",
        "command needs the daemon to run. Commands act on the focused window unless you choose another one.",
        "",
        "## Rules for an agent",
        "",
        "- Start with `wm daemon status`. It exits 0 when wm runs and 1 when it does not; then run `wm daemon start`.",
        "- Read state with `--json` (`wm list windows --json`, `wm list workspaces --json`, `wm list monitors --json`). Never parse the text output.",
        "- Look before you act: list the windows, pick the id or a selector, then run the command.",
        "- Prefer commands that set a state over ones that toggle it: `window float on` or `off`, `zen on`, not `window float` twice.",
        "- `wm help <command>` has the full details and an example for one command, and `wm help window` lists a group. Use it instead of guessing.",
        "- Exit code 0 means done, 1 means it could not run now (daemon off, no such window), 2 means wrong use (see `hint:` on stderr).",
        "- Do not edit the user's config unless asked. Check a config change with `wm config check` before it is saved, and use `wm doctor` for problems.",
        "- Commands that open an interface (`palette`, `hints`, `scroll`, `jump`, `select`, `switcher`, `overview`, `menu`, `cheatsheet`) wait for the user: do not run them to get information.",
        "",
        "## Choosing a window",
        "",
        "Put `--window <w>` before the command: `wm --window app:Safari window close`. `<w>` is one of:",
        "",
        "- an id from `wm list windows`, for example `3042`;",
        "- `focused` (the default), `app:<name>`, `title:<regex>`, `mark:<name>` or `pid:<n>`.",
        "",
        "`wm window mark <name>` gives a window a name that stays until it closes; `wm focus mark <name>` finds it again.",
        "",
        "## Workspaces, monitors and layouts",
        "",
        "- A workspace has a name (a number, or `special:<name>` for a special one) and a layout: `scrolling`, `tiling`, `master`, `monocle` or `floating`.",
        "- A monitor is `left`, `right`, `up`, `down`, `next`, `prev`, `last`, a role (`main`, `secondary`, `tertiary`), a number (1 is the leftmost) or part of its name.",
        "- `<dir>` is `left`, `right`, `up` or `down`.",
        "",
        "## Several commands",
        "",
        "- `wm batch 'workspace 2; layout set tiling'` runs commands in order and stops at the first error.",
        "- `wm subscribe --snapshot window_focus workspace_changed` prints one JSON event per line, for a script that reacts to wm. `wm help subscribe` lists the events.",
        "- `open \"wm://workspace/2\"` runs a command as a URL; `exec`, `key`, `daemon` and `subscribe` are blocked there unless the config allows them.",
        "",
        "## Examples",
        "",
        "```sh",
        "wm daemon status || wm daemon start",
        "wm list windows --json                   # ids, apps, titles, workspaces, frames",
        "wm focus left --wrap                     # move the focus; go around at the edge",
        "wm window send workspace 3 --stay        # send the window away and keep the view",
        "wm --window app:Safari window close      # act on a window that is not focused",
        "wm layout set master                     # change the layout of this workspace",
        "wm exec --float --center -- open -a Calculator",
        "```",
        "",
        "## Config",
        "",
        "The config is `~/.config/wm/init.lua` (Lua) and `shortcuts.toml` next to it. `WM_CONFIG` names another file. wm loads it again when it is saved.",
        "`wm init <template>` writes a starter config, `wm config check [path]` loads one without applying it, `wm daemon reload` loads it again,",
        "and `wm set <key> <value>` changes a value until the next reload. `wm lsp --write` sets up editor completion for the Lua API.",
        "",
        "## Commands",
        "",
        "Each line is `wm <command> <arguments> [options]` and what it does.",
    ]
    for section in commandSections {
        lines += ["", "### \(section.title)", ""]
        for spec in section.specs {
            lines.append("- `\(spec.usage)`: \(spec.summary)")
        }
    }
    lines += ["", "Options for every command: `--window <w>`, `--json` (list, query, pick, daemon status), `-v, --verbose` and `-h, --help`."]
    return lines.joined(separator: "\n") + "\n"
}
