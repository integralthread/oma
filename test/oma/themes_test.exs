defmodule Oma.ThemesTest do
  use ExUnit.Case, async: true
  alias Oma.Themes

  test "22 built-ins are vendored, all complete" do
    assert length(Themes.builtin()) == 22
    assert Enum.all?(Themes.builtin(), & &1.complete?)
  end

  test "the five light built-ins" do
    light =
      Themes.builtin() |> Enum.filter(&(&1.mode == :light)) |> Enum.map(& &1.name) |> Enum.sort()

    assert light == ~w(catppuccin-latte flexoki-light lupine rose-pine white)
    assert Enum.all?(light, &(&1 in Themes.light()))
    refute "tokyo-night" in Themes.light()
    assert "tokyo-night" in Themes.dark()
  end

  test "community themes are vendored and some are incomplete" do
    assert length(Themes.community()) > 100
    assert Enum.any?(Themes.community(), &(not &1.complete?))
    assert Enum.all?(Themes.complete(), & &1.complete?)
  end

  test "lookups" do
    assert %Oma.Palette{name: "tokyo-night", tier: :builtin} = Themes.get!("tokyo-night")
    assert Themes.valid?("tokyo-night")
    refute Themes.valid?("no-such-theme")
    assert Themes.get("no-such-theme") == nil
    assert_raise ArgumentError, fn -> Themes.get!("no-such-theme") end
    assert Themes.names() == Themes.names() |> Enum.sort()
    assert Themes.names() == Enum.map(Themes.all(), & &1.name)
  end

  test "index metadata and sources" do
    assert Themes.meta("tokyo-night")["tier"] == "builtin"
    assert Themes.meta("tokyo-night")["name"] == "Tokyo Night"
    assert Themes.meta("tokyo-night")["complete"] == true
    assert Themes.meta("no-such-theme") == nil
    assert String.match?(Themes.sources()["omarchy_commit"], ~r/^[0-9a-f]{40}$/)
    assert Themes.sources()["catalog_generated_at"] != nil
    assert map_size(Themes.index()) == length(Themes.all())
  end

  test "default is configurable" do
    assert Themes.default() == "tokyo-night"
    Application.put_env(:oma, :default_theme, "nord")
    assert Themes.default() == "nord"
    Application.delete_env(:oma, :default_theme)
  end
end
