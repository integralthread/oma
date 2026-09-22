defmodule Mix.Tasks.Oma.Gen do
  @shortdoc "Generate theme CSS files from the vendored palettes"

  @moduledoc """
  Writes one CSS file per theme plus `index.css` into a directory the
  generator owns:

      mix oma.gen --out assets/css/themes [options]

  Options:

    * `--out DIR` (required) target directory; `.css` files in it that this
      run did not produce are removed
    * `--tier builtin,community,extra` tiers to include (default all)
    * `--complete-only` only palettes whose author defined all 24 keys
    * `--theme NAME` include only this theme (repeatable)
    * `--semantic` also write `semantic.css` (the role layer) and import it
    * `--tailwind` also write `tailwind.css` (the `@theme` block) and import it
    * `--daisyui` append a daisyUI theme block to every theme file
    * `--daisyui-plugin PATH` plugin path in that block
      (default `../vendor/daisyui-theme`)

  In a Phoenix 1.8 app, `@import "./themes/index.css";` in `app.css` is
  then all that is needed.
  """

  use Mix.Task

  alias Oma.CSS
  alias Oma.Themes

  @switches [
    out: :string,
    tier: :string,
    complete_only: :boolean,
    theme: :keep,
    semantic: :boolean,
    tailwind: :boolean,
    daisyui: :boolean,
    daisyui_plugin: :string
  ]

  @impl true
  def run(args) do
    {opts, _, invalid} = OptionParser.parse(args, strict: @switches)
    if invalid != [], do: Mix.raise("unknown options: #{inspect(invalid)}")
    out = opts[:out] || Mix.raise("--out DIR is required")

    palettes = Themes.select(select_opts(opts))
    if palettes == [], do: Mix.raise("no themes selected")

    File.mkdir_p!(out)

    css_opts =
      [daisyui: Keyword.get(opts, :daisyui, false)] ++
        if(opts[:daisyui_plugin], do: [plugin: opts[:daisyui_plugin]], else: [])

    written =
      for p <- palettes do
        File.write!(Path.join(out, p.name <> ".css"), CSS.theme_file(p, css_opts))
        p.name <> ".css"
      end

    shared =
      Enum.flat_map([semantic: &CSS.semantic_layer/0, tailwind: &CSS.tailwind_theme/0], fn {name,
                                                                                            render} ->
        if Keyword.get(opts, name, false) do
          File.write!(Path.join(out, "#{name}.css"), render.())
          ["#{name}.css"]
        else
          []
        end
      end)

    imports = Enum.map(shared, &Path.rootname/1) ++ Enum.map(palettes, & &1.name)
    File.write!(Path.join(out, "index.css"), CSS.index(imports))

    keep = written ++ shared ++ ["index.css"]

    out
    |> Path.join("*.css")
    |> Path.wildcard()
    |> Enum.reject(&(Path.basename(&1) in keep))
    |> Enum.each(&File.rm!/1)

    Mix.shell().info(
      "generated #{length(palettes)} themes into #{out}" <>
        if(shared == [], do: "", else: " (+ #{Enum.join(shared, ", ")})")
    )
  end

  @doc false
  def select_opts(opts) do
    tiers =
      case opts[:tier] do
        nil -> [:builtin, :community, :extra]
        list -> list |> String.split(",", trim: true) |> Enum.map(&tier!/1)
      end

    names = Keyword.get_values(opts, :theme)

    [tiers: tiers, complete_only: Keyword.get(opts, :complete_only, false)] ++
      if(names == [], do: [], else: [names: names])
  end

  defp tier!(name) when name in ~w(builtin community extra), do: String.to_atom(name)

  defp tier!(name),
    do: Mix.raise("unknown tier #{inspect(name)}; expected builtin, community or extra")
end
