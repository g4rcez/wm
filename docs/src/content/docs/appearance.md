---
title: "Appearance"
description: "One look for every overlay: native macOS by default, or your own theme."
group: Configure
order: 7
---
wm draws a few overlays of its own: the [command palette](/docs/palette), the [cheatsheet](/docs/cheatsheet), the
[switcher and the overview](/docs/switcher), the template picker and the [key label](/docs/key-panel). The `appearance` key of
`wm.config` sets one look and feel for all of them. There is no setting for a single overlay, so they always match.

By default they look like macOS: system blur, light and dark mode that follows the system, and the accent color and the
selection color that you chose in System Settings. You do not need to set anything.

```lua
wm.config { appearance = {
  style = "native",         -- "native" (the default) or "hud"
  theme = "system",         -- "system" | "light" | "dark"
  density = "comfortable",  -- "compact" | "comfortable" | "spacious"
} }
```

## Styles

The pictures on this page are illustrations drawn from the values of each look. They are not screenshots, so the real blur and
fonts differ a little.

- **`native`:** system materials (`popover`), 12 point corners, the system text and accent colors, and the selection color of a
  menu for the selected row. No color is fixed, so light mode works.

![The native style in light mode](/appearance/appearance-native-light.png)

![The native style in dark mode](/appearance/appearance-native-dark.png)

- **`hud`:** a dark blur, 20 point corners and a blue accent, in light mode too. It is one dark look for every overlay, not the
  mix of sizes that wm had before.

![The hud style](/appearance/appearance-hud.png)

## Keys

Every key is optional. A key that is absent comes from the preset of `style`.

| Key | What it does |
|---|---|
| `style` | `"native"` or `"hud"`. |
| `density` | `"compact"`, `"comfortable"` or `"spacious"`. Rows, panel widths, chips and paddings of every overlay grow or shrink together (0.85, 1 and 1.2 times). |
| `theme` | `"system"` follows macOS. `"light"` or `"dark"` forces one. |
| `material` | The blur: `"popover"`, `"menu"`, `"hud"`, `"sidebar"`, `"sheet"`, `"window"` or `"none"`. `"none"` is a flat system color without blur. The overview draws no blur and ignores it. |
| `accent` | The selected tile, the active tab, the chip of the mode. Default: the accent color of macOS. |
| `background` | A color drawn over the blur. In the overview it is the dim layer behind the workspaces, never more opaque than 85%. Default: none. |
| `foreground`, `secondary` | The text, and quieter text. Default: the label colors of macOS. |
| `selection` | The highlight of the selected row of the palette. Default: the selection color of macOS (the text of that row turns to the color that goes with it). |
| `border`, `border_width` | The line around the overlays (0 to 6 points). Default: the separator color of macOS, 1 point, where an overlay has a line. |
| `radius` | Corner radius in points, 0 to 48. The key label becomes a capsule when the radius is bigger than the label is tall. |
| `shadow` | The shadow of the windows. The switcher and the overview cover the screen and have none. |
| `font`, `mono_font` | A font name such as `"SF Pro Rounded"`, and the font of hints and key caps. Default: the system fonts. |
| `font_size` | The body size in points, 8 to 40 (default 13). The other text scales with it. |
| `animation` | Seconds of the fades, 0 to 2. `0` turns them off. Default 0.12. |

Two `wm.config` calls merge key by key, as the rest of the config does. A reload applies the new look the next time an overlay
opens.

## Upgrading

These keys styled one overlay. They are gone, but a config that still sets one keeps loading: wm reads each as the key
below, and an `appearance` key you set yourself wins over it. Move to the new key when you can:

| Removed | Use |
|---|---|
| `switcher.background`, `overview.backdrop`, `prefix.label.background` | `appearance.background` |
| `switcher.selected`, `prefix.label.accent` | `appearance.accent` |
| `prefix.label.foreground` | `appearance.foreground` |
| `prefix.label.font_size` | `appearance.font_size` (the label is a little smaller than the body text) |
| `prefix.label.font` | `appearance.font` |

`style = "hud"` is also not the exact look of the old overlays: every overlay is dark now, with the same corners.

## Themes to copy

Each one is the whole look. Paste one into your config, then change what you like. They all pass `wm config check`.

### Catppuccin Mocha

Solid dark with one accent. Every overlay uses the same colors, corners and fonts.

![The Catppuccin Mocha theme](/appearance/appearance-catppuccin.png)

```lua
wm.config { appearance = {
  theme = "dark", material = "none", radius = 14,
  accent = "#cba6f7", background = "#1e1e2e", foreground = "#cdd6f4", secondary = "#a6adc8",
  selection = "#45475a", border = "#313244",
} }
```

### Paper

Always light, flat and square, whatever macOS uses.

![The Paper theme](/appearance/appearance-paper.png)

```lua
wm.config { appearance = {
  theme = "light", material = "none", radius = 4,
  accent = "#d20f39", background = "#fafafa", foreground = "#222222", secondary = "#6c6f85",
  selection = "#e6e9ef", border = "#d0d4dc",
} }
```

### Spotlight

The native blur and colors, rounder corners, a rounded font, no fades.

![The Spotlight theme](/appearance/appearance-spotlight.png)

```lua
wm.config { appearance = {
  radius = 16, font = "SF Pro Rounded", animation = 0,
} }
```

### Tokyo Night

Deep navy with a soft blue accent.

![The Tokyo Night theme](/appearance/appearance-tokyonight.png)

```lua
wm.config { appearance = {
  theme = "dark", material = "none", radius = 14,
  accent = "#7aa2f7", background = "#1a1b26", foreground = "#c0caf5", secondary = "#7982a9",
  selection = "#283457", border = "#292e42",
} }
```

### Rosé Pine

Dark plum with a dusty rose accent.

![The Rosé Pine theme](/appearance/appearance-rosepine.png)

```lua
wm.config { appearance = {
  theme = "dark", material = "none", radius = 14,
  accent = "#ebbcba", background = "#191724", foreground = "#e0def4", secondary = "#908caa",
  selection = "#403d52", border = "#26233a",
} }
```

### Nord

Cool slate with an icy teal accent and tighter corners.

![The Nord theme](/appearance/appearance-nord.png)

```lua
wm.config { appearance = {
  theme = "dark", material = "none", radius = 10,
  accent = "#88c0d0", background = "#2e3440", foreground = "#eceff4", secondary = "#9aa5b8",
  selection = "#434c5e", border = "#3b4252",
} }
```

### Gruvbox Dark

Warm charcoal with a golden accent.

![The Gruvbox Dark theme](/appearance/appearance-gruvbox.png)

```lua
wm.config { appearance = {
  theme = "dark", material = "none", radius = 8,
  accent = "#fabd2f", background = "#282828", foreground = "#ebdbb2", secondary = "#a89984",
  selection = "#504945", border = "#3c3836",
} }
```

