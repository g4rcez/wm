---@meta
-- Type stubs for the `wm` Lua API, for lua-language-server (LuaLS). They give completion, hover help and
-- diagnostics for `~/.config/wm/init.lua`. wm never loads this file: it is only a description of the API.
-- Keep it in step with Sources/Scripting (ConfigParsing.swift, LuaState.swift, Chord.swift) and Sources/App.

---@alias wm.Layout "tiling"|"scrolling"|"master"
---@alias wm.WorkspaceMode "emulated"
---@alias wm.CenterMode "never"|"always"|"on-overflow"
---@alias wm.Side "left"|"right"
---@alias wm.Orientation "horizontal"|"vertical"
---@alias wm.TabIndicatorPosition "left"|"right"|"top"|"bottom"
---@alias wm.ColumnDisplay "normal"|"tabbed"
---@alias wm.LabelPosition "top-left"|"top-center"|"top-right"|"center"|"bottom-left"|"bottom-center"|"bottom-right"|"top"|"bottom"|"left"|"right"
---@alias wm.GestureDirection "left"|"right"|"up"|"down"

--- A color as `"#rrggbb"` or `"#rrggbbaa"` (the last pair is the alpha). Other forms are a config error.
---@alias wm.Color string

--- A wm command line, the same text as `wm <command>` in a shell. Any other string is also accepted.
--- An empty string swallows the key. See the "Commands" section of the README for all commands.
---@alias wm.Command
---| ""
---| "focus left" | "focus right" | "focus up" | "focus down"
---| "focus left --wrap" | "focus right --wrap" | "focus up --wrap" | "focus down --wrap"
---| "focus back" | "focus layer" | "focus layer floating" | "focus layer tiling"
---| "focus next" | "focus prev" | "focus next --wrap" | "focus prev --wrap"
---| "focus column first" | "focus column last" | "focus column 1" | "focus column 2" | "focus column 3"
---| "focus stack first" | "focus stack last" | "focus stack 1" | "focus stack 2" | "focus stack 3"
---| "focus monitor left" | "focus monitor right" | "focus monitor up" | "focus monitor down" | "focus monitor next" | "focus monitor prev" | "focus monitor last"
---| "focus monitor main" | "focus monitor secondary" | "focus monitor tertiary"
---| "move left" | "move right" | "move up" | "move down" | "move left 100" | "move right 100" | "move up 100" | "move down 100"
---| "swap left" | "swap right" | "swap up" | "swap down"
---| "resize smart +50" | "resize smart -50" | "resize width +50" | "resize width -50" | "resize height +50" | "resize height -50"
---| "workspace back" | "workspace special"
---| "workspace move monitor left" | "workspace move monitor right" | "workspace move monitor up" | "workspace move monitor down" | "workspace move monitor next" | "workspace move monitor prev" | "workspace move monitor last"
---| "window close" | "window float" | "window float on" | "window float off" | "window center" | "window fullscreen" | "window maximize" | "window native-fullscreen"
---| "window sticky" | "zen" | "zen on" | "zen off"
---| "window snap left" | "window snap right" | "window snap top" | "window snap bottom" | "window snap center"
---| "window snap top-left" | "window snap top-right" | "window snap bottom-left" | "window snap bottom-right"
---| "window raise-floating" | "window rescue" | "window unmark" | "window remember" | "window remember --title"
---| "window forget" | "window forget --title"
---| "window send monitor left" | "window send monitor right" | "window send monitor up" | "window send monitor down" | "window send monitor next" | "window send monitor prev" | "window send monitor last"
---| "window send monitor main" | "window send monitor secondary" | "window send monitor tertiary"
---| "window send strip horizontal" | "window send strip vertical"
---| "layout set tiling" | "layout set scrolling" | "layout set master"
---| "layout master promote" | "layout master count +1" | "layout master count -1" | "layout master ratio +0.05" | "layout master ratio -0.05"
---| "layout master orientation" | "layout master orientation left" | "layout master orientation right" | "layout master orientation top"
---| "layout master orientation bottom" | "layout master orientation center"
---| "layout balance" | "layout flip" | "layout rotate cw" | "layout rotate ccw"
---| "layout split toggle" | "layout split swap"
---| "layout column width cycle" | "layout column match" | "layout column center" | "layout column center-visible"
---| "layout column move first" | "layout column move last" | "layout column expand"
---| "layout stack join" | "layout stack join right" | "layout stack leave left" | "layout stack leave" | "layout stack tabs" | "layout stack equalize" | "layout stack height cycle"
---| "layout preselect left" | "layout preselect right" | "layout preselect up" | "layout preselect down"
---| "layout split root" | "layout split ratio +0.1" | "layout split ratio -0.1"
---| "window pseudo"
---| "workspace next" | "workspace prev" | "workspace empty" | "window send workspace next" | "window send workspace prev" | "window send workspace empty"
---| "layout tile" | "layout tile 2" | "layout tile 3" | "layout tile 2+1" | "layout tile 1+2" | "layout tile 4" | "layout tile 5" | "layout tile 6" | "layout tile 2/3" | "layout tile 3/4" | "layout tile 1/4" | "layout tile chain"
---| "menu" | "palette" | "palette windows" | "palette apps" | "palette tabs" | "palette reset" | "palette commands" | "palette menu" | "palette --cmdtab" | "palette --cmdtab --reverse"
---| "switcher" | "switcher next" | "switcher prev" | "switcher commit" | "switcher cancel" | "switcher --all"
---| "overview" | "overview open" | "overview close"
---| "hints" | "hints open" | "hints close"
---| "scroll" | "scroll open" | "scroll close"
---| "mode main"
---| "pointer window" | "pointer monitor"
---| "daemon reload"
---| string

--- A key bind: a command string, or a Lua function that runs when the key is pressed.
---@alias wm.Action wm.Command|fun()

--- Last key of a chord (the part after the modifiers): a letter, a digit, or one of these names.
--- A chord is modifiers and a key joined by `-` or `+`: `"alt-shift-h"`. Modifiers: `alt` (`opt`, `option`), `cmd`
--- (`command`), `ctrl` (`control`), `shift`. A sequence joins chords with `>`: `"ctrl-p>h"`.
---@alias wm.Key
---| "esc" | "space" | "tab" | "enter" | "backspace" | "delete"
---| "left" | "right" | "up" | "down"
---| "minus" | "equal" | "comma" | "period" | "slash" | "backslash" | "semicolon" | "quote" | "backtick"
---| "leftsquarebracket" | "rightsquarebracket"
---| "home" | "end" | "pageup" | "pagedown"
---| "f1" | "f2" | "f3" | "f4" | "f5" | "f6" | "f7" | "f8" | "f9" | "f10"
---| "f11" | "f12" | "f13" | "f14" | "f15" | "f16" | "f17" | "f18" | "f19" | "f20"

--- A chord such as `"alt-h"` or a key sequence such as `"ctrl-p>h"` or `"alt-space > t > n"`.
--- In one mode a chord cannot be both a bind by itself and the first step of a sequence, and a sequence
--- cannot be the start of a longer one (`a>b` and `a>b>c`).
---@alias wm.Chord string

-- wm.config ------------------------------------------------------------------------------------------------------

--- `outer` as a table: the gap of each side, in points. A side that is absent keeps its value.
---@class (exact) wm.GapSides
---@field top? number >= 0
---@field right? number >= 0
---@field bottom? number >= 0
---@field left? number >= 0

---@class (exact) wm.Gaps
---@field inner? number Points between windows, >= 0. Default 8.
---@field outer? number|wm.GapSides Points between windows and the screen edge, >= 0 (one number: all sides). Default 8.
---@field smart? boolean A workspace with one tiled window has no gaps. Default false.

---@class (exact) wm.Animations
---@field enabled? boolean Default true.
---@field rate? number Spring stiffness, >= 0.1; higher is faster. A long move ends in about 10 / rate seconds. Default 14.

---@class (exact) wm.Border
---@field enabled? boolean Default false.
---@field width? number Points, >= 0. Default 2.
---@field radius? number Points, >= 0. Default 10.
---@field active? wm.Color Color of the focused window's border. Default "#89b4fa".
---@field inactive? wm.Color Default "#00000000" (clear).

--- A tile pattern for `layout tile`: the cells are fractions of the screen, in reading order, and must fill it with straight cuts.
---@class (exact) wm.Template
---@field name string What `layout tile <name>` takes. No spaces, not "chain", unique in its list.
---@field key? string One key a-z or 0-9 (not "c") that picks it in the picker. Unique in its list.
---@field title? string Text in the menu bar menu. Default: the name.
---@field cells number[][] Two or more `{ x, y, width, height }`, each 0 to 1. With `area`, one cell `{ 0, 0, 1, 1 }` is also valid (tiling layout only).
---@field area? number[] `{ x, y, width, height }`, each 0 to 1: the part of the screen that the cells fill. Default the whole screen. A template with one cell and a smaller area (`wm.templates.centered`) keeps the windows as they are and lays them out inside the area.

--- The built-in templates, to put in a `templates` list.
---@class wm.BuiltInTemplates
---@field two wm.Template
---@field three wm.Template
---@field four wm.Template
---@field five wm.Template
---@field six wm.Template
---@field stack_left wm.Template
---@field stack_right wm.Template
---@field two_thirds wm.Template
---@field three_quarters wm.Template
---@field one_quarter wm.Template
---@field centered wm.Template The windows share the middle two thirds of the width (tiling layout only).

---@class (exact) wm.TilingConfig
---@field split_ratio? number Share of the cell that the first window gets, 0.1 to 0.9. Default 0.5.
---@field preserve_split? boolean Keep the orientation of a split when its sibling closes. Default true.
---@field smart_split? boolean A new window splits the tile on the side that the mouse pointer is nearest to. Default false.
---@field split_under_pointer? boolean A new window splits the tile under the mouse pointer (not the focused one), on the side nearest the pointer. Default false.
---@field force_split? "second"|"first" Where a new window goes in the split of the window it splits: "second" (right or bottom) or "first". Default "second".
---@field split_width_multiplier? number 0.1 to 3. A cell this many times wider than tall splits side by side, so an ultrawide screen shows more columns before stacking. Default 1.
---@field templates? wm.Template[] The patterns that the picker and the menu bar list for this layout, instead of the built-in ones. Not empty. `layout tile <name>` still takes a built-in name that is not in the list.

---@class (exact) wm.VerticalStrip
---@field side? wm.Side Side of the screen. Default "right".
---@field width? number Width of the zone as a fraction of the screen, 0.1 to 0.9. Default 0.25.
---@field row_height? number Height of a new row as a fraction of the zone, 0.05 to 1. Default 0.5.

---@class (exact) wm.ScrollingConfig
---@field presets? number[] Column widths as fractions of the screen, 0.05 to 1, not empty. `layout column width cycle` walks this list. Default { 0.33, 0.5, 0.66, 1.0 }.
---@field default_width? number Width fraction of a new column, 0.05 to 1. Default 0.5.
---@field center? wm.CenterMode When to center the focused column. Default "on-overflow".
---@field always_center_single_column? boolean A lone column sits in the middle, even with `center = "never"`. Default false.
---@field default_column_display? wm.ColumnDisplay "tabbed" makes every new column a tab stack. Default "normal".
---@field orientation? "horizontal"|"vertical"|"auto" The way the strip runs: columns side by side ("horizontal", the default), rows one under the other ("vertical"), or "vertical" on a screen that is taller than it is wide ("auto").
---@field single_window_fit? "keep"|"fill" A lone column fills the screen ("fill", the default) or keeps its width ("keep").
---@field visible_columns? integer With 2 or more columns but fewer than this number, the columns grow in proportion to fill the screen. 0 is off (the default).
---@field preset_heights? number[] Window heights in a stack as fractions of the column, 0.1 to 0.9, not empty. `layout stack height cycle` walks this list. Default { 0.33, 0.5, 0.66 }.
---@field sliver_width? number Points of an off-screen column that stay on screen, >= 0. Default 8.
---@field sliver_height? number Height fraction of an off-screen column, 0.05 to 1. Default 0.9.
---@field vertical? wm.VerticalStrip The vertical strip zone.
---@field templates? wm.Template[] The patterns that the picker and the menu bar list for this layout, instead of the built-in ones. Not empty. `layout tile <name>` still takes a built-in name that is not in the list.

---@class (exact) wm.TabIndicatorConfig
---@field enabled? boolean Draw a bar with one segment per tab at the edge of a tabbed column. Default true.
---@field position? wm.TabIndicatorPosition Edge of the column. Default "left".
---@field size? number Thickness in points, 1 to 40. Default 6.
---@field spacing? number Points between segments, 0 to 40. Default 3.
---@field radius? number Corner radius in points, >= 0. Default 3.
---@field active? wm.Color Segment of the focused window. Default "#89b4fa".
---@field inactive? wm.Color Other segments. Default "#9999a599".

---@class (exact) wm.SwitcherConfig
---@field thumbnails? boolean Picture of each window (needs Screen Recording). Default true.
---@field delay? number Seconds before the overlay shows, >= 0. Default 0.12.
---@field background? wm.Color Default "#0000008c".
---@field selected? wm.Color Color of the selected window. Default "#89b4fa".
---@field max_scale? number Largest scale of the miniature, 0.3 to 1. Default 0.85.

---@class (exact) wm.PrefixOffset
---@field x? number Points; positive is right. Default 0.
---@field y? number Points; positive is down. Default 0.

--- The floating key panel: a chip with the mode (or the prefix keys), then a chip per key that can be pressed next.
---@class (exact) wm.PrefixLabel
---@field enabled? boolean Show the panel for a prefix and for a binding mode. Default true.
---@field show_keys? boolean List the keys that can be pressed next (inside a mode, or after a prefix). Default true.
---@field position? wm.LabelPosition Default "bottom-center". "top" and "bottom" are the centered positions.
---@field offset? wm.PrefixOffset Moves the label from `position`.
---@field font_size? number 8 to 96. Default 11.
---@field font? string Name of a font, for example "SF Pro Rounded" or "Menlo". Empty or missing: the system font.
---@field background? wm.Color Default "#1e1e2ecc".
---@field foreground? wm.Color Default "#d6dff5".
---@field accent? wm.Color Color of the mode chip (drawn at 40% opacity). Default "#89b4fa".

---@class (exact) wm.MasterConfig
---@field ratio? number Share of the screen that the master area takes: 0.1 to 0.9. Default 0.55.
---@field count? integer How many windows are masters. Default 1.
---@field orientation? "left"|"right"|"top"|"bottom"|"center" Where the master area is. `center`: in the middle, with the stack on both sides. Default "left".
---@field new_window? "stack"|"master" Where a new window goes: the top of the stack (default) or the master.

---@class (exact) wm.ZenConfig
---@field width? number Width of the window in the zen mode (`wm zen`), as a fraction of the work area: 0.3 to 1. Default 0.7.

---@class (exact) wm.BindsConfig
---@field long_press_timeout? number Seconds a key is held for a `long_press` bind, 0.1 to 3. Default 0.4.
---@field disable_system_cmd_tab? boolean Turn off the Cmd+Tab and Cmd+Shift+Tab of macOS while wm runs. Default false.
---@field capslock? "hyper" Make CapsLock the `hyper` modifier for chords such as `hyper-k`: a tap alone types Esc. wm sets the key mapping of the keyboards (like `hidutil`) while it runs. Default: CapsLock is not changed.

--- The options of a mode (third argument of `wm.mode`).
---@class (exact) wm.ModeOptions
---@field once? boolean The mode ends after the first bind of it has run; the mode before it is back (`mode back`).
---@field swallow? boolean A key that the mode does not bind is not typed into the app. Default false.

--- The options of a bind (third argument of `wm.bind`, or a table with the action first in `wm.mode`).
---@class (exact) wm.BindOptions
---@field description? string Text for `wm list binds` and the key panel.
---@field repeating? boolean `false`: run once per press. `true`: a bind that runs for each repeat of the held key (with a plain bind on the same chord, that one runs only on the press). Without it a held key repeats the action.
---@field release? boolean Run when the key comes up. Not for sequences.
---@field long_press? boolean|number Run when the key is held (`binds.long_press_timeout`); a number is the seconds to wait for this bind, 0.1 to 3. Not for sequences.
---@field universal? boolean The bind works in every mode.
---@field submap_universal? boolean The same as `universal` (the name that Hyprland uses).
---@field hidden? boolean Leave the key out of the key panel.

--- A swipe with modifiers: a two-finger scroll that goes `threshold` points in one direction runs the command, once.
---@class (exact) wm.Gesture
---@field mods? string One or more of alt, shift, ctrl, cmd: "alt", "alt+shift". Needed unless `fingers` is set.
---@field fingers? 3|4 A swipe on the trackpad with this many fingers. Needs the trackpad on (the default). Replaces the built-in swipe for the same fingers and direction.
---@field direction wm.GestureDirection With natural scrolling, the direction of your fingers.
---@field command wm.Command|fun()
---@field threshold? number Points, 10 to 2000. Default 100.
---@field description? string

---@class (exact) wm.PrefixConfig
---@field timeout? number Deprecated and ignored. A sequence waits until the next key or Escape.
---@field menubar? boolean Show "..." in the menu bar icon while waiting. Default true.
---@field label? wm.PrefixLabel The floating label.

---@class (exact) wm.CommandsConfig
---@field mode? "normal"|"persistent" `normal`: the sequence ends after one command. `persistent`: the keys after the prefix stay active until `timeout` passes without a command. Default `normal`.
---@field timeout? number Milliseconds without a command after which a persistent sequence ends, 100 to 10000. Default 800.

---@class (exact) wm.UrlConfig
---@field allow? string[] Commands that `wm://` URLs may run besides the default ones. `exec`, `daemon` and `subscribe` are blocked by default.

---@class (exact) wm.TrackpadConfig
---@field enabled? boolean Read the trackpad for swipes with 3 or 4 fingers (a private macOS framework). Default true. `true` in the config also shows a notification when there is no trackpad; `false` turns the built-in swipes off.
---@field fingers? 3|4 Fingers of the built-in swipes: left is `workspace next`, right is `workspace prev`, up is `overview open`, down is `overview close`. Default 4.
---@field scroll_fingers? integer The swipe with this many fingers (3 or 4) scrolls the scrolling strip; 0 turns that off. Default: the value of `fingers`.
---@field speed? number How far a swipe moves the strip, 0.1 to 10. Default 1.

--- The keys are `default` (what a keyboard that is not named gets, true if missing), the name of a keyboard, or its `vendor:product`
--- in hex (`wm query keyboards` shows both). A keyboard that wm manages gets CapsLock as the hyper key (`binds.capslock`), also when it
--- connects later; one that it does not manage keeps its CapsLock. The id wins over the name. The match ignores case.
---@alias wm.KeyboardsConfig table<string, boolean>

---@class (exact) wm.FloatingConfig
---@field remember_position? boolean A window that a rule floats (the default floating rules too) opens where the last floating window of its app was when it closed, with that size. Default true.

---@class (exact) wm.OverviewConfig
---@field zoom? number A workspace is drawn as its screen times this, 0.2 to 0.75. Default 0.5.
---@field gap? number Points between two workspaces, 0 to 200. Default 48.
---@field backdrop? wm.Color The dim layer behind the workspaces. Default "#0f0f14db".

---@class (exact) wm.HintsConfig
---@field background? wm.Color The background of a label in hint mode. Default "#ffd60af5".
---@field text? wm.Color The text of a label. Default "#141414".
---@field focus? wm.Color The label of the focused element and the ring around that element. Default "#30d158".
---@field area? wm.Color The rings and the numbers of the scroll areas in scroll mode. Default "#0a84ff".

---@class (exact) wm.SpecialConfig
---@field size? number Size of a shown special workspace as a fraction of the work area, 0.5 to 1. Default 0.9.
---@field backdrop? wm.Color A dim layer on the monitor behind a shown special workspace, for example "#00000066". Default "" (none).
---@field hide_on_other_monitor? boolean A window of a normal workspace on another monitor that gets the focus hides the special workspace too. Default false.

---@class (exact) wm.MouseConfig
---@field move_modifier? string Hold these modifiers (for example "alt") and drag with the left button to move a window. Off by default.
---@field resize_modifier? string Hold these modifiers and drag with the right button to resize a window. Off by default.

---@class (exact) wm.FocusFollowsMouse
---@field enabled? boolean Keeps its value when missing.
---@field only_fully_visible? boolean The pointer focuses only windows that are fully on screen. Default false.

--- Every key is optional. Two `wm.config` calls merge: a key that is absent keeps its value. An unknown key is an error.
---@class (exact) wm.Config
---@field layout? wm.Layout Default layout of a workspace. Default "tiling".
---@field workspaces? wm.WorkspaceMode Kept for old configs. The only mode is "emulated" (wm hides windows); "native" was removed.
---@field gaps? wm.Gaps
---@field animations? wm.Animations
---@field border? wm.Border
---@field focus_follows_mouse? boolean|wm.FocusFollowsMouse Default false. A table can limit it to windows that are fully on screen.
---@field mouse_follows_focus? boolean Default false.
---@field start_at_login? boolean Only when running as wm.app. Default false.
---@field trackpad? wm.TrackpadConfig Swipes with 3 or 4 fingers.
---@field mouse? wm.MouseConfig Move and resize windows with a modifier and the mouse.
---@field wrap_focus? boolean `focus <dir>` wraps around at the edge. Default false.
---@field workspace_back_and_forth? boolean `workspace N` while N is shown goes back to the previous workspace. Default false.
---@field tiling? wm.TilingConfig
---@field scrolling? wm.ScrollingConfig
---@field tab_indicator? wm.TabIndicatorConfig The tabs of a tabbed column.
---@field switcher? wm.SwitcherConfig The Alt+Tab window switcher.
---@field prefix? wm.PrefixConfig Key sequences such as `ctrl-p>h`.
---@field binds? wm.BindsConfig
---@field zen? wm.ZenConfig The zen mode: the focused window alone, centered.
---@field floating? wm.FloatingConfig Floating windows: whether they open where the last one closed.
---@field keyboards? wm.KeyboardsConfig Which keyboards wm manages: `{ default = true, ["Keyboard name"] = false, ["046d:c52b"] = true }`. See `wm query keyboards`.
---@field overview? wm.OverviewConfig The overview (`wm overview`): all workspaces, one under the other.
---@field hints? wm.HintsConfig The colors of the labels of `hints` and of the areas of `scroll`.
---@field special? wm.SpecialConfig Special workspaces (`workspace special`): size, dim backdrop, when they hide.
---@field master? wm.MasterConfig The `master` layout.
---@field url? wm.UrlConfig
---@field commands? wm.CommandsConfig What a key sequence does after a command: one command (`normal`) or many until a pause (`persistent`).

-- wm.rule, wm.workspace ------------------------------------------------------------------------------------------

--- A rule needs at least one of `app`, `title`, `role`, `subrole` or `identifier`. Rules apply to each new window, in order, until one with `stop = true` (the default) matches.
---@class (exact) wm.Rule
---@field name? string A label for `wm logs` and for `wm.floating.disable`. It matches nothing.
---@field app? string Bundle id (`"com.apple.finder"`) or app name. Exact match, not case-sensitive.
---@field title? string Regular expression, matched anywhere in the window title.
---@field role? string Accessibility role (`"AXWindow"`). Exact match, not case-sensitive.
---@field subrole? string Accessibility subrole (`"AXStandardWindow"`, `"AXDialog"`, `"AXFloatingWindow"`). Exact match, not case-sensitive. `wm logs` shows it for skipped windows.
---@field identifier? string Regular expression, matched anywhere in the `AXIdentifier` of the window. It tells apart windows with the same title.
---@field float? boolean Open the window floating.
---@field workspace? string|integer Send the window to this workspace.
---@field layout? wm.Layout Layout of that workspace.
---@field size? [number, number] `{ width, height }`: fractions of the screen when <= 1, points when above 1.
---@field center? boolean Center the window. Default false.
---@field maximize? boolean Open the window maximized.
---@field width? number Column width of the window in the scrolling layout, a fraction of the screen, 0.05 to 1.
---@field monitor? string|integer Open on the workspace that this monitor shows: a role (`main`, `secondary`, `tertiary`), its number (1 is the leftmost) or part of its name. `workspace` wins when both are set.
---@field focus? boolean `false`: the window opens without taking the focus.
---@field run? wm.Command|wm.Command[] Commands that run after the other actions.
---@field stop? boolean `false` lets later rules add to this one. Default true.

--- Needs at least one field.
---@class (exact) wm.WorkspaceSpec
---@field layout? wm.Layout
---@field monitor? string|integer Binds the workspace to a monitor: a role (`main`, `secondary`, `tertiary`), its number (1 is the leftmost) or part of its name. Showing it shows it there.
---@field default? boolean With `monitor`: the monitor starts with this workspace.
---@field gaps? wm.Gaps Gaps of this workspace only.
---@field border? boolean `false` hides the focus border on this workspace.
---@field layout_options? wm.LayoutOptions Tiling and scrolling options of this workspace only.

--- The options of `tiling` and `scrolling`, flat.
---@class (exact) wm.LayoutOptions
---@field split_ratio? number
---@field preserve_split? boolean
---@field force_split? "second"|"first"
---@field smart_split? boolean
---@field split_under_pointer? boolean
---@field split_width_multiplier? number
---@field presets? number[]
---@field default_width? number
---@field center? wm.CenterMode
---@field always_center_single_column? boolean
---@field default_column_display? wm.ColumnDisplay
---@field orientation? "horizontal"|"vertical"|"auto"
---@field single_window_fit? "keep"|"fill"
---@field visible_columns? integer
---@field preset_heights? number[]
---@field sliver_width? number
---@field sliver_height? number
---@field vertical? wm.VerticalStrip

-- Events -------------------------------------------------------------------------------------------------------

---@alias wm.EventName
---| "window_open"
---| "window_close"
---| "window_focus"
---| "window_title"
---| "window_floating"
---| "window_fullscreen"
---| "window_moved"
---| "workspace_changed"
---| "special_changed"
---| "monitor_changed"
---| "displays_changed"
---| "layout_changed"
---| "mode_changed"
---| "config_reloaded"

--- Match fields for `wm.on`. The handler runs only when every field equals the same field of the event.
---@class (exact) wm.EventFilter
---@field id? integer
---@field app? string
---@field title? string
---@field workspace? string
---@field previous? string
---@field monitor? integer
---@field visible? boolean
---@field floating? boolean
---@field fullscreen? boolean
---@field native? boolean
---@field layout? wm.Layout
---@field mode? string

---@class wm.WindowOpenEvent
---@field id integer Window id.
---@field app string Bundle id.
---@field title string
---@field workspace string

---@class wm.WindowCloseEvent
---@field id integer

---@class wm.WindowFocusEvent
---@field id integer
---@field app string
---@field title string

---@class wm.WindowTitleEvent
---@field id integer
---@field app string
---@field title string The new title.

---@class wm.WindowFloatingEvent
---@field id integer
---@field floating boolean

---@class wm.WindowFullscreenEvent
---@field id integer
---@field fullscreen boolean
---@field native boolean `true`: the macOS fullscreen (`window native-fullscreen`); `false`: `window fullscreen`.

---@class wm.WindowMovedEvent
---@field id integer
---@field workspace string The workspace that the window is on now.
---@field previous string

---@class wm.WorkspaceChangedEvent
---@field workspace string
---@field previous string
---@field monitor integer

---@class wm.SpecialChangedEvent
---@field workspace string Name of the special workspace.
---@field monitor integer
---@field visible boolean

---@class wm.Keyboard
---@field name string The name that the keyboard tells (`Product`). Use it in `keyboards = { ["name"] = false }`.
---@field manufacturer? string
---@field id string `vendor:product` in hex, for example "046d:c52b". A built-in keyboard has no ids ("0000:0000").
---@field vendor_id integer
---@field product_id integer
---@field location_id integer
---@field transport string For example "USB", "Bluetooth", "FIFO" (the built-in keyboard) or "SPI".
---@field built_in boolean
---@field enabled boolean wm manages it: the config does not turn it off.
---@field hyper boolean CapsLock is mapped to F18 on this keyboard now (the hyper key).

--- The set of connected displays changed. It also fires once at start. A dock or an undock sends one event, 0.5 s after the last change.
---@class wm.DisplaysChangedEvent
---@field count integer Number of displays now.
---@field monitors string[] Their names, from the left one to the right one.

---@class wm.MonitorChangedEvent
---@field monitor integer
---@field name string Name of the monitor that has the focus now.
---@field workspace string Workspace on that monitor.

---@class wm.LayoutChangedEvent
---@field workspace string
---@field layout wm.Layout

---@class wm.ModeChangedEvent
---@field mode string

---@class wm.ConfigReloadedEvent

-- wm.query results -----------------------------------------------------------------------------------------------

---@class wm.Rect
---@field x number
---@field y number
---@field width number
---@field height number

---@class wm.Window
---@field id integer
---@field strip? wm.Orientation Only in a scrolling workspace.
---@field app string Bundle id.
---@field app_name string
---@field title string
---@field workspace string
---@field floating boolean
---@field sticky boolean Shown on every workspace of its monitor (`window sticky`).
---@field maximized boolean
---@field focused boolean
---@field marks string[] Names given with `window mark`.
---@field frame wm.Rect

---@class wm.Workspace
---@field name string
---@field layout wm.Layout
---@field visible boolean
---@field windows integer[] Window ids.
---@field strips table<wm.Orientation, integer[]> Window ids by strip; empty for a tiling workspace.

---@class wm.Monitor
---@field id integer
---@field name string
---@field index integer Position from the left, starting at 1 (the number that a monitor selector takes).
---@field role? "main"|"secondary"|"tertiary" The role that a monitor selector takes; `nil` for a fourth monitor or more.
---@field main boolean The monitor with the menu bar.
---@field workspace string Workspace on this monitor.
---@field special? string Special workspace shown here.
---@field focused boolean
---@field frame wm.Rect
---@field work_area wm.Rect

--- A window that `wm window remember` kept.
---@class wm.MemorizedWindow
---@field app string Bundle id.
---@field name string Name of the app.
---@field title? string Only for an entry made with `--title`.
---@field workspace string
---@field monitor? string Name of the monitor that showed the workspace.
---@field mode "floating"|"maximized"|"pseudo"|"tiled"
---@field floating boolean
---@field maximized boolean
---@field frame? table `{ x, y, width, height }` as fractions of the work area (floating windows).
---@field column_width? number Scrolling layout: fraction of the zone.
---@field strip? wm.Orientation
---@field marks string[]
---@field sticky? boolean

-- API ------------------------------------------------------------------------------------------------------------

---@class wm
---@field version string Version of the Lua API.
---@field commands? wm.CommandsConfig `wm.commands = { mode = "persistent", timeout = 800 }`: the same as `wm.config { commands = ... }`.
---@field templates wm.BuiltInTemplates The built-in tile templates, to mix with your own in `templates`.
wm = {}

--- Sets options. Only while the config file loads.
---@param options wm.Config
function wm.config(options) end

--- Binds a chord or a key sequence. Only while the config file loads.
---@param chord wm.Chord
---@param action wm.Action A command, or a function. An empty string swallows the key.
---@param options? wm.BindOptions
function wm.bind(chord, action, options) end

--- Types a key when a chord is pressed. The key goes down, repeats and comes up with it, and the modifiers that are held
--- besides the ones of `chord` go with it: with `wm.remap("hyper-h", "left")`, `hyper-shift-h` types shift-left.
--- `target` is a chord such as `left`, `cmd-right`, or a media key: volume_up, volume_down, mute, play, next, previous,
--- brightness_up, brightness_down. Only while the config file loads.
---@param chord wm.Chord A single chord. `hyper` is a modifier when `binds.capslock = "hyper"`.
---@param target string
---@param options? wm.BindOptions
function wm.remap(chord, target, options) end

--- Types a key now, as a press and a release (the same as `wm key press`). Works in a function bind.
---@param chord string A chord such as `cmd-shift-4`, or a media key such as `play`.
---@return string? stdout
---@return string? stderr
function wm.press(chord) end

--- Defines a mode (a submap). `wm.bind("alt-shift-r", "mode resize")` enters it, `esc = "mode main"` leaves it.
--- A key is a chord or a key sequence; an action can be a table `{ "command", description = "...", hidden = true }`,
--- or a remap `{ remap = "left", description = "..." }`.
--- The key panel lists the binds of the active mode. Only while the config file loads.
---@param name string Not `*` and not `back`.
---@param binds table<wm.Chord, wm.Action|table>
---@param options? wm.ModeOptions
function wm.mode(name, binds, options) end

--- Runs a command when you swipe with modifiers held. Only while the config file loads.
---@param spec wm.Gesture
function wm.gesture(spec) end

--- Default rules for windows that start floating and centered: browser popups and picture-in-picture (Google Meet), Finder, Preview
--- and small utilities. They are added after the config has run, so a `wm.rule` of yours for the same window wins.
---@class wm.Floating
---@field enabled boolean `false` turns every default rule off. Default true.
---@field disabled table<string, boolean> The names that `disable` turned off.
---@field defaultRules wm.Rule[] The list. Each rule has a `name`. Change it before the config ends: `table.insert`, `table.remove`, or edit a rule.
wm.floating = {}

--- Turns default rules off by name: `wm.floating.disable("finder", "preview")` or `wm.floating.disable { "finder", "preview" }`.
--- An unknown name is a config error. Only while the config file loads.
---@overload fun(names: string[])
---@param ... string
function wm.floating.disable(...) end

--- Adds a window rule. Only while the config file loads.
---@param spec wm.Rule
function wm.rule(spec) end

--- What `wm.profile` takes.
---@class (exact) wm.ProfileSpec
---@field monitors (string|integer)[] One selector for each connected monitor: a role (`"main"`, `"secondary"`, `"tertiary"`), its number (1 is the leftmost) or part of its name. The profile fits when the number of monitors is the same and each selector names a different monitor.
---@field apply fun(monitors: wm.Monitor[]) Runs when the profile starts to fit. Use `wm.dispatch` and `wm.query` in it.

--- Runs `apply` when the connected monitors fit `monitors`: when the displays change and when the config loads. The first profile
--- that fits wins, in the order of the calls. Only while the config file loads.
---@param name string
---@param spec wm.ProfileSpec
function wm.profile(name, spec) end

--- Sets the layout, monitor and settings of one workspace. Only while the config file loads.
---@param name string|integer
---@param spec wm.WorkspaceSpec
function wm.workspace(name, spec) end

--- Runs `handler` when an event happens. The optional `filter` limits it to events with equal field values.
---@overload fun(event: "window_open", handler: fun(e: wm.WindowOpenEvent))
---@overload fun(event: "window_open", filter: wm.EventFilter, handler: fun(e: wm.WindowOpenEvent))
---@overload fun(event: "window_close", handler: fun(e: wm.WindowCloseEvent))
---@overload fun(event: "window_close", filter: wm.EventFilter, handler: fun(e: wm.WindowCloseEvent))
---@overload fun(event: "window_focus", handler: fun(e: wm.WindowFocusEvent))
---@overload fun(event: "window_focus", filter: wm.EventFilter, handler: fun(e: wm.WindowFocusEvent))
---@overload fun(event: "window_title", handler: fun(e: wm.WindowTitleEvent))
---@overload fun(event: "window_title", filter: wm.EventFilter, handler: fun(e: wm.WindowTitleEvent))
---@overload fun(event: "window_floating", handler: fun(e: wm.WindowFloatingEvent))
---@overload fun(event: "window_floating", filter: wm.EventFilter, handler: fun(e: wm.WindowFloatingEvent))
---@overload fun(event: "window_fullscreen", handler: fun(e: wm.WindowFullscreenEvent))
---@overload fun(event: "window_fullscreen", filter: wm.EventFilter, handler: fun(e: wm.WindowFullscreenEvent))
---@overload fun(event: "window_moved", handler: fun(e: wm.WindowMovedEvent))
---@overload fun(event: "window_moved", filter: wm.EventFilter, handler: fun(e: wm.WindowMovedEvent))
---@overload fun(event: "workspace_changed", handler: fun(e: wm.WorkspaceChangedEvent))
---@overload fun(event: "workspace_changed", filter: wm.EventFilter, handler: fun(e: wm.WorkspaceChangedEvent))
---@overload fun(event: "special_changed", handler: fun(e: wm.SpecialChangedEvent))
---@overload fun(event: "special_changed", filter: wm.EventFilter, handler: fun(e: wm.SpecialChangedEvent))
---@overload fun(event: "monitor_changed", handler: fun(e: wm.MonitorChangedEvent))
---@overload fun(event: "monitor_changed", filter: wm.EventFilter, handler: fun(e: wm.MonitorChangedEvent))
---@overload fun(event: "displays_changed", handler: fun(e: wm.DisplaysChangedEvent))
---@overload fun(event: "displays_changed", filter: wm.EventFilter, handler: fun(e: wm.DisplaysChangedEvent))
---@overload fun(event: "layout_changed", handler: fun(e: wm.LayoutChangedEvent))
---@overload fun(event: "layout_changed", filter: wm.EventFilter, handler: fun(e: wm.LayoutChangedEvent))
---@overload fun(event: "mode_changed", handler: fun(e: wm.ModeChangedEvent))
---@overload fun(event: "mode_changed", filter: wm.EventFilter, handler: fun(e: wm.ModeChangedEvent))
---@overload fun(event: "config_reloaded", handler: fun(e: wm.ConfigReloadedEvent))
---@overload fun(event: "config_reloaded", filter: wm.EventFilter, handler: fun(e: wm.ConfigReloadedEvent))
---@param event wm.EventName
---@param filter wm.EventFilter|fun(e: table)
---@param handler? fun(e: table)
function wm.on(event, filter, handler) end

--- Runs a wm command, like `wm <command>` in a shell.
---@param command wm.Command
---@param options? { window: integer|string } `window`: the command acts on this window: an id, or "focused", "app:<name>", "title:<regex>", "mark:<name>", "pid:<n>".
---@return string? stdout nil when the command failed.
---@return string? stderr Only when the command failed.
function wm.dispatch(command, options) end

--- Reads the state of wm.
---@overload fun(kind: "windows"): wm.Window[]
---@overload fun(kind: "focused"): wm.Window?
---@overload fun(kind: "workspaces"): wm.Workspace[]
---@overload fun(kind: "monitors"): wm.Monitor[]
---@overload fun(kind: "monitor"): wm.Monitor?
---@overload fun(kind: "memory"): wm.MemorizedWindow[]
---@overload fun(kind: "keyboards"): wm.Keyboard[]
---@param kind "windows"|"focused"|"workspaces"|"monitors"|"monitor"|"memory"|"keyboards"
---@return table?
function wm.query(kind) end

--- Runs a shell command in the background.
---@param command string
function wm.exec(command) end

--- Writes to the wm log (`wm logs`, level info, source `lua`). Arguments are joined with a space.
---@param ... any
function wm.log(...) end
