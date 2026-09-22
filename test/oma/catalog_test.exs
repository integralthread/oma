defmodule Oma.CatalogTest do
  use ExUnit.Case, async: true
  alias Oma.Catalog
  alias Oma.Palette
  alias Oma.Palette.Parser

  @body File.read!("test/fixtures/catalog.json")
  @digest File.read!("test/fixtures/catalog.json.sha256")

  test "decodes the fixture" do
    assert {:ok, catalog} = Catalog.decode(@body)
    assert catalog.schema_version == 1
    assert catalog.omarchy_min == "4.0.0"
    assert length(catalog.themes) == 4
  end

  test "verify accepts the published digest format and rejects a tampered body" do
    assert :ok = Catalog.verify(@body, @digest)
    assert :ok = Catalog.verify(@body, String.split(@digest) |> hd())
    assert {:error, :sha256_mismatch} = Catalog.verify(@body <> " ", @digest)
  end

  test "decode rejects JSON that is not a catalog" do
    assert {:error, :not_a_catalog} = Catalog.decode(~s({"themes": "no"}))
    assert {:error, {:json, _}} = Catalog.decode("nope")
  end

  describe "entries/1" do
    setup do
      {:ok, catalog} = Catalog.decode(@body)
      %{entries: Map.new(Catalog.entries(catalog), &{&1.slug, &1})}
    end

    test "sorted by slug with raw colours and picker metadata", %{entries: e} do
      assert Map.keys(e) |> Enum.sort() == ~w(01 aetheria arc-blueberry archwave)
      assert e["arc-blueberry"].meta["tier"] == "community"
      assert e["arc-blueberry"].meta["repo"] =~ "github.com"
      assert is_binary(e["arc-blueberry"].meta["commit"])

      assert e["arc-blueberry"].meta["hue"] in ~w(red orange yellow green teal blue purple pink gray)

      assert is_binary(e["arc-blueberry"].meta["preview"])
    end

    test "mode is raw only when the author declared it", %{entries: e} do
      assert e["arc-blueberry"].raw["mode"] == "dark"
      refute Map.has_key?(e["aetheria"].raw, "mode")
      refute Map.has_key?(e["archwave"].raw, "mode")
    end

    test "a 17-key entry and a complete entry both build palettes", %{entries: e} do
      assert {:ok, partial} =
               Palette.from_raw(e["aetheria"].raw, name: "aetheria", tier: :community)

      refute partial.complete?
      assert partial.mode == :dark

      assert {:ok, full} =
               Palette.from_raw(e["arc-blueberry"].raw, name: "arc-blueberry", tier: :community)

      assert full.complete?
    end

    test "the catalog entry and its vendored file derive the same palette", %{entries: e} do
      for {slug, entry} <- e do
        {:ok, from_catalog} = Palette.from_raw(entry.raw, name: slug, tier: :community)

        {:ok, from_file} =
          entry.raw |> Parser.encode() |> Palette.from_toml(name: slug, tier: :community)

        assert Palette.colors(from_file) == Palette.colors(from_catalog), slug
        assert from_file.mode == from_catalog.mode, slug
        assert from_file.complete? == from_catalog.complete?, slug
      end
    end
  end
end
