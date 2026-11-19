---
title: "Hints and scroll mode"
description: "Click and scroll from the keyboard."
group: Features
order: 7
---
Keyboard clicking and scrolling, as in Homerow. wm has no default keys for them:

```lua
wm.bind("cmd-shift-space", "hints")
wm.bind("cmd-shift-j", "scroll")
```

## Hints

`hints` works like the flash plugin of Neovim. It puts a label of **two letters** on every clickable element of the focused
window (buttons, links, fields, tabs, rows, checkboxes), of the menu bar, of the menu extras on its right, and of the Dock.
Type the two letters and wm clicks the element. With more than 676 elements the labels have three letters.

Press `/` to search instead. The search works as in fzf: type words separated by spaces, in any order, and each word matches
an element when its letters are in the title, description or value of the element in that order, with other letters between
them (`sv as` and `as sv` both find "Save As"; case does not count). Only the elements that match keep a label. As in
flash, a letter that could continue the last word in some match is never the first letter of a label, so every key is a label
key or a search key, not both. While the last word is empty (right after `/` or a space) there are no labels. When the
letters that are left for labels are too few for all the matches, the first matches (in reading order) get one: go on typing
to narrow the search.

| Key | Effect |
| --- | --- |
| two letters | click the element of that label |
| second letter with `Shift` | right click |
| second letter with `Cmd` | Cmd-click (a link opens in a new tab) |
| `/` | start a search |
| `Backspace` | undo a label letter, then a letter of the text, then the search |
| `Tab`, `Down`, `Ctrl-N` / `Shift-Tab`, `Up`, `Ctrl-P` | focus the next, previous match |
| `Return` | click the focused element, or the only match (`Shift`: right click) |
| `Return` again within 300 ms | double click |
| `Esc`, a mouse click | close |

A wrong second letter cancels the first one. A shortcut with Cmd, Ctrl or Alt ends the mode and goes to the app. Web pages work
too. A browser builds the tree of a page only for an assistive tool, so when wm finds a page with nothing in it, it sets
`AXManualAccessibility` and `AXEnhancedUserInterface` on the app (once for each app) and reads again. wm turns the second one
off and on around its own window moves, so the animations stay smooth. The click is
a real mouse click at the center of the element, so it works in web pages, the menu bar and the Dock. The pointer stays there.

## Two modes

- **`hints`** (search and click): as above. Typing a label clicks the element.
- **`hints --wait`** (search and wait): the search starts at once, with no `/`. A label does not click: it highlights its
  element, and so does the first title match (the green ring). Tab, Down and Ctrl-N, or Shift-Tab, Up and Ctrl-P,
  move the highlight. `Return` clicks it, `Shift-Return` right-clicks and `Cmd-Return` Cmd-clicks. `Return` again within
  300 ms double-clicks. Every label stays visible. Type a label or words of the title: the element that matches is highlighted, and the others
  are dimmed. Backspace widens the matches.

```lua
wm.bind("cmd-shift-space", "hints")
wm.bind("cmd-alt-space", "hints --wait")
```

## Label colors

```lua
wm.config { hints = {
  background = "#ffd60af5",    -- the background of a label
  text = "#141414",            -- the letters of a label
  focus = "#30d158",           -- the label and the ring of the focused element
  area = "#0a84ff",            -- the rings and the numbers of the scroll areas
} }
```

Colors are `"#rrggbb"` or `"#rrggbbaa"`. The letters of a label that you typed already are drawn with the same color, faded.
A reload of the config changes them.

## Scroll mode

`scroll` numbers the scroll areas of the focused window (up to ten, in reading order) and scrolls the active one, the largest
at first. The pointer moves to the active area, because scroll events go to the view under it.

| Key | Effect |
| --- | --- |
| `h` `j` `k` `l` | scroll left, down, up, right by 60 points |
| `Shift` + `h` `j` `k` `l` | dash: five times as far |
| `d`, `u` | half a page down, up |
| `gg`, `G` | top, bottom |
| `Tab`, `Down`, `Ctrl-N` / `Shift-Tab`, `Up`, `Ctrl-P` | next, previous area |
| `0`-`9` | the area of that number |
| `Esc`, a mouse click | close |

Both modes read the Accessibility tree of the app, so they show what the app gives them. A read looks at most 6000 elements.
On the first use in a browser wm waits a moment for the page; if it has no labels, press the key again. A web element that is not a link, button or field (a plain `div`
with a click handler) has no label. Not in wm: Homerow's labels-only mode and its tutor.
