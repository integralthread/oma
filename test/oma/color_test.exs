defmodule Oma.ColorTest do
  use ExUnit.Case, async: true
  alias Oma.Color

  describe "normalize/1 and parse/1" do
    test "accepts the spellings the registry accepts" do
      assert {:ok, "#1a1b26"} = Color.normalize("#1A1B26")
      assert {:ok, "#1a1b26"} = Color.normalize("1a1b26")
      assert {:ok, "#1a1b26"} = Color.normalize("0x1A1B26")
      assert {:ok, "#1a1b26"} = Color.normalize("#1a1b26ff")
      assert {:ok, "#aabbcc"} = Color.normalize("#abc")
      assert :error = Color.normalize("CellForeground")
      assert :error = Color.normalize("#12345")
    end

    test "parse round-trips through to_hex" do
      assert {:ok, {26, 27, 38}} = Color.parse("#1a1b26")
      assert Color.to_hex({26, 27, 38}) == "#1a1b26"
    end

    test "valid_hex? is strict six-digit with a hash" do
      assert Color.valid_hex?("#205EA6")
      refute Color.valid_hex?("205EA6")
      refute Color.valid_hex?("#fff")
    end
  end

  describe "mix/3" do
    test "matches the upstream awk with round-half-up" do
      # brown for tokyo-night if it were missing: orange #eb927b mixed 50% with black
      assert Color.mix("#eb927b", "#000000", 0.5) == "#76493e"
      # 25% and 50% toward black from tokyo-night background
      assert Color.mix("#1a1b26", "#000000", 0.25) == "#14141d"
      assert Color.mix("#1a1b26", "#000000", "50%") == "#0d0e13"
      # percentage as a number above 1
      assert Color.mix("#1a1b26", "#000000", 50) == "#0d0e13"
    end

    test "20% toward white for a bright hue" do
      assert Color.mix("#f7768e", "#ffffff", 0.2) == "#f991a5"
    end
  end

  describe "mode inference" do
    test "flexoki-light background sums to 747 and is light" do
      assert Color.channel_sum("#FFFCF0") == 747
      assert Color.infer_mode("#FFFCF0") == :light
    end

    test "tokyo-night background sums to 91 and is dark" do
      assert Color.channel_sum("#1a1b26") == 91
      assert Color.infer_mode("#1a1b26") == :dark
    end

    test "the threshold is strictly greater than 382" do
      assert Color.infer_mode("#7f7f80") == :dark
      assert Color.infer_mode("#7f7f81") == :light
    end
  end

  describe "WCAG" do
    test "black on white is 21:1 and identical colours are 1:1" do
      assert_in_delta Color.contrast_ratio("#000000", "#ffffff"), 21.0, 0.001
      assert_in_delta Color.contrast_ratio("#7aa2f7", "#7aa2f7"), 1.0, 0.0001
    end

    test "tokyo-night body text clears AA" do
      assert Color.contrast_ratio("#a9b1d6", "#1a1b26") > 4.5
    end
  end

  describe "hue_bucket/1" do
    test "buckets match the registry" do
      assert Color.hue_bucket("#7aa2f7") == :blue
      assert Color.hue_bucket("#f7768e") == :pink
      assert Color.hue_bucket("#ff0000") == :red
      assert Color.hue_bucket("#9ece6a") == :green
      assert Color.hue_bucket("#e0af68") == :orange
      assert Color.hue_bucket("#ad8ee6") == :purple
      assert Color.hue_bucket("#808080") == :gray
      assert Color.hue_bucket("#000000") == :gray
    end
  end
end
