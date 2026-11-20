---
title: "Window and workspace rules"
description: "Match new windows by app or title, and set per-workspace layouts, monitors and gaps."
group: Configure
order: 5
---
## Window rules

| Field | Meaning |
|---|---|
| `app` | Bundle id or app name. Exact match, case does not matter. |
| `title` | A regular expression, matched anywhere in the title. |
| `role`, `subrole` | The Accessibility role and subrole of the window, for example `subrole = "AXDialog"`. Exact match, case does not matter. |
| `identifier` | A regular expression, matched anywhere in the `AXIdentifier` of the window. It tells apart windows that have the same title, such as a settings window and a document. Many apps set none. |
| `float` | Open the window floating. |
| `workspace`, `layout` | Where it opens, and the layout of that workspace if it is empty. |
| `size`, `center` | For floating windows: `{ width, height }` as fractions of the screen (or points above 1), and centering. |
| `maximize` | Open maximized. |
| `width` | Column width in the scrolling layout, as a fraction of the screen. |
| `monitor` | Open on the workspace that this monitor shows: a role, its number (1 is the leftmost) or part of its name. `workspace` wins when both are set. |
| `focus = false` | Open without taking the focus. The window that had it gets it back. |
| `run` | A command or a list of commands to run after the other actions. |
| `stop = false` | Let later rules add to this one. By default the first match is the last. |
| `border` | The color of the focus border of the window: `"#f38ba8"`, or `{ "#f38ba8", "#fab387" }` for a gradient (`border.angle` in [`wm.config`](/docs/config) sets its direction). It needs `border.enabled` in the config. It is not the `border = false` of `wm.workspace`, which turns the border off for a workspace. |
| `dynamic = true` | Check the rule again when the title of the window changes. See [Dynamic rules](#dynamic-rules). |
| `name` | A label. It shows in `wm logs` (`rule=finder float,center`) and is what `wm.floating.disable` takes. It matches nothing. |

A rule needs at least one of `app`, `title`, `role`, `subrole` or `identifier`. A window must match all the fields of a rule. Rules apply in order, and later values win.

```lua
-- Every dialog of Notes floats; its documents tile.
wm.rule({ app = "com.apple.Notes", subrole = "AXDialog", float = true })
```

`wm logs` prints the role, subrole and identifier of windows that wm skips. Use it to find the value for a rule.

### Dynamic rules

A rule applies when a window opens. A window can change after that: a browser tab that you pop out becomes a window titled
"Picture-in-Picture", and a Zoom window that was a lobby becomes the meeting. With `dynamic = true` wm checks the rule again each
time the title of the window changes.

```lua
wm.rule { app = "org.mozilla.firefox", title = "^Picture-in-Picture$", float = true, dynamic = true }
wm.rule { app = "us.zoom.xos", title = "^Zoom Meeting$", workspace = 5, dynamic = true }
```

- When a window starts to match, it gets `float`, `size`, `center`, `workspace`, `monitor` and `border` of the rule. `run`, `layout`,
  `width`, `maximize` and `focus` are for the moment a window opens only.
- When it stops matching, it floats or tiles as it did before the rule. It stays on the workspace that the rule sent it to.
- wm acts on a change, not on every title: a window that keeps matching is left alone, so a window that you moved by hand stays
  where you put it until the rule stops or starts to match again. A window that changes more than 4 times in a second is left
  alone for that second.
- wm listens to the title changes of the apps that a dynamic rule can match, so an app with `app` set is cheap. A dynamic rule
  without `app` listens to every app, and each title change reads the windows again.
- `border` follows the same rule: a window that matches gets the color, and has its old one back when it stops matching.
- A rule that is not dynamic still applies once, when the window opens.

### Rules for one command

A rule can also belong to a command instead of an app: `wm exec` and `wm.exec` give the window that the command opens the same
actions as a rule (`float`, `workspace`, `layout`, `size`, `center`, `maximize`, `width`, `monitor`, `focus`, `run`). They go on
top of the rules above, and they apply once.

```lua
wm.exec("/Applications/Foo.app/Contents/MacOS/foo", { float = true, center = true, workspace = 3 })
wm.exec("open -a Notes", { app = "Notes", float = true, timeout = 20 })   -- `app`: a window of Notes may take them too
```

```sh
wm exec --float --workspace 3 -- /Applications/Foo.app/Contents/MacOS/foo
wm exec --app Notes --timeout 20 --float -- open -a Notes
```

wm gives the options to the first window that opens within `timeout` seconds (15 by default) and is a child of the command or, with
`app`, a window of that app. See [`wm.exec`](/docs/lua-api) and [`wm exec`](/docs/cli).

### Default floating rules

Some windows should not be tiled: the picture-in-picture window of Google Meet, the popup of a browser extension, Finder, Preview.
wm adds a list of rules for them, after the rules of your config, so these windows start **floating and centered** without any
setting. The list is `wm.floating.defaultRules`, and each entry is a normal `wm.rule` with a `name`:

| Name | Windows |
|---|---|
| `helium-popups`, `chrome-popups`, `chromium-popups`, `edge-popups`, `brave-popups`, `firefox-popups` | Windows of the browser that are not the browser: picture-in-picture (Google Meet, the "Picture-in-Picture" window of Firefox), extension popups, `about:blank` popups. A browser window has the name of the browser in its title (`... - Helium`); these have not. An empty title is a dialog and floats already. |
| `finder`, `preview`, `calculator`, `activity-monitor`, `archive-utility`, `quicktime-player` | The windows of these apps. |
| `system-settings`, `raycast-settings` | System Settings and the settings window of Raycast. |

Only the Helium title was checked on a real Mac. The others come from how the browsers name their windows: `... - Google Chrome`,
`... - Chromium`, and the name `Brave`, `Edge` or `Firefox` anywhere in the title (Edge writes a zero-width space inside its name, and
Firefox uses a long dash). The bundle ids of Chromium (`org.chromium.Chromium`) and Edge (`com.microsoft.edgemac`) were not checked
either. Read `wm logs` first if a browser does not match, because a pattern that misses the real windows would float all of them.

```lua
wm.floating.disable("finder", "preview")        -- tile these again (or: wm.floating.disable { "finder", "preview" })
wm.floating.enabled = false                     -- no default rule at all

wm.rule { app = "com.apple.finder", float = false }   -- a rule of yours for the same window wins: the config goes first

for _, rule in ipairs(wm.floating.defaultRules) do    -- change the list itself
  if rule.name == "preview" then rule.size = { 0.5, 0.85 } end
end
table.insert(wm.floating.defaultRules, { name = "notes", app = "com.apple.Notes", float = true, center = true })
```

An unknown name in `wm.floating.disable` is a config error. Rules apply to windows that open after the reload; use `wm window center`
for one that is open already.

## Workspace rules

`wm.workspace(name, options)` needs at least one option.

| Option | Meaning |
|---|---|
| `layout` | `scrolling`, `tiling`, `master`, `monocle` or `floating`. |
| `monitor` | Bind the workspace to a monitor (a role, a number or part of its name). Showing it shows it there. |
| `default` | With `monitor`: the monitor starts with this workspace. |
| `gaps`, `border` | Settings for this workspace only. |
| `on_empty` | A command that runs when the workspace is shown with no window on it: `"ghostty"`, or `{ cmd = "open -a Notes", app = "Notes", float = true }` with the options of [`wm.exec`](/docs/lua-api) for its window. The window goes to this workspace even if you have left it. Showing the workspace again while the command still waits for its window does not start it twice. |
| `persistent` | The workspace exists with no window: the menu bar lists it, and `workspace next` and `workspace prev` stop there. |
| `wallpaper` | A picture (an absolute path, or `~/...`) that the monitor shows while it shows this workspace. A workspace without one gives the monitor back the picture that it had before wm changed it. See [Wallpaper](#wallpaper) for the limits. |
| `layout_options` | Tiling, scrolling and master options for this workspace only, for example `{ split_ratio = 0.6 }`. The master options have `master_` in front: `master_ratio`, `master_count`, `master_orientation`, `master_new_window`. |

### Wallpaper

```lua
wm.workspace("1", { wallpaper = "~/Pictures/desk.jpg" })
wm.workspace("code", { wallpaper = "~/Pictures/dark.png" })
wm.workspace("special:term", { wallpaper = "~/Pictures/term.png" })   -- a special workspace wins over the one below it
```

When a monitor shows a workspace that has a `wallpaper`, wm sets that picture as the desktop picture of the monitor. When it shows a
workspace without one, the monitor gets the picture it had when wm first changed it. wm saves those original pictures in the state
folder and puts them back when it quits, and at the next start if it stopped without doing it.

This uses the public desktop picture call of macOS, so it has limits:

- It changes the desktop of the **current Space** only. Other Spaces keep their pictures.
- Each change takes a moment, and the picture can flash. It runs after the layout pass, but it still uses the main thread of wm.
- A dynamic wallpaper (day and night) or an aerial one cannot be set again: macOS reports its still picture, and that is what comes
  back. Pick a plain picture for the workspaces that you switch to often.
- A file that does not exist is logged once (`wm logs`, source `wallpaper`) and ignored.
