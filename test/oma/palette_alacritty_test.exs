defmodule Oma.Palette.AlacrittyTest do
  use ExUnit.Case, async: true
  alias Oma.Palette.Alacritty

  @sample """
  [colors.primary]
  background = "#1a1b26"
  foreground = '#a9b1d6'

  [colors.selection]
  background = "#292e42"
  text = "CellForeground"

  [colors.normal]
  black = "0x13141c"
  red = "#f7768e"
  green = "#9ece6a"
  yellow = "#e0af68"
  blue = "#7aa2f7"
  magenta = "#ad8ee6"
  cyan = "#449dab"
  white = "#b4bee6" # comment

  [colors.bright]
  black = "#565f89"
  red = "#ff7a93"
  white = "#c0caf5"
  """

  test "maps the tables the way the registry does" do
    raw = Alacritty.parse(@sample)

    assert raw["background"] == "#1a1b26"
    assert raw["foreground"] == "#a9b1d6"
    assert raw["selection"] == "#292e42"
    assert raw["dark_background"] == "#13141c"
    assert raw["light_foreground"] == "#b4bee6"
    assert raw["dark_foreground"] == "#565f89"
    assert raw["bright_foreground"] == "#c0caf5"
    assert raw["red"] == "#f7768e"
    assert raw["bright_red"] == "#ff7a93"
    assert raw["accent"] == "#7aa2f7"
    refute Map.has_key?(raw, "bright_green")
    refute Map.has_key?(raw, "text")
  end

  test "dotted keys under [colors] are accepted, section form wins" do
    text = """
    [colors]
    primary.background = "#000000"
    normal.red = "#110000"

    [colors.normal]
    red = "#ff0000"
    """

    raw = Alacritty.parse(text)
    assert raw["background"] == "#000000"
    assert raw["red"] == "#ff0000"
  end

  test "produces a palette Oma.Palette accepts" do
    raw = Alacritty.parse(@sample)
    assert {:ok, palette} = Oma.Palette.from_raw(raw, name: "sample")
    assert palette.mode == :dark
    refute palette.complete?
  end
end
