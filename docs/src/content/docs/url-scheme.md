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

Any app or web page can open a `wm://` URL. For that reason `exec`, `daemon` and `subscribe` are blocked for URLs. Allow one
on purpose with `url = { allow = { "exec" } }`.
