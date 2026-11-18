---
title: "Gestures"
description: "Swipes with 3 or 4 fingers, with or without modifier keys."
group: Configure
order: 4
---
`wm.gesture { mods, direction, command }` runs a command when you swipe with two fingers while you hold modifiers.
`mods` is one or more of `alt`, `shift`, `ctrl` and `cmd` (`"alt+shift"`). `direction` is `left`, `right`, `up` or
`down`. With natural scrolling, which is the macOS default, it is the direction of your fingers. The command can be a
string or a Lua function. It runs once per swipe, when the scroll has gone `threshold` points (10 to 2000, default 100).

macOS does not say how many fingers scroll, so a gesture with `mods` is a modifier and a direction. A swipe on an axis that
no gesture uses goes on to the built-in Option + scroll, which moves the scrolling strip.

## Swipes with 3 or 4 fingers

The private MultitouchSupport framework does say how many fingers touch the pad. wm reads it by default, and the swipes
below work without a config. `trackpad.fingers` (4 by default, or 3) is the number of fingers:

| Swipe | Command |
| --- | --- |
| fingers left | `workspace next` |
| fingers right | `workspace prev` |
| fingers up | `overview open` |
| fingers down | `overview close` |

On a scrolling workspace the sideways swipe scrolls the strip instead (see below). A `wm.gesture` for the same fingers
and direction replaces a built-in swipe. Name the fingers in the gesture instead of (or besides) the modifier:

```lua
wm.config { trackpad = { fingers = 4, scroll_fingers = 4, speed = 1 } }   -- enabled = false turns all of this off

wm.gesture { fingers = 4, direction = "up",   command = "overview" }
wm.gesture { fingers = 3, direction = "down", command = "workspace prev" }
```

- A swipe starts when the same number of fingers (3 or 4) has touched the pad for a few frames. It ends when the fingers
  lift, or when their number changes; then no new swipe starts until all fingers are up.
- A gesture claims the swipe on its axis, as above. A swipe that no gesture claims scrolls the scrolling strip when its
  finger count is `scroll_fingers` (the same as `fingers` unless you set it, or 0 for never). The strip goes on a little
  after the fingers lift and then settles on a column. `speed` (0.1 to 10) says how far a swipe moves the strip.
- With `trackpad = { enabled = true }` in the config, wm shows a notification when the framework or a trackpad is
  missing. Without it, wm only writes a line to the log. A config reload looks for trackpads again.
