import Foundation

/// The starter configs that `wm init` writes: the binds of macOS, Windows, i3, Hyprland or Niri.
public enum InitTemplate: String, CaseIterable, Sendable {
    case osx, windows, i3, hyprland, niri

    /// The modifier that the template uses when the user does not choose one. macOS uses ctrl for its Spaces keys; the
    /// others use alt, the same key as the Mod1 of i3 (the Super key of the other systems clashes with cmd shortcuts).
    public var defaultMod: String { self == .osx ? "ctrl" : "alt" }
}

/// The modifiers that a template can use as its main key. `hyper` is CapsLock (the template turns that on).
public let initModKeys = ["alt", "cmd", "ctrl", "hyper"]

/// The text of the `init.lua` for `template`, with `mod` as the main modifier.
public func initConfig(_ template: InitTemplate, mod: String) -> String {
    let body: String
    switch template {
    case .osx: body = osxTemplate
    case .windows: body = windowsTemplate
    case .i3: body = i3Template
    case .hyprland: body = hyprlandTemplate
    case .niri: body = niriTemplate
    }
    return "local mod = \"\(mod)\"\n" + initPrelude + body
}

/// Writes `text` to `url`. Returns `false` and leaves the file as it is when it exists and `force` is off.
public func writeInitConfig(_ text: String, to url: URL, force: Bool) throws -> Bool {
    if FileManager.default.fileExists(atPath: url.path), !force { return false }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url, options: .atomic)
    return true
}

private let initPrelude = #"""
-- Change `mod` above to alt, cmd, ctrl or hyper (CapsLock) to move every bind of this file to another key.
-- A drag with the mouse cannot use hyper, so it uses alt then.
local drag = mod == "hyper" and "alt" or mod
local terminal = "open -n -a Terminal"

-- Binds from shortcuts.toml, the file that the Shortcuts window writes. A bind below for the same keys replaces the shortcut:
-- move this line to the end of the file to let shortcuts.toml win, or delete it to use only this file.
wm.shortcuts()

local function bind(keys, command) wm.bind(mod .. "-" .. keys, command) end

"""#

private let osxTemplate = #"""
-- Made by `wm init osx`. The keys of macOS: ctrl-N and ctrl-arrows for the Spaces, cmd-tab for the switcher.
wm.config {
  layout = "tiling",
  gaps = { inner = 8, outer = 8 },
  border = { enabled = true, width = 2, active = "#89b4fa" },
  mouse = { move_modifier = drag, resize_modifier = drag },
  binds = { capslock = mod == "hyper" and "hyper" or nil, disable_system_cmd_tab = true },
}

wm.bind("cmd-tab", "switcher")
bind("up", "overview")
bind("left", "workspace prev")
bind("right", "workspace next")
for n = 1, 9 do
  bind(n, "workspace " .. n)
  bind("shift-" .. n, "window send workspace " .. n)
end

-- Place a window like the tiling of macOS: half of the screen, or all of it.
bind("shift-left", "window snap left")
bind("shift-right", "window snap right")
bind("shift-up", "window snap top")
bind("shift-down", "window snap bottom")
bind("shift-enter", "window maximize")
bind("shift-c", "window center")

-- The keys below use alt whatever `mod` is: ctrl-h, ctrl-j, ctrl-k, ctrl-l, ctrl-f, ctrl-p are keys of the shell.
wm.bind("alt-h", "focus left --wrap")
wm.bind("alt-j", "focus down --wrap")
wm.bind("alt-k", "focus up --wrap")
wm.bind("alt-l", "focus right --wrap")
wm.bind("alt-shift-h", "swap left")
wm.bind("alt-shift-j", "swap down")
wm.bind("alt-shift-k", "swap up")
wm.bind("alt-shift-l", "swap right")
wm.bind("alt-f", "window fullscreen")
wm.bind("alt-space", "window float")
wm.bind("alt-p", "palette")
wm.bind("alt-enter", "exec " .. terminal)
wm.bind("alt-shift-r", "daemon reload")
"""#

private let windowsTemplate = #"""
-- Made by `wm init windows`. The keys of Windows, with `mod` in the place of the Windows key: the arrows snap a window,
-- mod-ctrl and the arrows change the desktop (workspace), alt-tab is the switcher and alt-f4 closes a window.
wm.config {
  layout = "tiling",
  gaps = { inner = 6, outer = 6 },
  border = { enabled = true, width = 2, active = "#0078d4" },
  mouse = { move_modifier = drag, resize_modifier = drag },
  binds = { capslock = mod == "hyper" and "hyper" or nil },
}

bind("left", "window snap left")
bind("right", "window snap right")
bind("up", "window maximize")
bind("down", "window float off")          -- back into the tiles
bind("shift-left", "window send monitor left")
bind("shift-right", "window send monitor right")

wm.bind("alt-tab", "switcher")
wm.bind("alt-f4", "window close")
bind("ctrl-tab", "overview")              -- the task view
bind("ctrl-left", "workspace prev")
bind("ctrl-right", "workspace next")
bind("ctrl-d", "workspace empty")         -- a new desktop
for n = 1, 9 do
  bind(n, "workspace " .. n)
  bind("shift-" .. n, "window send workspace " .. n)
end

bind("e", "exec open -a Finder")
bind("r", "palette")
bind("enter", "exec " .. terminal)
bind("shift-s", "key press cmd-shift-4")  -- a screenshot of an area
bind("shift-r", "daemon reload")
"""#

private let i3Template = #"""
-- Made by `wm init i3` (https://i3wm.org/): the default keys of i3, with `mod` in the place of Mod1. The keys for the
-- focus are j k l ;, as in i3. Tabbed and stacking containers do not exist in wm: the scrolling layout has stacks.
wm.config {
  layout = "tiling",
  gaps = { inner = 0, outer = 0 },
  border = { enabled = true, width = 2, active = "#4c7899", inactive = "#333333" },
  mouse = { move_modifier = drag, resize_modifier = drag },
  binds = { capslock = mod == "hyper" and "hyper" or nil },
}

bind("enter", "exec " .. terminal)
bind("shift-q", "window close")
bind("d", "palette")                      -- dmenu
bind("shift-c", "daemon reload")

-- Focus and move
bind("j", "focus left")
bind("k", "focus down")
bind("l", "focus up")
bind("semicolon", "focus right")
bind("left", "focus left")
bind("down", "focus down")
bind("up", "focus up")
bind("right", "focus right")
bind("shift-j", "swap left")
bind("shift-k", "swap down")
bind("shift-l", "swap up")
bind("shift-semicolon", "swap right")
bind("shift-left", "swap left")
bind("shift-down", "swap down")
bind("shift-up", "swap up")
bind("shift-right", "swap right")

-- Containers
bind("h", "layout preselect right")       -- split horizontally: the next window opens on the right
bind("v", "layout preselect down")        -- split vertically
bind("e", "layout split toggle")
bind("f", "window fullscreen")
bind("shift-space", "window float")
bind("space", "focus layer")              -- between the floating and the tiled windows
bind("s", "layout set scrolling")
bind("t", "layout set tiling")

-- The scratchpad
bind("shift-minus", "window send workspace special:scratch")
bind("minus", "workspace special scratch")

-- Workspaces
for n = 1, 9 do
  bind(n, "workspace " .. n)
  bind("shift-" .. n, "window send workspace " .. n)
end

-- The resize mode of i3
wm.mode("resize", {
  j = "resize width -50", k = "resize height +50", l = "resize height -50", semicolon = "resize width +50",
  left = "resize width -50", down = "resize height +50", up = "resize height -50", right = "resize width +50",
  enter = "mode main", esc = "mode main",
})
bind("r", "mode resize")
"""#

private let hyprlandTemplate = #"""
-- Made by `wm init hyprland` (https://hypr.land/): the example keys of hyprland.conf, with `mod` in the place of
-- $mainMod. The tiling layout is the dwindle layout. Drag a window with `mod` and the mouse to move it, or with the
-- right button to resize it.
wm.config {
  layout = "tiling",
  gaps = { inner = 5, outer = 20 },
  border = { enabled = true, width = 2, radius = 10, active = "#33ccff", inactive = "#595959" },
  mouse = { move_modifier = drag, resize_modifier = drag },
  binds = { capslock = mod == "hyper" and "hyper" or nil },
}

bind("q", "exec " .. terminal)
bind("c", "window close")
bind("e", "exec open -a Finder")
bind("v", "window float")
bind("r", "palette")
bind("p", "window pseudo")                -- pseudo
bind("j", "layout split toggle")          -- togglesplit
bind("f", "window fullscreen")

-- Focus with the arrows
bind("left", "focus left")
bind("right", "focus right")
bind("up", "focus up")
bind("down", "focus down")
bind("shift-left", "swap left")
bind("shift-right", "swap right")
bind("shift-up", "swap up")
bind("shift-down", "swap down")

-- Workspaces: mod-1 to mod-0 show one, mod-shift-1 to mod-shift-0 send the window
for n = 1, 10 do
  local key = n % 10
  bind(key, "workspace " .. n)
  bind("shift-" .. key, "window send workspace " .. n)
end

-- The special workspace magic
bind("s", "workspace special magic")
bind("shift-s", "window send workspace special:magic")
"""#

private let niriTemplate = #"""
-- Made by `wm init niri` (https://github.com/niri-wm/niri): the default keys of niri, with `mod` in the place of Mod.
-- The layout is a strip of columns that scrolls: focus left and right move between columns, up and down inside one.
wm.config {
  layout = "scrolling",
  gaps = { inner = 16, outer = 16 },
  border = { enabled = true, width = 4, active = "#7fc8ff", inactive = "#505050" },
  mouse = { move_modifier = drag, resize_modifier = drag },
  scrolling = { presets = { 0.33333, 0.5, 0.66667 }, default_width = 0.5 },
  binds = { capslock = mod == "hyper" and "hyper" or nil },
}

bind("t", "exec " .. terminal)
bind("d", "palette")
bind("q", "window close")
bind("o", "overview")
bind("shift-r", "daemon reload")

-- Focus
bind("h", "focus left")
bind("j", "focus down")
bind("k", "focus up")
bind("l", "focus right")
bind("left", "focus left")
bind("down", "focus down")
bind("up", "focus up")
bind("right", "focus right")
bind("home", "focus column first")
bind("end", "focus column last")
bind("shift-h", "focus monitor left")
bind("shift-l", "focus monitor right")
bind("shift-left", "focus monitor left")
bind("shift-right", "focus monitor right")

-- Move
bind("ctrl-h", "swap left")
bind("ctrl-j", "swap down")
bind("ctrl-k", "swap up")
bind("ctrl-l", "swap right")
bind("ctrl-left", "swap left")
bind("ctrl-down", "swap down")
bind("ctrl-up", "swap up")
bind("ctrl-right", "swap right")

-- Workspaces: mod-u and mod-i walk them, mod-N shows one, mod-ctrl-N sends the column there
bind("u", "workspace next")
bind("i", "workspace prev")
for n = 1, 9 do
  bind(n, "workspace " .. n)
  bind("ctrl-" .. n, "window send workspace " .. n .. " --column")
end

-- Columns
bind("comma", "layout stack join")        -- the window goes into the column on its left
bind("period", "layout stack leave")
bind("w", "layout stack tabs")
bind("r", "layout column width cycle")
bind("f", "layout column expand")
bind("shift-f", "window fullscreen")
bind("c", "layout column center")
bind("minus", "resize width -50")
bind("equal", "resize width +50")
bind("v", "window float")
bind("shift-v", "focus layer")
"""#
