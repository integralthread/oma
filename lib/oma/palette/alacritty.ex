defmodule Oma.Palette.Alacritty do
  @moduledoc """
  Raw palette map from a legacy `alacritty.toml`, for themes that predate
  `colors.toml`.

  Mirrors `paletteFromAlacritty` in the theme registry so a palette read
  from a repository here matches the catalog entry for the same theme.
  The upstream shell converter emits `color0..15`; the registry maps those
  straight to semantic names, and `Oma.Palette` accepts either spelling.
  """

  @doc "Parse alacritty TOML text into a raw `colors.toml`-style map."
  @spec parse(String.t()) :: %{String.t() => String.t()}
  def parse(text) when is_binary(text) do
    colors = tables(text)
    primary = Map.get(colors, "primary", %{})
    normal = Map.get(colors, "normal", %{})
    bright = Map.get(colors, "bright", %{})
    selection = Map.get(colors, "selection", %{})

    %{}
    |> put("background", primary["background"])
    |> put("foreground", primary["foreground"])
    |> put("selection", selection["background"])
    |> put_hues(normal, bright)
    |> put("dark_background", normal["black"])
    |> put("light_foreground", normal["white"])
    |> put("dark_foreground", bright["black"])
    |> put("bright_foreground", bright["white"])
    |> then(fn raw ->
      if Map.has_key?(raw, "blue") and not Map.has_key?(raw, "accent"),
        do: Map.put(raw, "accent", raw["blue"]),
        else: raw
    end)
  end

  defp put_hues(raw, normal, bright) do
    Enum.reduce(~w(red green yellow blue magenta cyan), raw, fn name, acc ->
      acc |> put(name, normal[name]) |> put("bright_" <> name, bright[name])
    end)
  end

  defp put(raw, _key, nil), do: raw

  defp put(raw, key, value) do
    case Oma.Color.normalize(value) do
      {:ok, hex} -> Map.put(raw, key, hex)
      :error -> raw
    end
  end

  # Collect `[colors.<table>]` sections and dotted `<table>.<key>` entries
  # under `[colors]` into %{"primary" => %{"background" => ...}, ...}.
  # Section form wins over dotted form; first occurrence of a key wins.
  defp tables(text) do
    {_section, direct, dotted} =
      text
      |> String.split(["\n", "\r\n"])
      |> Enum.reduce({nil, %{}, %{}}, fn line, {section, direct, dotted} ->
        trimmed = String.trim(line)

        case Regex.run(~r/^\[([^\]]*)\]\s*$/, trimmed) do
          [_, header] ->
            {String.trim(header), direct, dotted}

          nil ->
            entry(section, trimmed, direct, dotted)
        end
      end)

    Map.merge(dotted, direct, fn _table, d, s -> Map.merge(d, s) end)
  end

  defp entry(nil, _line, direct, dotted), do: {nil, direct, dotted}

  defp entry(section, line, direct, dotted) do
    with [raw_key, raw_value] <- String.split(line, "=", parts: 2),
         key when key != "" <- String.trim(raw_key),
         false <- String.starts_with?(key, "#"),
         {:ok, hex} <- hex_value(raw_value) do
      case {section, String.split(key, ".", parts: 2)} do
        {"colors", [table, name]} ->
          {section, direct, put_first(dotted, table, name, hex)}

        {"colors." <> table, [name]} ->
          {section, put_first(direct, table, name, hex), dotted}

        _ ->
          {section, direct, dotted}
      end
    else
      _ -> {section, direct, dotted}
    end
  end

  defp put_first(tables, table, name, hex) do
    Map.update(tables, table, %{name => hex}, &Map.put_new(&1, name, hex))
  end

  # A lone hex colour, optionally quoted and `0x`/`#` prefixed, with an
  # optional trailing comment. Keywords like "CellForeground" are dropped.
  defp hex_value(raw) do
    value = raw |> String.trim() |> String.replace(~r/\s+#.*$/, "")
    unquoted = String.replace(value, ~r/^["']|["']$/, "")

    if Regex.match?(~r/^(0[xX]|#)?[0-9a-fA-F]{6}$/, unquoted) do
      Oma.Color.normalize(unquoted)
    else
      :error
    end
  end
end
