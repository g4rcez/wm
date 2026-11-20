---
title: "URL scheme"
description: "Run wm commands from a wm:// URL."
group: Reference
order: 3
---
`wm://<command>/<arg>...` or `wm://<command>?args=<url-encoded arguments>`:

```sh
open "wm://workspace/2"
open "wm://focus?args=left"
open "wm://window/send/workspace/3?args=--stay"
```

Any app or web page can open a `wm://` URL. For that reason a URL may only run commands that act on wm itself, so `exec`, `key`, `daemon` and `subscribe` are blocked for URLs. The block also covers the commands inside a `batch`.
Allow one
on purpose with `url = { allow = { "exec" } }`.
