defmodule Oma.CSS do
  @moduledoc """
  Pure CSS renderers. Every function returns a string; nothing here touches
  the file system. `mix oma.gen` assembles files from these pieces, and a
  Phoenix app can call them directly to inline a theme.

  The contract: one custom property per schema key scoped by `data-theme`
  on `<html>` (underscores become hyphens, `mode` becomes `color-scheme`),
  a semantic role layer defined once per app, a Tailwind v4 `@theme` block
  that exposes the roles as utilities, and an optional daisyUI theme block
  per palette.
  """

  alias Oma.Color
  alias Oma.Palette

  @groups [
    [:accent, :selection, :muted],
    [:background, :dark_background, :darker_background, :lighter_background],
    [:foreground, :dark_foreground, :light_foreground, :bright_foreground],
    [:red, :yellow, :orange, :green, :cyan, :blue, :magenta, :brown],
    [:bright_red, :bright_yellow, :bright_green, :bright_cyan, :bright_blue, :bright_magenta]
  ]

  @doc """
  The `:root[data-theme="<name>"]` block: `color-scheme` from `mode`, then
  one `--<key>` per colour with underscores turned into hyphens, and finally
  `--text-on-accent`, the ramp end that contrasts best with `accent` (see
  `content_color/2`), so button text stays legible on themes where
  `background` on `accent` fails contrast. Desktop-only keys (`hyprland_*`,
  `active_*`) are not emitted.

  Option `:selector` overrides the selector.
  """
  @spec variables(Palette.t(), keyword) :: String.t()
  def variables(%Palette{} = p, opts \\ []) do
    selector = Keyword.get(opts, :selector, ~s(:root[data-theme="#{p.name}"]))

    body =
      Enum.map_join(@groups, "\n\n", fn group ->
        Enum.map_join(group, "\n", fn key -> "  --#{var(key)}: #{Map.fetch!(p, key)};" end)
      end)

    """
    #{selector} {
      color-scheme: #{p.mode};

    #{body}

      --text-on-accent: #{content_color(p, p.accent)};
    }
    """
  end

  @doc """
  The semantic role layer, identical for every theme, pointing web roles at
  schema roles. Include once in `app.css`.
  """
  @spec semantic_layer() :: String.t()
  def semantic_layer do
    """
    :root {
      --surface: var(--background);
      --surface-sunken: var(--dark-background);
      --surface-deepest: var(--darker-background);
      --surface-raised: var(--lighter-background);

      --text: var(--foreground);
      --text-secondary: var(--dark-foreground);
      --text-strong: var(--light-foreground);
      --text-strongest: var(--bright-foreground);

      --border: var(--selection);
      --divider: var(--muted);
      --placeholder: var(--muted);

      --brand: var(--accent);
      --link: var(--accent);
      --focus-ring: var(--accent);

      --error: var(--red);
      --warning: var(--yellow);
      --success: var(--green);
      --info: var(--blue);
    }
    """
  end

  @doc """
  A Tailwind v4 `@theme` block registering the semantic roles and raw hues
  as colour utilities (`bg-surface`, `text-text-secondary`, `border-border`,
  `text-red`). Values are `var()` references, so switching `data-theme`
  repaints without a rebuild.
  """
  @spec tailwind_theme() :: String.t()
  def tailwind_theme do
    """
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
      --color-orange: var(--orange);
      --color-green: var(--green);
      --color-cyan: var(--cyan);
      --color-blue: var(--blue);
      --color-magenta: var(--magenta);
      --color-brown: var(--brown);
    }
    """
  end

  @doc """
  A daisyUI 5 theme block for the palette.

  `base-200` is the raised surface in a dark theme and `dark_background` in
  a light one, since daisyUI expects it one step more recessed than
  `base-100`. Every `-content` colour is whichever end of the neutral ramp
  contrasts better with its base (see `content_color/2`).

  Options: `:plugin` (default `"../vendor/daisyui-theme"`, the Phoenix 1.8
  vendored path), `:default` and `:prefersdark` (both default `false`).
  """
  @spec daisyui(Palette.t(), keyword) :: String.t()
  def daisyui(%Palette{} = p, opts \\ []) do
    plugin = Keyword.get(opts, :plugin, "../vendor/daisyui-theme")
    base_200 = if p.mode == :dark, do: p.lighter_background, else: p.dark_background

    colored = [
      primary: p.accent,
      secondary: p.magenta,
      accent: p.cyan,
      neutral: p.darker_background,
      info: p.blue,
      success: p.green,
      warning: p.yellow,
      error: p.red
    ]

    lines =
      [
        "--color-base-100: #{p.background};",
        "--color-base-200: #{base_200};",
        "--color-base-300: #{p.selection};",
        "--color-base-content: #{p.foreground};"
      ] ++
        Enum.flat_map(colored, fn {role, hex} ->
          ["--color-#{role}: #{hex};", "--color-#{role}-content: #{content_color(p, hex)};"]
        end)

    """
    @plugin "#{plugin}" {
      name: "#{p.name}";
      default: #{Keyword.get(opts, :default, false)};
      prefersdark: #{Keyword.get(opts, :prefersdark, false)};
      color-scheme: "#{p.mode}";
    #{Enum.map_join(lines, "\n", &("  " <> &1))}
    }
    """
  end

  @doc """
  Text colour for content drawn on `base`: the palette's `darker_background`
  or `bright_foreground`, whichever has the higher WCAG contrast ratio with
  `base`. In a dark theme that is the darkest and lightest stop of the ramp;
  in a light theme the same two keys are the lightest and darkest.
  """
  @spec content_color(Palette.t(), String.t()) :: String.t()
  def content_color(%Palette{} = p, base) do
    Enum.max_by([p.darker_background, p.bright_foreground], &Color.contrast_ratio(&1, base))
  end

  @doc ~S"""
  `@import` lines for a list of theme names, one per line.

      iex> Oma.CSS.index(["nord", "tokyo-night"])
      "@import \"./nord.css\";\n@import \"./tokyo-night.css\";\n"
  """
  @spec index([String.t()], keyword) :: String.t()
  def index(names, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "./")
    Enum.map_join(names, "", &~s|@import "#{prefix}#{&1}.css";\n|)
  end

  @doc "The file `mix oma.gen` writes per theme: variables, plus the daisyUI block when `daisyui: true`."
  @spec theme_file(Palette.t(), keyword) :: String.t()
  def theme_file(%Palette{} = p, opts \\ []) do
    if Keyword.get(opts, :daisyui, false) do
      variables(p) <> "\n" <> daisyui(p, opts)
    else
      variables(p)
    end
  end

  defp var(key), do: key |> Atom.to_string() |> String.replace("_", "-")
end
