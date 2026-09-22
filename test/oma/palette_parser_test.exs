defmodule Oma.Palette.ParserTest do
  use ExUnit.Case, async: true
  alias Oma.Palette.Parser

  test "reads quoted values, ignores blanks, comments and inline comments" do
    text = """
    # a comment
    mode = "dark"

    accent = "#7aa2f7" # trailing comment
    'quoted_key' = '#ffffff'
    bare = ffffff
    hyprland_active_border = "rgba(26a269ee) rgba(2ec27eee) 45deg"
    """

    assert Parser.parse(text) == %{
             "mode" => "dark",
             "accent" => "#7aa2f7",
             "quoted_key" => "#ffffff",
             "bare" => "ffffff",
             "hyprland_active_border" => "rgba(26a269ee) rgba(2ec27eee) 45deg"
           }
  end

  test "skips keys and values outside the upstream character sets" do
    text = ~s|bad;key = "#000000"\nok = "#000000"\nweird = "a;b"\n|
    assert Parser.parse(text) == %{"ok" => "#000000"}
  end

  test "later duplicates win, as with a bash associative array" do
    assert Parser.parse(~s|a = "#000000"\na = "#ffffff"\n|) == %{"a" => "#ffffff"}
  end

  test "encode writes the conventional grouped order and only present keys" do
    raw = %{
      "bright_red" => "#ff7a93",
      "background" => "#1a1b26",
      "mode" => "dark",
      "accent" => "#7aa2f7",
      "zzz_custom" => "#123456",
      "red" => "#f7768e"
    }

    assert Parser.encode(raw) == """
           mode = "dark"

           accent = "#7aa2f7"

           background = "#1a1b26"

           red = "#f7768e"

           bright_red = "#ff7a93"

           zzz_custom = "#123456"
           """
  end

  test "encode then parse is the identity on a built-in theme" do
    text = File.read!("priv/themes/builtin/tokyo-night.toml")
    raw = Parser.parse(text)
    assert raw |> Parser.encode() |> Parser.parse() == raw
    assert Parser.encode(raw) == text
  end
end
