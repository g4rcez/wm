---
title: "Saved state"
description: "What wm saves to disk, and where."
group: Reference
order: 4
---
wm saves its layouts to `$XDG_STATE_HOME/wm/state.json`, or `~/.local/state/wm/state.json`. It saves half a second after a change
and when it quits.

## After a daemon restart

This covers a rebuild, a crash, and `wm daemon stop` then `start`.

- Windows that are still open go back to their workspace, layout, column sizes, stacks, tile blocks, split tree, scroll
  position, floating frame and monitor.
- wm matches windows by window id and bundle id. An app that you closed or relaunched meanwhile counts as new.
- A restored window runs no rules and fires no `window_open`.

## After a reboot

Window ids are new, and the apps open one by one over the next minute. wm sees the new start of the Mac (the state has the time
of the last start) and restores in another way.

- The saved layouts of all workspaces come back at once, with a place for every saved window.
- Each window that opens takes the place of the saved window of the same app. If there are several, it takes the one with the
  same title, else the first one in the layout.
- It gets the workspace, the floating state and frame, the marks, and the place, size, stack and tabs of that window.
- Displays are found by name when their ids changed.
- No rule and no `window_open` hook runs for a window that took a place.

While the places wait, the layouts show empty gaps where the apps have not opened yet.

- After 2 minutes, or as soon as every saved window is back, the places that nobody took are given up. The other windows
  close the gaps.
- wm saves nothing during that time, so a start in progress does not replace the good state.
- If you shut the Mac down within those 2 minutes, the old state is still there for the next start.
- A state saved by an older wm has no start time. It is restored the old way once. The next save adds the time.

## Sleep and lock

wm does not read or move windows while the Mac sleeps or is locked, and for two seconds after. A window moves only when you ask.

## Other rules

- A layout that you change in the config while wm is stopped wins over the saved one.
- A state saved by the removed `native` mode is ignored.
- Delete the file to start fresh.
