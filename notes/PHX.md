# Bringing Omarchy themes to a Phoenix app

This guide shows how to take the palette contract in `SCHEMA.md` and apply
it to an Elixir/Phoenix web app, so that any of the 22 theme folders in
this directory (or a new one that follows the schema) can skin the app.

It assumes Phoenix 1.8 defaults: Tailwind v4 with CSS-first config,
daisyUI vendored under `assets/vendor`, and the `data-theme` toggle that
ships in `root.html.heex`. Older setups are covered in notes along the way.

## 1. The idea in one paragraph

A `colors.toml` is a flat list of about 30 named hex colors plus a `mode`.
Its power is not the hues, it is the *roles*: a ten-stop neutral ramp from
`darker_background` to `bright_foreground`, one `accent`, a `selection`
and `muted` stop, and six named hues that double as status colors. On the
web those roles map one-to-one onto CSS custom properties. Once every
component in the app reads a role instead of a literal color, swapping the
whole look is a matter of swapping which block of variables is active.

## 2. Decide the CSS contract

Define one custom property per schema key, scoped by `data-theme` on
`<html>`. Keep the schema names so the mapping stays obvious:

```css
/* assets/css/themes/tokyo-night.css (generated, see section 4) */
:root[data-theme="tokyo-night"] {
  color-scheme: dark;

  --accent: #7aa2f7;
  --selection: #292e42;
  --muted: #414868;

  --background: #1a1b26;
  --dark-background: #13141c;
  --darker-background: #0e0e14;
  --lighter-background: #24283b;

  --foreground: #a9b1d6;
  --dark-foreground: #565f89;
  --light-foreground: #b4bee6;
  --bright-foreground: #c0caf5;

  --red: #f7768e;     --bright-red: #ff7a93;
  --yellow: #e0af68;  --bright-yellow: #ff9e64;
  --green: #9ece6a;   --bright-green: #b9f27c;
  --cyan: #449dab;    --bright-cyan: #0db9d7;
  --blue: #7aa2f7;    --bright-blue: #7da6ff;
  --magenta: #ad8ee6; --bright-magenta: #bb9af7;
  --orange: #eb927b;
  --brown: #75493d;
}
```

Two conventions to hold onto:

- `mode` becomes `color-scheme`. That single line makes native form
  controls, scrollbars and the default focus ring follow the theme.
- Underscores become hyphens. Everything else keeps the schema name.

### Semantic layer on top

Components should not reach for `--red` directly. Add a second, smaller
layer that names web roles and points them at schema roles. This layer is
the same for every theme, so it lives once in `app.css`:

```css
:root {
  --surface:          var(--background);
  --surface-sunken:   var(--dark-background);
  --surface-deepest:  var(--darker-background);
  --surface-raised:   var(--lighter-background);

  --text:             var(--foreground);
  --text-secondary:   var(--dark-foreground);
  --text-strong:      var(--light-foreground);
  --text-strongest:   var(--bright-foreground);

  --border:           var(--selection);
  --divider:          var(--muted);
  --placeholder:      var(--muted);

  --brand:            var(--accent);
  --link:             var(--accent);
  --focus-ring:       var(--accent);

  --error:            var(--red);
  --warning:          var(--yellow);
  --success:          var(--green);
  --info:             var(--blue);
}
```

The neutral ramp gives you the surface hierarchy for free. Read from the
schema: `darker_background` is the page behind a modal, `dark_background`
is a sidebar or sunken well, `background` is the page, `lighter_background`
is a card or hover state. `selection` sits between surfaces and text, so
it works as a border color that is visible on any surface.

## 3. Tailwind v4: expose the roles as utilities

Phoenix 1.8 configures Tailwind from `assets/css/app.css`. Register the
semantic layer in `@theme` so `bg-surface`, `text-text-secondary`,
`border-border` and friends exist as normal utility classes:

```css
@import "tailwindcss" source(none);
@source "../css";
@source "../js";
@source "../../lib/my_app_web";

@import "./themes/index.css"; /* every generated theme file */

@theme {
  --color-surface: var(--surface);
  --color-surface-sunken: var(--surface-sunken);
  --color-surface-deepest: var(--surface-deepest);
  --color-surface-raised: var(--surface-raised);

  --color-text: var(--text);
  --color-text-secondary: var(--text-secondary);
  --color-text-strong: var(--text-strong);
  --color-text-strongest: var(--text-strongest);

  --color-border: var(--border);
  --color-divider: var(--divider);
  --color-brand: var(--brand);
  --color-link: var(--link);

  --color-error: var(--error);
  --color-warning: var(--warning);
  --color-success: var(--success);
  --color-info: var(--info);

  /* raw hues, for charts and syntax highlighting */
  --color-red: var(--red);
  --color-yellow: var(--yellow);
  --color-green: var(--green);
  --color-cyan: var(--cyan);
  --color-blue: var(--blue);
  --color-magenta: var(--magenta);
  --color-orange: var(--orange);
  --color-brown: var(--brown);
}
```

Because the `@theme` values are `var()` references rather than literals,
Tailwind emits utilities that resolve at runtime. Changing `data-theme`
repaints the page with no rebuild.

Opacity modifiers such as `bg-brand/20` need the underlying color to be
in a form Tailwind can mix. Hex works with `color-mix()` in modern
browsers, which Tailwind v4 uses, so nothing extra is required.

**Tailwind v3 (Phoenix 1.7):** put the same mapping under
`theme.extend.colors` in `tailwind.config.js`, using the
`"rgb(var(--x) / <alpha-value>)"` idiom, and have the generator emit
space-separated RGB channels instead of hex.

### daisyUI, if you keep it

The Phoenix 1.8 generator ships daisyUI with a `light` and `dark` theme
defined via `@plugin "../vendor/daisyui-theme"`. To make an Omarchy
theme drive daisyUI components too, emit a plugin block per theme with
this mapping:

| daisyUI variable | Schema key |
|------------------|------------|
| `--color-base-100` | `background` |
| `--color-base-200` | `lighter_background` (dark mode) or `dark_background` (light mode) |
| `--color-base-300` | `selection` |
| `--color-base-content` | `foreground` |
| `--color-primary` | `accent` |
| `--color-primary-content` | `background` |
| `--color-secondary` | `magenta` |
| `--color-accent` | `cyan` |
| `--color-neutral` | `darker_background` |
| `--color-neutral-content` | `bright_foreground` |
| `--color-info` | `blue` |
| `--color-success` | `green` |
| `--color-warning` | `yellow` |
| `--color-error` | `red` |

The `base-200` rule deserves a note. daisyUI expects `base-200` to be
"one step more recessed" than `base-100`. In a dark theme the raised
surface (`lighter_background`) reads well there; in a light theme the
schema's `dark_background` is the slightly darker cream that plays the
same role. This is exactly the point `SCHEMA.md` makes about the ramp
names describing position, not luminance.

For the `-content` (text-on-color) variables, pick `darker_background`
for dark themes and `bright_foreground` for light themes when the base
hue is bright, and the reverse when it is dark. The generator below
computes this from luminance rather than hard-coding it.

## 4. Generate the CSS from `colors.toml`

Do not hand-copy palettes. Keep the theme folders as the source of truth
and generate the CSS with a Mix task. The files are flat TOML, so a
dedicated parser is optional, but the `toml` Hex package handles it in
one call and tolerates future keys.

```elixir
# mix.exs
{:toml, "~> 0.7", only: :dev, runtime: false}
```

```elixir
# lib/mix/tasks/themes.gen.ex
defmodule Mix.Tasks.Themes.Gen do
  @shortdoc "Generate assets/css/themes/*.css from Omarchy colors.toml files"
  use Mix.Task

  @required ~w(mode accent selection muted background dark_background
    darker_background lighter_background foreground dark_foreground
    light_foreground bright_foreground red yellow green cyan blue magenta
    bright_red bright_yellow bright_green bright_cyan bright_blue bright_magenta)

  @hex ~r/^#[0-9a-fA-F]{6}$/

  @impl true
  def run([source_dir]) do
    out = Path.join(File.cwd!(), "assets/css/themes")
    File.mkdir_p!(out)

    names =
      source_dir
      |> Path.join("*/colors.toml")
      |> Path.wildcard()
      |> Enum.map(fn path ->
        name = path |> Path.dirname() |> Path.basename()
        colors = path |> File.read!() |> Toml.decode!() |> validate!(name) |> derive()
        File.write!(Path.join(out, "#{name}.css"), render(name, colors))
        name
      end)

    index = Enum.map_join(names, "\n", &~s|@import "./#{&1}.css";|)
    File.write!(Path.join(out, "index.css"), index <> "\n")
    Mix.shell().info("generated #{length(names)} themes")
  end

  defp validate!(colors, name) do
    missing = @required -- Map.keys(colors)
    missing == [] || Mix.raise("#{name}: missing keys #{inspect(missing)}")

    colors["mode"] in ["dark", "light"] ||
      Mix.raise("#{name}: mode must be dark or light")

    for {k, v} <- colors, k != "mode", not String.starts_with?(k, "hyprland_"),
        not Regex.match?(@hex, v) do
      Mix.raise("#{name}: #{k} is not 6-digit hex: #{v}")
    end

    colors
  end

  # Mirror the fallbacks in bin/omarchy-theme-color.
  defp derive(colors) do
    colors
    |> Map.put_new_lazy("orange", fn -> colors["yellow"] end)
    |> then(&Map.put_new_lazy(&1, "brown", fn -> mix(&1["orange"], "#000000", 0.5) end))
  end

  defp render(name, colors) do
    vars =
      colors
      |> Map.drop(["mode"])
      |> Enum.reject(fn {k, _} -> String.starts_with?(k, "hyprland_") end)
      |> Enum.sort()
      |> Enum.map_join("\n", fn {k, v} -> "  --#{String.replace(k, "_", "-")}: #{v};" end)

    """
    :root[data-theme="#{name}"] {
      color-scheme: #{colors["mode"]};
    #{vars}
    }
    """
  end

  defp mix(a, b, weight) do
    {ar, ag, ab} = rgb(a)
    {br, bg, bb} = rgb(b)
    ch = fn x, y -> round(x * (1 - weight) + y * weight) end
    "#" <> Base.encode16(<<ch.(ar, br), ch.(ag, bg), ch.(ab, bb)>>, case: :lower)
  end

  defp rgb("#" <> hex) do
    <<r, g, b>> = Base.decode16!(hex, case: :mixed)
    {r, g, b}
  end
end
```

Run it against a checkout of this repo:

```sh
mix themes.gen ../omarchy/themes
```

Commit the generated `assets/css/themes/` directory. It is small, it
makes builds reproducible, and a diff on regeneration shows you exactly
what an upstream palette change did. If you would rather vendor the
sources, copy the `colors.toml` files into `priv/themes/<name>/` and point
the task there.

Add the daisyUI block to `render/2` if you use daisyUI, following the
table in section 3. The luminance test for `-content` colors is the same
one the schema describes for inferring `mode`: sum the RGB channels and
compare with 382.

## 5. Switching themes at runtime

Phoenix 1.8's `root.html.heex` already sets `data-theme` on `<html>` from
`localStorage`, and the `theme_toggle` component in `layouts.ex`
dispatches a `phx:set-theme` event with a theme name. Extend it rather
than replace it.

### Make the list of themes available to templates

```elixir
# lib/my_app_web/themes.ex
defmodule MyAppWeb.Themes do
  @themes "assets/css/themes/*.css"
          |> Path.wildcard()
          |> Enum.map(&Path.basename(&1, ".css"))
          |> List.delete("index")
          |> Enum.sort()

  @default "tokyo-night"

  def all, do: @themes
  def default, do: @default
  def valid?(name), do: name in @themes
end
```

Reading the directory at compile time keeps the list in sync with what
the generator produced with no runtime file access.

### A picker component

```elixir
attr :current, :string, required: true

def theme_picker(assigns) do
  assigns = assign(assigns, :themes, MyAppWeb.Themes.all())

  ~H"""
  <select
    class="bg-surface-raised text-text border-border rounded px-2 py-1"
    phx-change="set-theme"
    name="theme"
  >
    <option :for={t <- @themes} value={t} selected={t == @current}>{t}</option>
  </select>
  """
end
```

### Persist the choice per user

`localStorage` alone is fine for anonymous visitors. For signed-in users
store the theme on the account so it follows them between devices, and
render it into the first HTML response so there is no flash of the wrong
theme.

1. Add a `theme` column to users, validated against `MyAppWeb.Themes.valid?/1`.
2. In a plug that runs after `fetch_current_scope_for_user`, assign
   `:theme` from the user, falling back to the session, then to the
   default.
3. In `root.html.heex`, render it on the element:

```heex
<html lang="en" data-theme={assigns[:theme] || MyAppWeb.Themes.default()}>
```

4. Keep the inline `setTheme` script, but let the server value win when
   the user is signed in. The simplest change is to only read
   `localStorage` when `<html>` has no `data-theme` attribute already.

5. Handle the LiveView event by saving and then pushing the change to the
   client so the current page repaints without a reload:

```elixir
def handle_event("set-theme", %{"theme" => theme}, socket) do
  with true <- MyAppWeb.Themes.valid?(theme),
       {:ok, user} <- Accounts.update_theme(socket.assigns.current_scope.user, theme) do
    {:noreply,
     socket
     |> assign(:theme, user.theme)
     |> push_event("set-theme", %{theme: user.theme})}
  else
    _ -> {:noreply, put_flash(socket, :error, "Unknown theme")}
  end
end
```

```js
// assets/js/app.js
window.addEventListener("phx:set-theme", (e) => {
  document.documentElement.setAttribute("data-theme", e.detail.theme)
  localStorage.setItem("phx:theme", e.detail.theme)
})
```

### Respecting light and dark preference

Because each theme carries its own `mode`, "follow the system" means
choosing between two named themes rather than flipping a class. Offer a
light and a dark favourite and pick between them with a media query:

```js
const prefersDark = matchMedia("(prefers-color-scheme: dark)")
const pick = () => prefersDark.matches ? "tokyo-night" : "flexoki-light"
```

The five light themes at the time of writing are `catppuccin-latte`,
`flexoki-light`, `lupine`, `rose-pine` and `white`. Check `mode` in the
generated CSS rather than trusting the name: `rose-pine` and `lupine`
are light here even though other ports of those palettes are dark, and
`lumon` and `retro-82` are dark despite sounding pale.

## 6. Using the palette beyond CSS

**Charts and graphs.** The six named hues are the categorical palette.
Read them from the DOM in a hook rather than duplicating them in JS:

```js
const css = getComputedStyle(document.documentElement)
const series = ["red", "yellow", "green", "cyan", "blue", "magenta"]
  .map((h) => css.getPropertyValue(`--${h}`).trim())
```

Re-run that when `data-theme` changes; a `MutationObserver` on the
`<html>` attribute is enough.

**Emails and PDFs.** These cannot see CSS variables. Load the same
`colors.toml` in Elixir at compile time and interpolate literals. A
module attribute holding the parsed map for the default theme is enough
for most apps.

**Syntax highlighting.** Map `foreground` to plain text, `muted` to
comments, `dark_foreground` to punctuation, then the hues by token class.
Every Omarchy theme ships a `neovim.lua`; if one already exists for the
theme you are porting, borrow its highlight groups for the mapping.

**Favicons and Open Graph images.** Generate them per theme from
`accent` on `background`. Both are stable across the ramp and always
contrast.

## 7. Contrast checks in the test suite

The schema guarantees shape, not legibility. Add a test that loads each
generated theme and asserts the pairs you actually rely on:

| Pair | Minimum ratio |
|------|---------------|
| `foreground` on `background` | 4.5 |
| `dark_foreground` on `background` | 3.0 |
| `foreground` on `lighter_background` | 4.5 |
| `background` on `accent` (button text) | 3.0 |
| `red`, `green`, `yellow`, `blue` on `background` | 3.0 |

A WCAG relative-luminance function is about ten lines of Elixir. Run the
test against all themes so a new upstream theme that fails contrast shows
up in CI, and add a per-theme `--text-on-accent` override in the
generator for themes where the default choice fails.

## 8. Checklist for a new theme

1. Write `colors.toml` following the schema. The minimal file in
   `SCHEMA.md` is a complete template.
2. Run `mix themes.gen` and check the new file in `assets/css/themes/`.
3. Run the contrast test.
4. Add the name to your "follow system" light or dark pick if you want it
   selectable there.
5. Open the app, switch to the theme, and look at a form with validation
   errors, a table with hover rows, a modal over the page, and a code
   block. Those four views exercise every stop on the ramp.

## Mapping reference

Quick lookup from web concern to schema key.

| Web concern | Schema key |
|-------------|------------|
| Page background | `background` |
| Sidebar, table header, sunken input | `dark_background` |
| Backdrop behind modals, code blocks | `darker_background` |
| Cards, hover rows, dropdown menus | `lighter_background` |
| Borders, table dividers | `selection` |
| Placeholder text, disabled text, hairlines | `muted` |
| Body text | `foreground` |
| Secondary text, captions, timestamps | `dark_foreground` |
| Headings | `light_foreground` |
| Page title, text on selected rows | `bright_foreground` |
| Links, focus ring, primary button | `accent` |
| Text selection highlight | `selection` with `bright_foreground` |
| Error, destructive button | `red` |
| Warning banner | `yellow` |
| Success toast | `green` |
| Info banner | `blue` |
| Tag and badge colors, chart series | the six hues and their `bright_*` variants |
