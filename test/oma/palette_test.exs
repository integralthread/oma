defmodule Oma.PaletteTest do
  use ExUnit.Case, async: true
  alias Oma.Palette

  @builtins Path.wildcard("priv/themes/builtin/*.toml")

  defp upstream(name) do
    "test/fixtures/upstream/#{name}.tsv"
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Map.new(fn line ->
      [k, v] = String.split(line, "\t", parts: 2)
      {k, v}
    end)
  end

  # Compare every name upstream resolves that we also expose.
  defp assert_matches_upstream(palette, name) do
    ours = Palette.resolved(palette)
    theirs = upstream(name)

    for {key, value} <- theirs, Map.has_key?(ours, key) do
      assert String.downcase(ours[key]) == String.downcase(value),
             "#{name}: #{key} ours=#{ours[key]} upstream=#{value}"
    end
  end

  describe "built-in themes" do
    test "all 22 load, are complete, and the five light ones are light" do
      palettes =
        for path <- @builtins do
          assert {:ok, p} = Palette.from_file(path, tier: :builtin), path
          p
        end

      assert length(palettes) == 22
      assert Enum.all?(palettes, & &1.complete?)

      light = palettes |> Enum.filter(&(&1.mode == :light)) |> Enum.map(& &1.name) |> Enum.sort()
      assert light == ~w(catppuccin-latte flexoki-light lupine rose-pine white)
    end

    test "derived orange and brown match upstream for the three themes without them" do
      for name <- ~w(last-horizon solitude white) do
        {:ok, p} = Palette.from_file("priv/themes/builtin/#{name}.toml", tier: :builtin)
        assert p.complete?
        refute :orange in p.defined
        assert_matches_upstream(p, name)
      end
    end

    test "tokyo-night and flexoki-light resolve identically to upstream" do
      for name <- ~w(tokyo-night flexoki-light) do
        {:ok, p} = Palette.from_file("priv/themes/builtin/#{name}.toml", tier: :builtin)
        assert_matches_upstream(p, name)
      end
    end

    test "rare extra keys are kept on the struct and out of the colours" do
      {:ok, p} = Palette.from_file("priv/themes/builtin/hackerman.toml", tier: :builtin)
      assert p.extra["hyprland_active_border"] == "rgba(26a269ee) rgba(2ec27eee) 45deg"
      refute Map.has_key?(Palette.colors(p), :hyprland_active_border)
    end
  end

  describe "17-key community shape (aetheria)" do
    setup do
      {:ok, p} =
        Palette.from_file("test/fixtures/aetheria.toml", name: "aetheria", tier: :community)

      %{p: p}
    end

    test "loads, is incomplete, infers dark mode from the background", %{p: p} do
      refute p.complete?
      assert p.mode == :dark
      assert p.tier == :community
      refute :selection in p.defined
      refute :muted in p.defined
      refute :light_foreground in p.defined
    end

    test "derives the missing neutrals exactly as upstream", %{p: p} do
      assert_matches_upstream(p, "aetheria")
      # spot checks against the cascade
      assert p.muted == p.dark_foreground
      assert p.selection == p.background
      assert p.lighter_background == p.background
      assert p.light_foreground == p.foreground
      assert p.dark_background == Oma.Color.mix(p.background, "#000000", 0.25)
      assert p.darker_background == Oma.Color.mix(p.background, "#000000", 0.5)
      assert p.orange == p.yellow
      assert p.brown == Oma.Color.mix(p.yellow, "#000000", 0.5)
    end
  end

  describe "legacy aliases" do
    test "bg/fg and colorN resolve, canonical wins over legacy" do
      raw = %{
        "bg" => "#000000",
        "fg" => "#ffffff",
        "color1" => "#ff0000",
        "color2" => "#00ff00",
        "color3" => "#ffff00",
        "color4" => "#0000ff",
        "color5" => "#ff00ff",
        "color6" => "#00ffff",
        "color8" => "#808080",
        "color12" => "#8080ff",
        "purple" => "#123456",
        "magenta" => "#654321",
        "theme_type" => "dark",
        "accent" => "#0000ff"
      }

      assert {:ok, p} = Palette.from_raw(raw, name: "legacy")
      assert p.background == "#000000"
      assert p.foreground == "#ffffff"
      assert p.red == "#ff0000"
      assert p.blue == "#0000ff"
      assert p.bright_blue == "#8080ff"
      assert p.magenta == "#654321"
      assert p.muted == "#808080"
      assert p.dark_foreground == "#808080"
      assert p.selection == "#808080"
      assert p.mode == :dark
      refute p.complete?
      assert p.bright_red == Oma.Color.mix("#ff0000", "#ffffff", 0.2)
    end
  end

  describe "validation" do
    @minimal %{
      "accent" => "#7aa2f7",
      "background" => "#1a1b26",
      "foreground" => "#a9b1d6",
      "red" => "#f7768e",
      "yellow" => "#e0af68",
      "green" => "#9ece6a",
      "cyan" => "#449dab",
      "blue" => "#7aa2f7",
      "magenta" => "#ad8ee6"
    }

    test "the nine required keys are enough" do
      assert {:ok, p} = Palette.from_raw(@minimal, name: "min")
      assert p.mode == :dark
      refute p.complete?
      assert Enum.all?(Palette.color_keys(), &is_binary(Map.fetch!(p, &1)))
    end

    test "missing required keys are an error" do
      raw = Map.drop(@minimal, ["blue", "cyan"])
      assert {:error, [{:missing_required, [:cyan, :blue]}]} = Palette.from_raw(raw, name: "x")
    end

    test "a required key that is not a colour is an error" do
      raw = Map.put(@minimal, "blue", "CellForeground")
      assert {:error, [{:bad_value, :blue, "CellForeground"}]} = Palette.from_raw(raw, name: "x")
    end

    test "an optional key that is not a colour is dropped with a warning" do
      raw = Map.put(@minimal, "selection", "nope")
      assert {:ok, p} = Palette.from_raw(raw, name: "x")
      assert p.warnings == [{:dropped, "selection", "nope"}]
      assert p.selection == p.background
    end

    test "a mode that is neither dark nor light is an error" do
      assert {:error, [{:bad_mode, "dim"}]} =
               Palette.from_raw(Map.put(@minimal, "mode", "dim"), name: "x")
    end

    test "a name that fails the slug rule is an error" do
      assert {:error, [{:bad_name, "Bad Name"}]} = Palette.from_raw(@minimal, name: "Bad Name")
    end

    test "light.mode marker sets light only when mode is undeclared" do
      assert {:ok, p} = Palette.from_raw(@minimal, name: "x", light_marker: true)
      assert p.mode == :light

      assert {:ok, p} =
               Palette.from_raw(Map.put(@minimal, "mode", "dark"), name: "x", light_marker: true)

      assert p.mode == :dark
    end
  end

  describe "idempotence" do
    test "feeding a derived palette back in changes nothing" do
      {:ok, p} = Palette.from_file("test/fixtures/aetheria.toml", name: "aetheria")

      raw =
        p
        |> Palette.colors()
        |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
        |> Map.put("mode", "dark")

      {:ok, again} = Palette.from_raw(raw, name: "aetheria")
      assert Palette.colors(again) == Palette.colors(p)
      assert again.complete?
    end
  end
end
