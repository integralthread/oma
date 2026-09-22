defmodule Oma.Contrast do
  @moduledoc """
  WCAG contrast checks for the colour pairs a web app actually relies on:
  body and secondary text on the page and on a raised surface, button text
  on `accent`, and the status hues on the page. The schema guarantees
  shape, not legibility; this is how a theme that fails shows up before it
  ships.
  """

  alias Oma.Color
  alias Oma.Palette

  @pairs [
    {:foreground, :background, 4.5},
    {:dark_foreground, :background, 3.0},
    {:foreground, :lighter_background, 4.5},
    {:background, :accent, 3.0},
    {:red, :background, 3.0},
    {:green, :background, 3.0},
    {:yellow, :background, 3.0},
    {:blue, :background, 3.0}
  ]

  @type result :: %{fg: atom, bg: atom, ratio: float, minimum: float, pass?: boolean}

  @doc "The `{foreground_key, background_key, minimum_ratio}` pairs checked."
  def pairs, do: @pairs

  @doc "Every pair with its ratio and pass/fail."
  @spec report(Palette.t()) :: [result]
  def report(%Palette{} = p) do
    for {fg, bg, min} <- @pairs do
      ratio = Color.contrast_ratio(Map.fetch!(p, fg), Map.fetch!(p, bg))
      %{fg: fg, bg: bg, ratio: Float.round(ratio, 2), minimum: min, pass?: ratio >= min}
    end
  end

  @doc "Only the failing pairs."
  @spec failures(Palette.t()) :: [result]
  def failures(%Palette{} = p), do: p |> report() |> Enum.reject(& &1.pass?)

  @doc "`:ok` or `{:error, failures}`."
  @spec check(Palette.t()) :: :ok | {:error, [result]}
  def check(%Palette{} = p) do
    case failures(p) do
      [] -> :ok
      failures -> {:error, failures}
    end
  end

  @doc ~S"""
  Stable identifier for a pair, used in the known-exceptions file:
  `"<theme> <fg>/<bg>"`.

      iex> Oma.Contrast.key("nord", %{fg: :yellow, bg: :background})
      "nord yellow/background"
  """
  @spec key(String.t(), %{fg: atom, bg: atom}) :: String.t()
  def key(theme, %{fg: fg, bg: bg}), do: "#{theme} #{fg}/#{bg}"
end
