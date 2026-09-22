defmodule Oma.Color do
  @moduledoc """
  Colour arithmetic shared by palette derivation, CSS rendering and the
  contrast report.

  `mix/3`, `channel_sum/1` and `infer_mode/1` mirror `bin/omarchy-theme-color`
  in the Omarchy repository so that a palette derived here matches what the
  desktop renders. `hue_bucket/1` mirrors the theme registry's validator so
  the built-in themes get the same hue grouping as the marketplace.
  """

  @type rgb :: {0..255, 0..255, 0..255}
  @type hex :: String.t()
  @type hue :: :red | :orange | :yellow | :green | :teal | :blue | :purple | :pink | :gray

  @hex_re ~r/^#[0-9a-fA-F]{6}$/

  @doc "True for a `#rrggbb` string in either case."
  @spec valid_hex?(term) :: boolean
  def valid_hex?(value) when is_binary(value), do: Regex.match?(@hex_re, value)
  def valid_hex?(_), do: false

  @doc """
  Normalise the colour spellings the registry accepts (`#rgb`, `#rrggbb`,
  `#rrggbbaa`, `rrggbb`, `0xrrggbb`) to lowercase `#rrggbb`.
  """
  @spec normalize(term) :: {:ok, hex} | :error
  def normalize(value) when is_binary(value) do
    v = value |> String.trim() |> String.downcase()
    v = if String.starts_with?(v, "0x"), do: binary_part(v, 2, byte_size(v) - 2), else: v
    v = if String.starts_with?(v, "#"), do: binary_part(v, 1, byte_size(v) - 1), else: v

    v =
      cond do
        Regex.match?(~r/^[0-9a-f]{3}$/, v) ->
          v |> String.graphemes() |> Enum.map_join(&(&1 <> &1))

        Regex.match?(~r/^[0-9a-f]{8}$/, v) ->
          binary_part(v, 0, 6)

        true ->
          v
      end

    if Regex.match?(~r/^[0-9a-f]{6}$/, v), do: {:ok, "#" <> v}, else: :error
  end

  def normalize(_), do: :error

  @doc "Parse `#rrggbb` into an `{r, g, b}` tuple."
  @spec parse(hex) :: {:ok, rgb} | :error
  def parse(hex) do
    with {:ok, "#" <> digits} <- normalize(hex),
         {:ok, <<r, g, b>>} <- Base.decode16(digits, case: :lower) do
      {:ok, {r, g, b}}
    else
      _ -> :error
    end
  end

  @spec parse!(hex) :: rgb
  def parse!(hex) do
    case parse(hex) do
      {:ok, rgb} -> rgb
      :error -> raise ArgumentError, "not a 6-digit hex colour: #{inspect(hex)}"
    end
  end

  @doc "Render an `{r, g, b}` tuple as lowercase `#rrggbb`."
  @spec to_hex(rgb) :: hex
  def to_hex({r, g, b}), do: "#" <> Base.encode16(<<r, g, b>>, case: :lower)

  @doc """
  Blend `a` toward `b` by `amount`, a fraction in `0..1`, a percentage above 1
  (`25` means 25%), or a `"25%"` string. Rounds half up per channel, the same
  as the upstream `mix_color` awk.
  """
  @spec mix(hex, hex, number | String.t()) :: hex
  def mix(a, b, amount) do
    w = amount |> weight() |> min(1.0) |> max(0.0)
    {ar, ag, ab} = parse!(a)
    {br, bg, bb} = parse!(b)
    ch = fn x, y -> trunc(x * (1 - w) + y * w + 0.5) end
    to_hex({ch.(ar, br), ch.(ag, bg), ch.(ab, bb)})
  end

  defp weight(s) when is_binary(s) do
    case String.trim_trailing(s, "%") do
      ^s ->
        s |> String.to_float() |> weight()

      pct ->
        weight(String.to_float(pct <> if(String.contains?(pct, "."), do: "", else: ".0")) / 100)
    end
  end

  defp weight(n) when is_number(n) and n > 1, do: n / 100
  defp weight(n) when is_number(n), do: n * 1.0

  @doc "Sum of the three channels; the upstream mode heuristic."
  @spec channel_sum(hex) :: 0..765
  def channel_sum(hex) do
    {r, g, b} = parse!(hex)
    r + g + b
  end

  @doc "`:light` when the channel sum exceeds 382, else `:dark`."
  @spec infer_mode(hex) :: :light | :dark
  def infer_mode(background) do
    if channel_sum(background) > 382, do: :light, else: :dark
  end

  @doc "WCAG 2.x relative luminance in `0.0..1.0`."
  @spec relative_luminance(hex) :: float
  def relative_luminance(hex) do
    {r, g, b} = parse!(hex)
    0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
  end

  defp linear(channel) do
    c = channel / 255

    if c <= 0.03928 do
      c / 12.92
    else
      :math.pow((c + 0.055) / 1.055, 2.4)
    end
  end

  @doc "WCAG contrast ratio between two colours, `1.0..21.0`."
  @spec contrast_ratio(hex, hex) :: float
  def contrast_ratio(a, b) do
    la = relative_luminance(a)
    lb = relative_luminance(b)
    {hi, lo} = if la >= lb, do: {la, lb}, else: {lb, la}
    (hi + 0.05) / (lo + 0.05)
  end

  @doc """
  Bucket a colour into the marketplace's filterable hues. Mirrors
  `hueBucket` in the registry validator.
  """
  @spec hue_bucket(hex) :: hue
  def hue_bucket(hex) do
    {h, s, l} = to_hsl(hex)

    cond do
      s < 0.15 or l < 0.08 or l > 0.95 -> :gray
      h < 12 or h >= 352 -> :red
      h < 38 -> :orange
      h < 68 -> :yellow
      h < 160 -> :green
      h < 195 -> :teal
      h < 255 -> :blue
      h < 300 -> :purple
      true -> :pink
    end
  end

  @doc "Hue in degrees, saturation and lightness in `0.0..1.0`."
  @spec to_hsl(hex) :: {float, float, float}
  def to_hsl(hex) do
    {r255, g255, b255} = parse!(hex)
    {r, g, b} = {r255 / 255, g255 / 255, b255 / 255}
    max = Enum.max([r, g, b])
    min = Enum.min([r, g, b])
    l = (max + min) / 2

    if max == min do
      {0.0, 0.0, l}
    else
      d = max - min
      s = if l > 0.5, do: d / (2 - max - min), else: d / (max + min)

      h =
        cond do
          max == r -> ((g - b) / d + if(g < b, do: 6, else: 0)) * 60
          max == g -> ((b - r) / d + 2) * 60
          true -> ((r - g) / d + 4) * 60
        end

      {h, s, l}
    end
  end
end
