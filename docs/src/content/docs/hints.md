---
title: "Hints, scroll and select mode"
description: "Click, scroll and select text from the keyboard."
group: Features
order: 7
---
Click, scroll and select text from the keyboard, as in Homerow. wm has no default keys for these modes:

```lua
wm.bind("cmd-shift-space", "hints")
wm.bind("cmd-shift-j", "scroll")
wm.bind("cmd-shift-y", "select")
```

## Hints

`hints` works like the flash plugin of Neovim. It puts a label of **two letters** on every clickable element of:

- the focused window (buttons, links, fields, tabs, rows, checkboxes);
- the menu bar and the menu extras on its right;
- the Dock.

Type the two letters and wm clicks the element. With more than 676 elements, labels have three letters.

Press `/` to search instead. The search works as in fzf:

- Type words separated by spaces, in any order.
- A word matches an element when its letters are in the title, description or value of the element, in that order. Other letters may sit between them.
- `sv as` and `as sv` both find "Save As". Case does not count.
- Only the elements that match keep a label.
- As in flash, a letter that could continue the last word in some match is never the first letter of a label. Every key is a label key or a search key, not both.
- While the last word is empty (right after `/` or a space), there are no labels.
- When too few letters are left for all the matches, the first matches (in reading order) get a label. Keep typing to narrow the search.

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

- A wrong second letter cancels the first one.
- A shortcut with Cmd, Ctrl or Alt ends the mode and goes to the app.
- A key that the mode does not accept (a function key, an arrow, a sign it has no use for) ends the mode too, so it never gets stuck.
- The screenshot shortcuts of macOS (Cmd+Shift+3, 4, 5, 6) go to macOS and leave the mode open, so the picture shows it.

Web pages work too:

- A browser builds the tree of a page only for an assistive tool.
- When wm finds a page with nothing in it, it sets `AXManualAccessibility` and `AXEnhancedUserInterface` on the app (once for each app) and reads again.
- wm turns the second one off and on around its own window moves, so the animations stay smooth.
- The click is a real mouse click at the center of the element, so it works in web pages, the menu bar and the Dock. The pointer stays there.

## Two modes

- **`hints`** (search and click): as above. Typing a label clicks the element.
- **`hints --wait`** (search and wait): the search starts at once, with no `/`.
  - A label does not click. It highlights its element, and so does the first title match (the green ring).
  - Tab, Down and Ctrl-N, or Shift-Tab, Up and Ctrl-P, move the highlight.
  - `Return` clicks it, `Shift-Return` right-clicks and `Cmd-Return` Cmd-clicks.
  - `Return` again within 300 ms double-clicks.
  - Every label stays visible.
  - Type a label or words of the title: the element that matches is highlighted, and the others are dimmed.
  - Backspace widens the matches.

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

- Colors are `"#rrggbb"` or `"#rrggbbaa"`.
- The letters of a label that you typed already are drawn in the same color, faded.
- A reload of the config changes them.
- [`jump`](/docs/jump) uses the same colors for its numbers.

## Letters and scroll step

```lua
wm.config { hints = {
  letters = "asdfghjkl",       -- the letters of the labels, used in this order (default: the whole alphabet, home row first)
  scroll_step = 60,            -- points that h j k l scroll in scroll mode (10 to 500)
  scroll_dash_factor = 5,      -- what Shift multiplies the step by (1 to 20)
} }
```

- `letters` takes 4 to 26 different lowercase letters.
- With fewer letters, labels need more keys: `n` letters give `n × n` labels.
- The select mode keeps its own letters.

## Scroll mode

`scroll` numbers the scroll areas of the focused window (up to ten, in reading order). It scrolls the active one, the largest at first. The pointer moves to the active area, because scroll events go to the view under it.

| Key | Effect |
| --- | --- |
| `h` `j` `k` `l` | scroll left, down, up, right by 60 points |
| `Shift` + `h` `j` `k` `l` | dash: five times as far |
| `d`, `u` | half a page down, up |
| `gg`, `G` | top, bottom |
| `Tab`, `Down`, `Ctrl-N` / `Shift-Tab`, `Up`, `Ctrl-P` | next, previous area |
| `0`-`9` | the area of that number |
| `Esc`, a mouse click | close |

## Select text

`select` reads the text of the windows on the focused display. You select a part of it with the keyboard, then copy it or right-click on it. It has two steps.

**Search.** Every key is text.

- Case and accents do not count.
- The text can go over many words of one line.
- The places of the text are highlighted, and one of them is focused.

| Key | Effect |
| --- | --- |
| text, `Backspace` | change the search text |
| `Tab`, `Down`, `Ctrl-N` / `Shift-Tab`, `Up`, `Ctrl-P` | next, previous place |
| `Return` | select the focused place and go to the next step |
| `Esc`, a mouse click | close |

Without a text, `Return` selects the first word and every word gets a label.

**Select.** Every key is a command. Each place of the search text has a label of two letters.

| Key | Effect |
| --- | --- |
| a label | select that place; a second label extends the selection to its place |
| `h` `l`, `Left` `Right` | one character |
| `w`, `b`, `e` | next word, previous word, end of the word |
| `j` `k`, `Down` `Up` | the line below, above |
| `0`, `$`, `Cmd-Left`, `Cmd-Right` | start, end of the line |
| `v` | extend: the next moves keep the start of the selection |
| `y`, `Cmd-C`, `Return` | copy the selection |
| `Shift-Return` | right-click on the first word of the selection |
| `/`, `Backspace` | back to the search |
| `Esc`, a mouse click | close |

Where the text comes from:

- The text comes from the Accessibility tree.
- A window that gives fewer than 8 words (a terminal that draws its own text, a canvas) is read from a picture of the display. wm uses the text recognition of macOS, which needs the Screen Recording permission.
- Without that permission, those windows have no text, and the pill at the bottom says so.
- Recognized text can have a wrong letter.
- A picture inside a window that gives its text is not read.
- Password fields are not read.
- A read gives at most 3000 words.

Highlights and clicks:

- A part of a word is highlighted in proportion to its letters, so the edge is near the letter, not on it.
- The right-click goes to what is under the text. It does not select the text in the app.
- The colors are the ones of the labels: `background` for the places and `focus` for the selection.

### Change the keys of the select step

- Each action has a list of chords.
- An action that you set replaces its keys. The others keep theirs.
- A chord can belong to one action only, and `hyper` cannot be used.
- `Esc` always closes.
- A plain letter that is a key here never starts a label.

```lua
wm.config {
    select = { keys = {
        copy = { "y", "cmd-c" },          -- Return no longer copies
        right_click = "shift-enter",
        extend = "v",
        search = { "slash", "backspace" },
        left = { "h", "left" }, right = { "l", "right" }, down = { "j", "down" }, up = { "k", "up" },
        next_word = "w", previous_word = "b", word_end = "e",
        line_start = { "0", "cmd-left" }, line_end = { "4", "shift-4", "cmd-right" },
    } },
}
```

Limits:

- Hints and scroll mode read the Accessibility tree of the app, so they show what the app gives them.
- A read looks at most 6000 elements.
- On the first use in a browser, wm waits a moment for the page. If it has no labels, press the key again.
- A web element that is not a link, button or field (a plain `div` with a click handler) has no label.
- Not in wm: Homerow's labels-only mode and its tutor.
