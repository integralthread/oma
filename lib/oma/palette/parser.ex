defmodule Oma.Palette.Parser do
  @moduledoc """
  Reader and writer for the flat `colors.toml` format.

  The reader mirrors `parse_colors_file` in `bin/omarchy-theme-color`: one
  `key = value` per line, quotes stripped, inline comments after a closing
  quote ignored, unknown keys kept. Keys and values outside the upstream
  character sets are skipped, as upstream does, rather than failing the
  file. This is deliberately not a general TOML parser.
  """

  @key_re ~r/^[A-Za-z0-9_-]+$/
  @value_re ~r|^[A-Za-z0-9#(),._+/% -]*$|

  # Conventional key order for the writer, matching the built-in themes.
  @groups [
    ~w(mode),
    ~w(accent selection muted),
    ~w(background dark_background darker_background lighter_background),
    ~w(foreground dark_foreground light_foreground bright_foreground),
    ~w(red yellow orange green cyan blue magenta brown),
    ~w(bright_red bright_yellow bright_green bright_cyan bright_blue bright_magenta)
  ]

  @doc "Parse `colors.toml` text into a string-keyed map of raw values."
  @spec parse(String.t()) :: %{String.t() => String.t()}
  def parse(text) when is_binary(text) do
    text
    |> String.split(["\n", "\r\n"])
    |> Enum.reduce(%{}, fn line, acc ->
      case parse_line(line) do
        {key, value} -> Map.put(acc, key, value)
        nil -> acc
      end
    end)
  end

  defp parse_line(line) do
    case String.split(line, "=", parts: 2) do
      [raw_key, raw_value] ->
        key = String.replace(raw_key, ~r/["' ]/, "")

        cond do
          key == "" or String.starts_with?(key, "#") -> nil
          not Regex.match?(@key_re, key) -> nil
          true -> value(key, raw_value)
        end

      _ ->
        nil
    end
  end

  defp value(key, raw) do
    value =
      case Regex.run(~r/["']([^"']*)["']/, raw) do
        [_, quoted] -> quoted
        nil -> String.trim(raw)
      end

    if value != "" and Regex.match?(@value_re, value), do: {key, value}, else: nil
  end

  @doc """
  Write a raw key map back out in the conventional grouped order. Only the
  keys present are written, so a partial palette stays partial on disk.
  """
  @spec encode(%{String.t() => String.t()}) :: String.t()
  def encode(raw) when is_map(raw) do
    known = List.flatten(@groups)

    grouped =
      Enum.map(@groups, fn group ->
        group |> Enum.filter(&Map.has_key?(raw, &1)) |> Enum.map(&line(&1, raw))
      end)

    rest =
      raw
      |> Map.keys()
      |> Enum.reject(&(&1 in known))
      |> Enum.sort()
      |> Enum.map(&line(&1, raw))

    (grouped ++ [rest])
    |> Enum.reject(&(&1 == []))
    |> Enum.map_join("\n\n", &Enum.join(&1, "\n"))
    |> Kernel.<>("\n")
  end

  defp line(key, raw), do: ~s(#{key} = "#{Map.fetch!(raw, key)}")
end
