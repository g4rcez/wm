---
title: "URL scheme"
description: "Run wm commands from a wm:// URL."
group: Reference
order: 3
---
Format: `wm://<command>/<arg>...` or `wm://<command>?args=<url-encoded arguments>`.

```sh
open "wm://workspace/2"
open "wm://focus?args=left"
open "wm://window/send/workspace/3?args=--stay"
```

Any app or web page can open a `wm://` URL. So a URL may only run commands that act on wm itself.

- `exec`, `key`, `daemon` and `subscribe` are blocked for URLs.
- The block also covers the commands inside a `batch`.
- To allow one on purpose, use `url = { allow = { "exec" } }`.

To act on a window other than the focused one, add `window=<id>` or a selector: `wm://window/close?window=app:Safari`. A URL accepts `focused`, `app:`, `mark:`, `pid:` and an id; it does not accept `title:`, because that selector is a regular expression that runs on the main thread. Use `wm --window title:<regex>` on the command line instead.
