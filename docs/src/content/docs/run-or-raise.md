---
title: "Run or raise"
description: "One key: focus the app if it runs, start it if it does not."
group: Features
order: 3
---
`wm focus app <name>` focuses a window of an app. `<name>` is the app name or the bundle id.

- It focuses the most recent window of the app.
- If the app already has the focus, it goes to the next window. One key walks through the windows.
- With `--launch`, an app that has no window starts.

```lua
wm.bind("alt-b", "focus app Safari --launch", { description = "Browser" })
wm.bind("alt-return", "focus app net.kovidgoyal.kitty --launch", { description = "Terminal" })
```
