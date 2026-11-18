---
title: "Menu Anywhere"
description: "Show the menus of the focused app as a pop-up at the mouse pointer."
group: Features
order: 6
---
`wm.bind("ctrl-alt-m", "menu")` shows the menus of the focused app as a pop-up menu at the mouse pointer, so you do not have
to move to the menu bar. Choosing an item runs it in that app. wm reads the menus through the Accessibility API, so it
shows what the app gives it: items that an app adds only when you open its menu can be missing, and a big menu (Xcode, Office)
takes a moment. A read looks at four levels and at most 3000 items. `wm --window app:Notes menu` shows the menus of
another app.
