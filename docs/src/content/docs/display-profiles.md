---
title: "Display profiles"
description: "Run your own commands when a set of monitors connects: one setup for the desk, one for the laptop."
group: Features
order: 10
---
A display profile runs a function when the connected monitors are the ones you named. Use it to put workspaces on the right
monitors, change a layout, or move windows when you dock or undock.

```lua
wm.profile("desk", {
  monitors = { "dell", "main" },
  apply = function(monitors)
    wm.dispatch("workspace move monitor 1")
    wm.dispatch("layout set scrolling")
  end,
})

wm.profile("laptop", {
  monitors = { "main" },
  apply = function() wm.dispatch("layout set tiling") end,
})
```

## When a profile fits

- The number of connected monitors is the number of selectors.
- Each selector names a **different** monitor.
- A selector is a role (`main`, `secondary`, `tertiary`), a number (1 is the leftmost) or part of the name, in any case.
  These are the same selectors as the `monitor` field of `wm.rule`.
- The first profile that fits wins. Put the most specific profile first.

## Inside `apply`

- `apply` gets the list that `wm.query("monitors")` gives.
- Use `wm.dispatch` and `wm.query` inside it.
- `wm.rule`, `wm.workspace` and `wm.config` work only while the config loads. They cannot run in `apply`.
- Bind a workspace to a monitor with `wm.workspace` as usual. Use a profile for the commands.
- `wm.profile` can be called only while the config loads.

## When a profile runs

- When the displays change: a plug, an unplug, a lid that opens or closes. wm waits half a second, so one dock gives one run.
- When the config loads, and each time you save it (wm loads the config again, so the profile that fits runs again).
- It does not run again while it is still the profile that fits. When no profile fits, the next profile that fits runs.

`wm subscribe displays_changed` shows the event that starts a profile (`count` and `monitors`, the names from left to right).
