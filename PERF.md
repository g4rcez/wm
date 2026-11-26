# Performance ledger

Every performance idea that was measured, kept or not, so that a dead idea is not tried again. Measure the same way before and
after; a change that does not beat the run-to-run noise is reverted. Numbers are from a MacBook (Built-in Retina Display, 120 Hz)
with 7 apps and 7 to 14 windows, 2026-11-26.

## How to measure

- Animations: start the daemon with `WM_DEBUG=1` (`wm daemon stop`, then `open --env WM_DEBUG=1 -a wm`), animate, and read the
  `animation` row of `wm daemon status`: tick timing, `work` (wm's own time per frame), `relayouts`, `replaced` frames and the
  write time of each app.
- A refresh that reads the windows for more than 50 ms logs `reading the windows took ...` (`source: refresh`).

## Ledger

| Idea | Baseline → result | Verdict | Why |
|---|---|---|---|
| Refresh only the app that changed, not every app | Full read of all windows: 9.7–13 ms sum, ~5 ms slowest app (warm), 80 ms / 19 ms cold; apps are read in parallel | not done | Far under one frame. A partial read would make windows count as closed. Logging slow reads instead. |
| One size write per animation frame instead of size + position + size | Helium resize frame: 4.8 / 6.4 ms → 6.2 / 2.0 ms (two runs each) | rejected | Inside the noise, and the window ended at the wrong width (the app clamps a size against the old position). |
| Cache `AXEnhancedUserInterface` per app instead of reading it each frame | read 0.01–0.05 ms, toggle off+on 0.1 ms | rejected | Too small to matter. |
| No AX snapshot and no 120 Hz clock on a plain click | a snapshot of every app (2 AX reads per window) and a display link per mouse-down | kept | Work removed from every click; needed only for a press near a tiled window's edge or title bar. |
| Option-scroll / strip scroll: coalesce relayouts | relayout per scroll event; menu bar and wallpaper already skip unchanged work | not done | Not measured on a live daemon yet: read `relayouts` in `wm daemon status` first. |
| Log writes on a background queue | 7,498 records in 9 days | rejected | A few records a minute: nothing to win. |
| Topmost window under the pointer for focus-follows-mouse | window list 0.3–0.6 ms per call | kept, only where windows overlap | A tiled layout keeps the frame-only check; the list is read only when two windows are under the pointer. |
| A NaN frame | the animation clock never stopped: ~9% CPU at idle | fixed | Non-finite numbers are refused and the animator snaps. |
