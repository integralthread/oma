defmodule Oma.Themes do
  @moduledoc """
  Compile-time index of the palettes vendored under `priv/themes`.

  Everything is read when this module compiles, so an application gets the
  theme list, the palettes and the picker metadata with no runtime file or
  network access. The module recompiles when any vendored file or
  `index.json` changes; `mix oma.sync` and `mix oma.add` always rewrite
  `index.json`, which is what makes a newly added file picked up.
  """

  alias Oma.Palette

  @priv Path.expand("../../priv/themes", __DIR__)
  @tiers ~w(builtin community extra)a

  @external_resource Path.join(@priv, "index.json")
  @external_resource Path.join(@priv, "SOURCES")

  @index (case File.read(Path.join(@priv, "index.json")) do
            {:ok, body} -> JSON.decode!(body)
            _ -> %{}
          end)

  @sources (case File.read(Path.join(@priv, "SOURCES")) do
              {:ok, body} ->
                body
                |> String.split("\n", trim: true)
                |> Enum.flat_map(fn line ->
                  case String.split(line, "=", parts: 2) do
                    [k, v] -> [{String.trim(k), String.trim(v)}]
                    _ -> []
                  end
                end)
                |> Map.new()

              _ ->
                %{}
            end)

  @palettes (for tier <- @tiers,
                 path <- Path.wildcard(Path.join([@priv, Atom.to_string(tier), "*.toml"])) do
               Module.put_attribute(__MODULE__, :external_resource, path)

               case Palette.from_file(path, tier: tier) do
                 {:ok, palette} -> palette
                 {:error, errors} -> raise "#{path}: #{inspect(errors)}"
               end
             end)
            |> Enum.sort_by(& &1.name)

  @doc "Every vendored palette, sorted by name."
  @spec all() :: [Palette.t()]
  def all, do: @palettes

  @doc "Every theme name, sorted."
  @spec names() :: [String.t()]
  def names, do: Enum.map(@palettes, & &1.name)

  @doc "Palettes in one tier."
  @spec tier(Palette.tier()) :: [Palette.t()]
  def tier(tier) when tier in @tiers, do: Enum.filter(@palettes, &(&1.tier == tier))

  def builtin, do: tier(:builtin)
  def community, do: tier(:community)
  def extra, do: tier(:extra)

  @doc "Palettes whose author defined all 24 schema keys."
  @spec complete() :: [Palette.t()]
  def complete, do: Enum.filter(@palettes, & &1.complete?)

  @doc "Names of light themes."
  def light, do: for(p <- @palettes, p.mode == :light, do: p.name)

  @doc "Names of dark themes."
  def dark, do: for(p <- @palettes, p.mode == :dark, do: p.name)

  # Lookups scan the list rather than a map literal: before the first sync
  # the vendored set is empty and the type checker would flag Map.get on an
  # empty map. A few hundred entries make the scan negligible.
  @spec get(String.t()) :: Palette.t() | nil
  def get(name), do: Enum.find(@palettes, &(&1.name == name))

  @spec get!(String.t()) :: Palette.t()
  def get!(name) do
    get(name) || raise ArgumentError, "unknown theme #{inspect(name)}"
  end

  @spec valid?(term) :: boolean
  def valid?(name), do: get(name) != nil

  @doc "Picker metadata from `index.json` for one theme, or nil."
  @spec meta(String.t()) :: map | nil
  def meta(name), do: Enum.find_value(@index, fn {k, v} -> k == name && v end)

  @doc "The whole `index.json` map."
  def index, do: @index

  @doc "Key-value pairs from `priv/themes/SOURCES`."
  def sources, do: @sources

  @doc """
  The default theme name: `config :oma, default_theme: "..."`, else
  `tokyo-night`.
  """
  @spec default() :: String.t()
  def default, do: Application.get_env(:oma, :default_theme, "tokyo-night")
end
