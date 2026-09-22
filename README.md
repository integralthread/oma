# Oma

Omarchy palettes for Elixir and Phoenix. Oma vendors the 22 built-in
Omarchy themes and every community theme listed in the theme registry,
validates and derives each palette the way the desktop does, and renders
the CSS a Phoenix 1.8 app needs to switch between them with a `data-theme`
attribute.

## Use in a Phoenix app

```elixir
# mix.exs
{:oma, path: "../oma"}
```

```sh
mix oma.gen --out assets/css/themes --semantic --tailwind --daisyui --complete-only
```

```css
/* assets/css/app.css */
@import "./themes/index.css";
```

Then set `data-theme="tokyo-night"` on `<html>`. `Oma.Themes` gives the
list for a picker, `Oma.Themes.meta/1` the registry metadata (repository,
hue, preview thumbnail), and `Oma.Palette` the raw values for anything
that cannot see CSS variables, such as email.

```elixir
Oma.Themes.names()                 # ["01", "aetheria", ..., "white"]
Oma.Themes.complete()              # palettes whose author defined all 24 keys
Oma.Themes.get!("tokyo-night").accent   # "#7aa2f7"
Oma.CSS.variables(Oma.Themes.get!("nord"))
```

The generated `priv/static/themes/` holds the built-ins as ready CSS for
consumers who do not want to run the generator.

## Maintain the vendored themes

```sh
mise bootstrap repos apply          # clone ./omarchy (once)
mix oma.sync                        # refresh priv/themes from the checkout and the catalog
mix oma.add <git-url>               # vendor an unlisted theme into priv/themes/extra
mix oma.check                       # WCAG contrast report; fails on new failures
mix oma.gen --out priv/static/themes --tier builtin
```

`priv/themes/SOURCES` records the omarchy commit and catalog timestamp a
sync came from. `priv/themes/index.json` is the picker metadata, one line
per theme. `priv/themes/contrast_exceptions.txt` lists known contrast
failures.

## Notes

- `notes/SCHEMA.md` the `colors.toml` contract as the built-ins ship it
- `notes/SOURCES.md` how Omarchy distributes themes and where the data comes from
- `notes/PHX.md` the CSS contract this library renders
- `notes/PLAN.md` the build plan and decisions
- `notes/CONTRAST.md` the generated contrast report
