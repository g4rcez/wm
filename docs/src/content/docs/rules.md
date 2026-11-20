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
| `name` | A label. It shows in `wm logs` (`rule=finder float,center`) and is what `wm.floating.disable` takes. It matches nothing. |

A rule needs at least one of `app`, `title`, `role`, `subrole` or `identifier`. A window must match all the fields of a rule. Rules apply in order, and later values win.

```lua
-- Every dialog of Notes floats; its documents tile.
wm.rule({ app = "com.apple.Notes", subrole = "AXDialog", float = true })
```

`wm logs` prints the role, subrole and identifier of windows that wm skips. Use it to find the value for a rule.

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
| `layout_options` | Tiling, scrolling and master options for this workspace only, for example `{ split_ratio = 0.6 }`. The master options have `master_` in front: `master_ratio`, `master_count`, `master_orientation`, `master_new_window`. |
