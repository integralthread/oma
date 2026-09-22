defmodule Oma.Catalog do
  @moduledoc """
  The community theme catalog published by `omacom/omarchy-theme-registry`.

  `fetch/1` downloads `catalog.json` and `catalog.json.sha256` from a base
  URL, verifies the digest and decodes. When the CDN is unreachable it falls
  back to the snapshot the marketplace site commits, unverified and flagged
  as such. `entries/1` turns each catalog theme into the raw palette map and
  the metadata `mix oma.sync` vendors.

  A catalog entry's `colors` are the keys the author defined, not a resolved
  palette. `mode` is resolved by the registry; it is treated as author
  declared only when the `MODE_UNDECLARED` warning is absent, so a palette
  built from the catalog derives exactly like one built from the file.
  """

  alias Oma.Color

  @default_base "https://pub-98465b4520f24f9a8f162c4f722a293f.r2.dev/v1"
  @fallback_url "https://raw.githubusercontent.com/omacom/omarchy-theme-marketplace/master/data/catalog.json"

  @type t :: %__MODULE__{}

  defstruct [:generated_at, :schema_version, :omarchy_min, :url, verified: false, themes: []]

  def default_base_url, do: @default_base
  def fallback_url, do: @fallback_url

  @doc """
  Fetch and verify the catalog.

  Options: `:base_url` (default `default_base_url/0`), `:fallback` (default
  `true`, use the marketplace snapshot when the CDN fails).
  """
  @spec fetch(keyword) :: {:ok, t} | {:error, term}
  def fetch(opts \\ []) do
    base = opts |> Keyword.get(:base_url, @default_base) |> String.trim_trailing("/")
    url = base <> "/catalog.json"
    fallback? = Keyword.get(opts, :fallback, true)

    case fetch_verified(url) do
      {:ok, catalog} ->
        {:ok, catalog}

      {:error, reason} when fallback? ->
        IO.warn(
          "catalog: CDN failed (#{inspect(reason)}); trying the unverified marketplace snapshot"
        )

        case Oma.HTTP.get(@fallback_url) do
          {:ok, body} ->
            with {:ok, catalog} <- decode(body) do
              {:ok, %{catalog | url: @fallback_url, verified: false}}
            end

          {:error, _} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_verified(url) do
    with {:ok, body} <- Oma.HTTP.get(url),
         {:ok, digest} <- Oma.HTTP.get(url <> ".sha256"),
         :ok <- verify(body, digest),
         {:ok, catalog} <- decode(body) do
      {:ok, %{catalog | url: url, verified: true}}
    end
  end

  @doc "Check a body against a `catalog.json.sha256` file (`<hex>  catalog.json` or bare hex)."
  @spec verify(binary, binary) :: :ok | {:error, :sha256_mismatch}
  def verify(body, digest_text) do
    expected =
      digest_text
      |> String.trim()
      |> String.split()
      |> List.first("")
      |> String.downcase()

    actual = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
    if expected == actual, do: :ok, else: {:error, :sha256_mismatch}
  end

  @doc "Decode catalog JSON."
  @spec decode(binary) :: {:ok, t} | {:error, term}
  def decode(body) do
    case JSON.decode(body) do
      {:ok, %{"themes" => themes} = map} when is_list(themes) ->
        {:ok,
         %__MODULE__{
           generated_at: map["generated_at"],
           schema_version: map["schema_version"],
           omarchy_min: map["omarchy_min"],
           themes: themes
         }}

      {:ok, _} ->
        {:error, :not_a_catalog}

      {:error, reason} ->
        {:error, {:json, reason}}
    end
  end

  @doc "Fetch `report.json` and return its `counts` map, or an error."
  @spec report(keyword) :: {:ok, map} | {:error, term}
  def report(opts \\ []) do
    base = opts |> Keyword.get(:base_url, @default_base) |> String.trim_trailing("/")

    with {:ok, body} <- Oma.HTTP.get(base <> "/report.json"),
         {:ok, %{"counts" => counts} = report} <- JSON.decode(body) do
      {:ok, %{counts: counts, problems: Map.get(report, "problems", [])}}
    else
      {:ok, _} -> {:error, :not_a_report}
      other -> other
    end
  end

  @doc "Each theme as `%{slug: , raw: , meta: }`, sorted by slug."
  @spec entries(t) :: [%{slug: String.t(), raw: map, meta: map}]
  def entries(%__MODULE__{themes: themes}) do
    themes
    |> Enum.map(&%{slug: &1["slug"], raw: raw_colors(&1), meta: meta(&1)})
    |> Enum.sort_by(& &1.slug)
  end

  @doc "The raw palette map for an entry: its `colors` plus `mode` when the author declared it."
  @spec raw_colors(map) :: %{String.t() => String.t()}
  def raw_colors(%{"colors" => colors} = entry) when is_map(colors) do
    if mode_declared?(entry) and entry["mode"] in ["dark", "light"] do
      Map.put(colors, "mode", entry["mode"])
    else
      colors
    end
  end

  def raw_colors(_), do: %{}

  defp mode_declared?(entry), do: "MODE_UNDECLARED" not in List.wrap(entry["warnings"])

  @doc "Picker metadata for an entry, string keyed for `index.json`."
  @spec meta(map) :: map
  def meta(entry) do
    accent = get_in(entry, ["colors", "accent"])

    %{
      "tier" => "community",
      "name" => entry["name"] || entry["slug"],
      "repo" => entry["repo"],
      "commit" => entry["commit"],
      "author" => get_in(entry, ["author", "login"]),
      "description" => entry["description"],
      "license" => entry["license"],
      "mode" => entry["mode"],
      "hue" => entry["hue"] || (accent && Atom.to_string(Color.hue_bucket(accent))),
      "generation" => entry["generation"],
      "stars" => entry["stars"],
      "tags" => entry["tags"] || [],
      "featured" => entry["featured"] || false,
      "warnings" => entry["warnings"] |> List.wrap() |> Enum.uniq(),
      "preview" => get_in(entry, ["preview", "thumb"]),
      "added_at" => entry["added_at"],
      "pushed_at" => entry["pushed_at"]
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end
end
