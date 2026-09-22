# `colors.toml` schema

Derived from the 22 `colors.toml` files in this directory and from how
`bin/omarchy-theme-color` reads them. Every theme folder ships exactly one
`colors.toml` at its root.

## File format

- Flat TOML: top-level `key = "value"` pairs only. No tables, no arrays, no
  comments in any shipped file.
- Keys are lowercase `snake_case`.
- Every value is a quoted string. Colors are 6-digit hex with a leading `#`,
  in either case (`"#1a1b26"`, `"#205EA6"`). No alpha, no shorthand.
- The loader reads the file line by line, so a value must sit on the same
  line as its key.
- Keys are grouped in a conventional order, separated by blank lines:
  mode, then semantic roles, then backgrounds, then foregrounds, then the
  named hues, then the bright hues. Order is not significant to the loader.

## Keys

### Required in every theme (22/22)

| Key | Type | Role |
|-----|------|------|
| `mode` | `"dark"` \| `"light"` | Which direction the neutral ramp runs. 17 themes are dark, 5 are light. |
| `accent` | hex | Primary highlight: focus rings, active borders, links, the brand color. Equals `blue` in 17 of 22 themes. |
| `selection` | hex | Text-selection background. A stop on the neutral ramp between `background` and `foreground`. |
| `muted` | hex | De-emphasized elements: comments, placeholders, dividers. Also serves as ANSI `color8`. |
| `background` | hex | Primary surface. |
| `dark_background` | hex | One step away from `background`, toward the ramp's dark end. |
| `darker_background` | hex | Two steps away from `background`, toward the ramp's dark end. |
| `lighter_background` | hex | One step from `background` toward `foreground`. Raised surfaces, hover states. |
| `foreground` | hex | Primary readable text. |
| `dark_foreground` | hex | Secondary text, one step from `foreground` back toward `background`. |
| `light_foreground` | hex | Text slightly stronger than `foreground`. |
| `bright_foreground` | hex | Strongest text. Also the cursor and the selection foreground. |
| `red` | hex | Named hue. Also the urgent/error role. |
| `yellow` | hex | Named hue. Warning. |
| `green` | hex | Named hue. Success. |
| `cyan` | hex | Named hue. |
| `blue` | hex | Named hue. Info. |
| `magenta` | hex | Named hue. |
| `bright_red` | hex | Brighter variant of `red`. |
| `bright_yellow` | hex | Brighter variant of `yellow`. |
| `bright_green` | hex | Brighter variant of `green`. |
| `bright_cyan` | hex | Brighter variant of `cyan`. |
| `bright_blue` | hex | Brighter variant of `blue`. |
| `bright_magenta` | hex | Brighter variant of `magenta`. |

### Optional, common (19/22)

| Key | Type | Fallback when absent |
|-----|------|----------------------|
| `orange` | hex | `yellow` |
| `brown` | hex | `orange` mixed 50% with black |

Omitted by `last-horizon`, `solitude`, and `white`. There are no
`bright_orange` or `bright_brown` keys in any theme.

### Optional, rare (2 to 3 themes)

| Key | Type | Fallback | Used by |
|-----|------|----------|---------|
| `hyprland_active_border` | gradient | `accent` | `hackerman`, `last-horizon`, `solitude` |
| `hyprland_inactive_border` | gradient | `rgba(595959aa)` | `last-horizon`, `solitude` |
| `active_border_color` | hex | `accent` | `last-horizon`, `lumon`, `solitude` |
| `active_tab_background` | hex | `accent` | `last-horizon`, `lumon`, `solitude` |

The two `hyprland_*` keys use a **gradient** grammar, not plain hex: one or
more space-separated stops, each `rgba(rrggbbaa)` or `rgb(rrggbb)` with no
`#`, optionally followed by an angle such as `45deg`.

```toml
hyprland_active_border = "rgba(26a269ee) rgba(2ec27eee) 45deg"
hyprland_inactive_border = "rgb(1e1e1e)"
```

Templates resolve them with `hypr_gradient`, `shell_gradient` and
`gradient_start`, each of which takes a fallback key. `active_border_color`
and `active_tab_background` are plain hex and are not read by any shipped
template, which uses `accent` for both roles.

## The neutral ramp

The eight neutral keys form one ordered ramp. Read in this order they go
from the surface toward the strongest text:

```
darker_background → dark_background → background → lighter_background
→ selection → muted → dark_foreground → foreground → light_foreground
→ bright_foreground
```

`mode` says which way that ramp runs in luminance:

- `dark`: `darker_background` is the darkest value, `bright_foreground` the
  lightest.
- `light`: `darker_background` is still further from `foreground` than
  `background`, but it is *lighter* only in name. In `flexoki-light`,
  `background` is `#FFFCF0` and `darker_background` is `#e5e2d8`, so the
  "darker" background is in fact a darker cream. The names describe position
  on the ramp relative to `background`, not absolute luminance.

Light themes commonly collapse the `bright_*` hues onto the base hues
(`flexoki-light` sets `bright_red = red`, and so on), and may set
`bright_foreground = foreground`.

## Derived and legacy names

Consumers see more names than the file defines. `omarchy-theme-color`
derives these; a theme should not set them.

| Derived name | Value |
|--------------|-------|
| `selection_background` | `selection` |
| `selection_foreground` | `bright_foreground` |
| `cursor` | `bright_foreground` |
| `purple`, `bright_purple` | aliases of `magenta`, `bright_magenta` |
| `color0` … `color15` | ANSI mapping: 0 background, 1 red, 2 green, 3 yellow, 4 blue, 5 magenta, 6 cyan, 7 foreground, 8 muted, 9 to 14 the `bright_*` hues in the same order, 15 `bright_foreground` |
| `bg`, `dark_bg`, `darker_bg`, `lighter_bg`, `fg`, `dark_fg`, `light_fg`, `bright_fg` | legacy short names for the neutral keys |
| `theme_type` | same as `mode` |

If `mode` is missing the loader infers it: `light` when the sum of
`background`'s RGB channels exceeds 382, else `dark`. Every shipped theme
sets it explicitly.

Missing neutrals are also derived (for example `dark_background` from
`background` mixed 25% with black, and each `bright_*` hue from its base
mixed 20% with white), but every shipped theme defines all of them.

## Minimal valid file

```toml
mode = "dark"

accent = "#7aa2f7"
selection = "#292e42"
muted = "#414868"

background = "#1a1b26"
dark_background = "#13141c"
darker_background = "#0e0e14"
lighter_background = "#24283b"

foreground = "#a9b1d6"
dark_foreground = "#565f89"
light_foreground = "#b4bee6"
bright_foreground = "#c0caf5"

red = "#f7768e"
yellow = "#e0af68"
orange = "#eb927b"
green = "#9ece6a"
cyan = "#449dab"
blue = "#7aa2f7"
magenta = "#ad8ee6"
brown = "#75493d"

bright_red = "#ff7a93"
bright_yellow = "#ff9e64"
bright_green = "#b9f27c"
bright_cyan = "#0db9d7"
bright_blue = "#7da6ff"
bright_magenta = "#bb9af7"
```

## Validation rules

1. `mode` is present and is exactly `"dark"` or `"light"`.
2. All 24 required keys are present.
3. Every hex value matches `^#[0-9a-fA-F]{6}$`.
4. `hyprland_active_border` and `hyprland_inactive_border`, if present,
   match `^(rgba?\([0-9a-fA-F]{6,8}\))( rgba?\([0-9a-fA-F]{6,8}\))*( -?\d+deg)?$`.
5. No unknown keys are needed for a valid theme, but unknown keys are
   tolerated: any key becomes available to templates as `{{ key }}`.
