---
title: "Gestures"
description: "Swipes with 3 or 4 fingers, with or without modifier keys."
group: Configure
order: 4
---
`wm.gesture { mods, direction, command }` runs a command when you swipe with two fingers while you hold modifiers.

- `mods` is one or more of `alt`, `shift`, `ctrl` and `cmd` (`"alt+shift"`).
- `direction` is `left`, `right`, `up` or `down`. With natural scrolling (the macOS default), it is the direction of your fingers.
- The command is a string or a Lua function.
- It runs once per swipe, when the scroll has gone `threshold` points (10 to 2000, default 100).

macOS does not say how many fingers scroll. So a gesture with `mods` is a modifier and a direction. A swipe on an axis that
no gesture uses goes to the built-in Option + scroll, which moves the scrolling strip.

## Swipes with 3 or 4 fingers

The private MultitouchSupport framework says how many fingers touch the pad. wm reads it by default, so these swipes work
without a config. `trackpad.fingers` is the number of fingers: 4 (default) or 3.

| Swipe | Command |
| --- | --- |
| fingers left | `workspace next` |
| fingers right | `workspace prev` |
| fingers up | `overview open` |
| fingers down | `overview close` |

- On a scrolling workspace, the sideways swipe scrolls the strip instead (see below).
- A `wm.gesture` for the same fingers and direction replaces a built-in swipe.
- Name the fingers in the gesture instead of (or besides) the modifier:

```lua
wm.config { trackpad = { fingers = 4, scroll_fingers = 4, speed = 1 } }   -- enabled = false turns all of this off

wm.gesture { fingers = 4, direction = "up",   command = "overview" }
wm.gesture { fingers = 3, direction = "down", command = "workspace prev" }
```

- A swipe starts when the same number of fingers (3 or 4) has touched the pad for a few frames.
- It ends when the fingers lift or their number changes. Then no new swipe starts until all fingers are up.
- A gesture claims the swipe on its axis.
- A swipe that no gesture claims scrolls the strip when its finger count is `scroll_fingers`. The default is the same as `fingers`. Use 0 for never.
- The strip goes on a little after the fingers lift, then settles on a column.
- `speed` (0.1 to 10) sets how far a swipe moves the strip.
- With `trackpad = { enabled = true }`, wm shows a notification when the framework or a trackpad is missing. Without it, wm only writes a line to the log.
- A config reload looks for trackpads again.

## Title bar gestures

Two fingers on the title bar of a window, as in Swish. They are off by default, because they take the scroll that starts over a
title bar away from the app.

```lua
wm.config { trackpad = { title_bar = true, title_bar_height = 40, pinch = true } }
```

- The window under the pointer takes the focus and gets the action.
- No modifier is held.
- A swipe that starts over the title bar belongs to wm until it ends, also while it coasts.
- A swipe that starts elsewhere goes to the app.

| Gesture | Command | Floating window | Tiled window |
| --- | --- | --- | --- |
| swipe left | `window swipe left` | snaps to the left half (again: a third, two thirds) | moves left in the layout |
| swipe right | `window swipe right` | snaps to the right half | moves right in the layout |
| swipe up | `window swipe up` | fills the screen, or goes back | maximizes, or goes back |
| swipe down | `window swipe down` | minimizes | minimizes |
| pinch in | `window close` | closes the window | closes the window |
| pinch out | `window fullscreen` | fills the screen, or goes back | fills the screen, or goes back |

- `title_bar_height` (10 to 200, default 40) is how many points from the top of the window count as its title bar.
- wm tests the frame of the window and does not ask the app. So an app that draws its own title bar works too.
- A tab strip or a toolbar in that strip also counts.
- `pinch = false` turns the pinch off and keeps the swipes.
- A pinch needs exactly two fingers that stay put for a few frames. The distance between them must change by about 40% (closer) or 60% (further).
- A pinch does not work with a Magic Mouse.
- A `wm.gesture` with `zone = "title_bar"` replaces the built-in gesture of the same direction. It takes no `mods` and no `fingers`.
- `direction` is `left`, `right`, `up`, `down`, `pinch-in` or `pinch-out`.
- A window gesture runs on the window under the pointer:

```lua
wm.gesture { zone = "title_bar", direction = "pinch-in", command = "window minimize" }
wm.gesture { zone = "title_bar", direction = "down",     command = "window float on" }
```

- `wm list binds` shows them as `title_bar-scroll left` and `title_bar pinch-in`.
- The Mac gives a small haptic tap when a gesture runs, on a trackpad that has one.
- Not in wm: swipe and hold for a grid of quarters and thirds, moving a window to another screen with a swipe, and Dock gestures.
