---
title: "Run or raise"
description: "One key: focus the app if it runs, start it if it does not."
group: Features
order: 3
---
`wm focus app <name>` focuses a window of an app (the name or the bundle id). The most recent window of the app gets the focus;
when the focus is on the app already, the next window of it, so one key walks through the windows. With `--launch` an app that has
no window starts:

```lua
wm.bind("alt-b", "focus app Safari --launch", { description = "Browser" })
wm.bind("alt-return", "focus app net.kovidgoyal.kitty --launch", { description = "Terminal" })
```
