defmodule Oma.SlugTest do
  use ExUnit.Case, async: true
  alias Oma.Slug

  test "derives slugs the way omarchy-theme-install does" do
    assert Slug.from_url("https://github.com/tahayvr/omarchy-sunset-drive-theme") ==
             "sunset-drive"

    assert Slug.from_url("https://github.com/tahayvr/omarchy-sunset-drive-theme.git") ==
             "sunset-drive"

    assert Slug.from_url("git@github.com:JJDizz1L/aetheria.git") == "aetheria"
    assert Slug.from_url("git@host:omarchy-blue-theme.git") == "blue"
    # upstream strips the prefix before lowercasing, so a capitalised prefix survives
    assert Slug.from_url("https://github.com/OldJobobo/Omarchy-Batman-Theme/") ==
             "omarchy-batman-theme"

    assert Slug.from_url("https://github.com/qaxxorovxd/omarchy-theme-marin") == "theme-marin"
  end

  test "valid? follows the installer's character rule" do
    assert Slug.valid?("tokyo-night")
    assert Slug.valid?("black_arch")
    assert Slug.valid?("retro-82")
    assert Slug.valid?("a.b+c")
    refute Slug.valid?("-leading")
    refute Slug.valid?(".hidden")
    refute Slug.valid?("Upper")
    refute Slug.valid?("has space")
    refute Slug.valid?("")
  end

  test "display matches omarchy-theme-list" do
    assert Slug.display("tokyo-night") == "Tokyo Night"
    assert Slug.display("catppuccin-latte") == "Catppuccin Latte"
    assert Slug.display("01") == "01"
  end
end
