defmodule Oma.Palette do
  @moduledoc """
  A validated, fully derived Omarchy palette.

  Any source (a `colors.toml`, a registry catalog entry, an `alacritty.toml`)
  becomes a raw string map first and then goes through `from_raw/2`, so every
  path yields the same palette for the same theme. Validation follows the
  registry's contract: nine required keys, everything else derived with the
  cascade from `bin/omarchy-theme-color`.

  `complete?` is true only when the author defined all 24 schema keys (the
  set every built-in theme ships), so an app can offer only fully specified
  palettes if it wants to.
  """

  alias Oma.Color
  alias Oma.Palette.Parser

  @schema ~w(accent selection muted background dark_background darker_background
    lighter_background foreground dark_foreground light_foreground bright_foreground
    red yellow green cyan blue magenta
    bright_red bright_yellow bright_green bright_cyan bright_blue bright_magenta)a

  @colors ~w(accent selection muted background dark_background darker_background
    lighter_background foreground dark_foreground light_foreground bright_foreground
    red yellow orange green cyan blue magenta brown
    bright_red bright_yellow bright_green bright_cyan bright_blue bright_magenta)a

  @required ~w(accent background foreground red yellow green cyan blue magenta)a

  @hues ~w(red yellow green cyan blue magenta)a

  # Legacy spellings `omarchy-theme-color` still accepts. Canonical wins.
  @short_names %{
    "background" => "bg",
    "dark_background" => "dark_bg",
    "darker_background" => "darker_bg",
    "lighter_background" => "lighter_bg",
    "foreground" => "fg",
    "dark_foreground" => "dark_fg",
    "light_foreground" => "light_fg",
    "bright_foreground" => "bright_fg"
  }

  @ansi %{
    "red" => "color1",
    "green" => "color2",
    "yellow" => "color3",
    "blue" => "color4",
    "magenta" => "color5",
    "cyan" => "color6",
    "bright_red" => "color9",
    "bright_green" => "color10",
    "bright_yellow" => "color11",
    "bright_blue" => "color12",
    "bright_magenta" => "color13",
    "bright_cyan" => "color14"
  }

  @legacy_keys Map.values(@short_names) ++
                 Enum.map(0..15, &"color#{&1}") ++
                 ~w(purple bright_purple selection_background selection_foreground cursor theme_type)

  @type tier :: :builtin | :community | :extra
  @type t :: %__MODULE__{}

  defstruct [:name, :tier, :mode, complete?: false, defined: [], warnings: [], extra: %{}] ++
              Enum.map(@colors, &{&1, nil})

  @doc "The 24 keys every built-in theme defines."
  def schema_keys, do: @schema

  @doc "The 26 colour fields on the struct (schema keys plus `orange` and `brown`)."
  def color_keys, do: @colors

  @doc "The nine keys a palette must define to load."
  def required_keys, do: @required

  @doc """
  Build a palette from a raw string map.

  Options: `:name` (required), `:tier` (default `:extra`), `:light_marker`
  (a `light.mode` file sat beside the source; used only when `mode` is
  undeclared).
  """
  @spec from_raw(%{String.t() => String.t()}, keyword) :: {:ok, t} | {:error, [term]}
  def from_raw(raw, opts) when is_map(raw) do
    name = Keyword.fetch!(opts, :name)
    tier = Keyword.get(opts, :tier, :extra)

    raw = Map.new(raw, fn {k, v} -> {String.downcase(to_string(k)), to_string(v)} end)
    {resolved, warnings} = raw |> alias_legacy() |> normalize_colors()

    errors =
      []
      |> check_name(name)
      |> check_required(resolved)
      |> check_mode(resolved)

    case errors do
      [] ->
        defined = Enum.filter(@schema, &Map.has_key?(resolved, Atom.to_string(&1)))
        mode = mode(resolved, Keyword.get(opts, :light_marker, false))
        derived = derive_map(resolved)

        palette =
          struct!(__MODULE__,
            name: name,
            tier: tier,
            mode: mode,
            complete?: length(defined) == length(@schema),
            defined: defined,
            warnings: Enum.reverse(warnings),
            extra: extras(raw)
          )

        {:ok,
         Enum.reduce(@colors, palette, &Map.put(&2, &1, Map.fetch!(derived, Atom.to_string(&1))))}

      errors ->
        {:error, Enum.reverse(errors)}
    end
  end

  @spec from_raw!(%{String.t() => String.t()}, keyword) :: t
  def from_raw!(raw, opts) do
    case from_raw(raw, opts) do
      {:ok, palette} ->
        palette

      {:error, errors} ->
        raise ArgumentError, "invalid palette #{inspect(opts[:name])}: #{inspect(errors)}"
    end
  end

  @doc "Parse `colors.toml` text and build a palette."
  @spec from_toml(String.t(), keyword) :: {:ok, t} | {:error, [term]}
  def from_toml(text, opts), do: text |> Parser.parse() |> from_raw(opts)

  @doc """
  Read a `colors.toml` from disk. The theme name defaults to the file's
  directory name for `<theme>/colors.toml` layouts and to the basename for
  `<theme>.toml`. A `light.mode` marker beside the file is honoured.
  """
  @spec from_file(Path.t(), keyword) :: {:ok, t} | {:error, [term]}
  def from_file(path, opts \\ []) do
    name =
      Keyword.get_lazy(opts, :name, fn ->
        case Path.basename(path) do
          "colors.toml" -> path |> Path.dirname() |> Path.basename()
          base -> Path.rootname(base)
        end
      end)

    marker = path |> Path.dirname() |> Path.join("light.mode") |> File.exists?()

    path
    |> File.read!()
    |> from_toml(Keyword.merge([name: name, light_marker: marker], opts))
  end

  @doc "The 26 colour fields as an atom-keyed map."
  @spec colors(t) :: %{atom => String.t()}
  def colors(%__MODULE__{} = p), do: Map.take(p, @colors)

  @doc """
  Every name a template can reference, as `omarchy-theme-color --all`
  would print it: canonical keys, legacy short names, `color0..15`,
  selection and cursor roles, `purple` aliases, `mode` and `theme_type`,
  plus any extra keys the source carried.
  """
  @spec resolved(t) :: %{String.t() => String.t()}
  def resolved(%__MODULE__{} = p) do
    c = colors(p)
    mode = Atom.to_string(p.mode)

    canonical = Map.new(c, fn {k, v} -> {Atom.to_string(k), v} end)
    short = Map.new(@short_names, fn {canon, short} -> {short, canonical[canon]} end)
    ansi = Map.new(@ansi, fn {canon, colour} -> {colour, canonical[canon]} end)

    p.extra
    |> Map.merge(canonical)
    |> Map.merge(short)
    |> Map.merge(ansi)
    |> Map.merge(%{
      "color0" => c.background,
      "color7" => c.foreground,
      "color8" => c.muted,
      "color15" => c.bright_foreground,
      "selection_background" => c.selection,
      "selection_foreground" => c.bright_foreground,
      "cursor" => c.bright_foreground,
      "purple" => c.magenta,
      "bright_purple" => c.bright_magenta,
      "mode" => mode,
      "theme_type" => mode
    })
  end

  # -- alias resolution -----------------------------------------------------

  # Mirrors resolve_theme_colors up to the point where shades are derived.
  defp alias_legacy(raw) do
    raw =
      Enum.reduce(@short_names, raw, fn {canon, short}, acc -> fallback(acc, canon, short) end)

    raw =
      raw
      |> fallback("background", "color0")
      |> fallback("foreground", "color7")
      |> then(&if(&1["background"], do: Map.put(&1, "color0", &1["background"]), else: &1))
      |> then(&if(&1["foreground"], do: Map.put(&1, "color7", &1["foreground"]), else: &1))

    raw = Enum.reduce(@ansi, raw, fn {canon, colour}, acc -> fallback(acc, canon, colour) end)

    raw
    |> fallback("magenta", "purple")
    |> fallback("bright_magenta", "bright_purple")
    |> fallback("mode", "theme_type")
  end

  defp fallback(map, key, from) do
    case {map[key], map[from]} do
      {nil, value} when is_binary(value) and value != "" -> Map.put(map, key, value)
      _ -> map
    end
  end

  # Normalise every colour-valued key we know about; drop unparsable
  # optional ones with a warning, keep bad required ones for check_required.
  defp normalize_colors(raw) do
    keys = Enum.map(@colors, &Atom.to_string/1) ++ (@legacy_keys -- ["theme_type"])

    Enum.reduce(keys, {raw, []}, fn key, {acc, warnings} ->
      case Map.fetch(acc, key) do
        :error ->
          {acc, warnings}

        {:ok, value} ->
          case Color.normalize(value) do
            {:ok, hex} ->
              {Map.put(acc, key, hex), warnings}

            :error ->
              if String.to_atom(key) in @required do
                {acc, warnings}
              else
                {Map.delete(acc, key), [{:dropped, key, value} | warnings]}
              end
          end
      end
    end)
  end

  # -- validation ------------------------------------------------------------

  defp check_name(errors, name) do
    if Oma.Slug.valid?(name), do: errors, else: [{:bad_name, name} | errors]
  end

  defp check_required(errors, resolved) do
    {missing, bad} =
      Enum.reduce(@required, {[], []}, fn key, {missing, bad} ->
        case Map.fetch(resolved, Atom.to_string(key)) do
          :error ->
            {[key | missing], bad}

          {:ok, value} ->
            if Color.valid_hex?(value), do: {missing, bad}, else: {missing, [{key, value} | bad]}
        end
      end)

    errors =
      if missing == [], do: errors, else: [{:missing_required, Enum.reverse(missing)} | errors]

    Enum.reduce(Enum.reverse(bad), errors, fn {k, v}, acc -> [{:bad_value, k, v} | acc] end)
  end

  defp check_mode(errors, resolved) do
    case resolved["mode"] do
      nil -> errors
      "dark" -> errors
      "light" -> errors
      other -> [{:bad_mode, other} | errors]
    end
  end

  defp mode(resolved, light_marker) do
    cond do
      resolved["mode"] == "dark" -> :dark
      resolved["mode"] == "light" -> :light
      light_marker -> :light
      true -> Color.infer_mode(resolved["background"])
    end
  end

  # -- derivation --------------------------------------------------------------

  # The remainder of resolve_theme_colors, in upstream order. Idempotent:
  # every step only fills a key that is still missing.
  defp derive_map(r) do
    r
    |> fallback("light_foreground", "color7")
    |> fallback("light_foreground", "foreground")
    |> fallback("bright_foreground", "color15")
    |> fallback("bright_foreground", "foreground")
    |> fallback("lighter_background", "color0")
    |> fallback("lighter_background", "background")
    |> fallback("dark_foreground", "color8")
    |> fallback("dark_foreground", "foreground")
    |> fallback("muted", "color8")
    |> fallback("muted", "dark_foreground")
    |> fallback("selection", "selection_background")
    |> fallback("selection", "color8")
    |> fallback("selection", "color0")
    |> fallback("selection", "background")
    |> fallback("orange", "yellow")
    |> put_new_lazy("brown", &Color.mix(&1["orange"], "#000000", 0.5))
    |> put_new_lazy("dark_background", &Color.mix(&1["background"], "#000000", 0.25))
    |> put_new_lazy("darker_background", &Color.mix(&1["background"], "#000000", 0.5))
    |> then(fn acc ->
      Enum.reduce(@hues, acc, fn hue, m ->
        base = Atom.to_string(hue)
        put_new_lazy(m, "bright_" <> base, &Color.mix(&1[base], "#ffffff", 0.2))
      end)
    end)
  end

  defp put_new_lazy(map, key, fun) do
    if Map.has_key?(map, key), do: map, else: Map.put(map, key, fun.(map))
  end

  # Keys that are neither palette colours nor legacy aliases nor mode.
  defp extras(raw) do
    known = Enum.map(@colors, &Atom.to_string/1) ++ @legacy_keys ++ ["mode"]
    raw |> Map.drop(known) |> Map.new()
  end
end
