defmodule Mix.Tasks.Oma.Sync do
  @shortdoc "Refresh priv/themes from the omarchy checkout and the registry catalog"

  @moduledoc """
  Vendors palettes into `priv/themes/`:

      mix oma.sync [--omarchy DIR] [--catalog BASE_URL] [--no-community] [--no-builtin]

  * `builtin/<name>.toml` is copied from `DIR/themes/<name>/colors.toml`
    (default `./omarchy`, the mise bootstrap checkout).
  * `community/<slug>.toml` is written from the registry catalog's raw
    colours, in the same flat format.
  * `extra/` is left alone; `mix oma.add` manages it.
  * `index.json` and `SOURCES` are rewritten every run.

  Prints what was added, removed and changed, plus the registry's
  exclusion counts from `report.json`.
  """

  use Mix.Task

  alias Oma.Catalog
  alias Oma.Palette
  alias Oma.Palette.Parser

  @switches [omarchy: :string, catalog: :string, community: :boolean, builtin: :boolean]

  @impl true
  def run(args) do
    {opts, _, invalid} = OptionParser.parse(args, strict: @switches)
    if invalid != [], do: Mix.raise("unknown options: #{inspect(invalid)}")

    priv = priv_dir()
    File.mkdir_p!(priv)
    before = snapshot(priv)
    index = read_index(priv)
    sources = read_sources(priv)

    {builtin_meta, sources} =
      if Keyword.get(opts, :builtin, true),
        do: sync_builtin(priv, Keyword.get(opts, :omarchy, "omarchy"), sources),
        else: {keep(index, "builtin"), sources}

    {community_meta, sources} =
      if Keyword.get(opts, :community, true),
        do: sync_community(priv, opts[:catalog], sources),
        else: {keep(index, "community"), sources}

    extra_meta = keep(index, "extra")

    write_index(priv, Map.merge(Map.merge(builtin_meta, community_meta), extra_meta))
    write_sources(priv, sources)
    report_diff(before, snapshot(priv))
  end

  # -- built-in ----------------------------------------------------------------

  defp sync_builtin(priv, dir, sources) do
    themes_dir = Path.join(dir, "themes")

    unless File.dir?(themes_dir) do
      Mix.raise("""
      no omarchy checkout at #{dir}/themes.
      Run `mise bootstrap repos apply` (or pass --omarchy DIR, or --no-builtin).
      """)
    end

    out = Path.join(priv, "builtin")
    File.mkdir_p!(out)

    meta =
      themes_dir
      |> Path.join("*/colors.toml")
      |> Path.wildcard()
      |> Enum.sort()
      |> Map.new(fn path ->
        name = path |> Path.dirname() |> Path.basename()
        content = builtin_content(path)

        palette =
          case Palette.from_toml(content, name: name, tier: :builtin) do
            {:ok, p} -> p
            {:error, errors} -> Mix.raise("built-in theme #{name} is invalid: #{inspect(errors)}")
          end

        write_if_changed(Path.join(out, name <> ".toml"), content)

        {name,
         %{
           "tier" => "builtin",
           "name" => Oma.Slug.display(name),
           "repo" => "https://github.com/omacom/omarchy",
           "path" => "themes/" <> name,
           "mode" => Atom.to_string(palette.mode),
           "hue" => Atom.to_string(Oma.Color.hue_bucket(palette.accent)),
           "complete" => palette.complete?
         }}
      end)

    prune(out, Map.keys(meta))
    commit = git(dir, ~w(rev-parse HEAD))

    meta = Map.new(meta, fn {k, v} -> {k, Map.put(v, "commit", commit)} end)

    {meta,
     Map.merge(sources, %{
       "omarchy_repo" => "https://github.com/omacom/omarchy",
       "omarchy_commit" => commit
     })}
  end

  # Verbatim, except that a light.mode marker with no mode key becomes an
  # explicit `mode = "light"` so the vendored file stands alone.
  defp builtin_content(path) do
    content = File.read!(path)
    marker = path |> Path.dirname() |> Path.join("light.mode") |> File.exists?()

    if marker and not Map.has_key?(Parser.parse(content), "mode") do
      ~s(mode = "light"\n\n) <> content
    else
      content
    end
  end

  # -- community ---------------------------------------------------------------

  defp sync_community(priv, base_url, sources) do
    fetch_opts = if base_url, do: [base_url: base_url], else: []

    catalog =
      case Catalog.fetch(fetch_opts) do
        {:ok, c} -> c
        {:error, reason} -> Mix.raise("could not fetch the theme catalog: #{inspect(reason)}")
      end

    Mix.shell().info(
      "catalog: #{length(catalog.themes)} themes, generated #{catalog.generated_at}, " <>
        if(catalog.verified, do: "sha256 verified", else: "UNVERIFIED fallback") <>
        "\n  #{catalog.url}"
    )

    out = Path.join(priv, "community")
    File.mkdir_p!(out)

    builtin_names =
      priv
      |> Path.join("builtin/*.toml")
      |> Path.wildcard()
      |> Enum.map(&Path.basename(&1, ".toml"))

    meta =
      catalog
      |> Catalog.entries()
      |> Enum.reduce(%{}, fn %{slug: slug, raw: raw, meta: meta}, acc ->
        cond do
          slug in builtin_names ->
            Mix.shell().error("  skip #{slug}: shadows a built-in theme")
            acc

          true ->
            case Palette.from_raw(raw, name: slug, tier: :community) do
              {:ok, palette} ->
                write_if_changed(Path.join(out, slug <> ".toml"), Parser.encode(raw))
                Map.put(acc, slug, Map.put(meta, "complete", palette.complete?))

              {:error, errors} ->
                Mix.shell().error("  skip #{slug}: #{inspect(errors)}")
                acc
            end
        end
      end)

    prune(out, Map.keys(meta))

    case Catalog.report(fetch_opts) do
      {:ok, %{counts: counts}} ->
        Mix.shell().info(
          "registry: " <> Enum.map_join(Enum.sort(counts), ", ", fn {k, v} -> "#{k} #{v}" end)
        )

      {:error, _} ->
        Mix.shell().info("registry: report.json unavailable")
    end

    {meta,
     Map.merge(sources, %{
       "catalog_url" => catalog.url,
       "catalog_generated_at" => to_string(catalog.generated_at),
       "catalog_schema_version" => to_string(catalog.schema_version),
       "catalog_verified" => to_string(catalog.verified)
     })}
  end

  # -- files -------------------------------------------------------------------

  @doc false
  def priv_dir, do: Path.join(File.cwd!(), "priv/themes")

  @doc false
  def read_index(priv) do
    case File.read(Path.join(priv, "index.json")) do
      {:ok, body} -> JSON.decode!(body)
      _ -> %{}
    end
  end

  @doc false
  def write_index(priv, index) do
    body =
      index
      |> Enum.sort_by(fn {slug, _} -> slug end)
      |> Enum.map_join(",\n", fn {slug, meta} ->
        "  #{JSON.encode!(slug)}: #{JSON.encode!(meta)}"
      end)

    File.write!(Path.join(priv, "index.json"), "{\n" <> body <> "\n}\n")
  end

  defp read_sources(priv) do
    case File.read(Path.join(priv, "SOURCES")) do
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
    end
  end

  defp write_sources(priv, sources) do
    body = sources |> Enum.sort() |> Enum.map_join("\n", fn {k, v} -> "#{k} = #{v}" end)
    File.write!(Path.join(priv, "SOURCES"), body <> "\n")
  end

  defp keep(index, tier) do
    index |> Enum.filter(fn {_, meta} -> meta["tier"] == tier end) |> Map.new()
  end

  defp write_if_changed(path, content) do
    if File.read(path) != {:ok, content}, do: File.write!(path, content)
  end

  defp prune(dir, keep_names) do
    dir
    |> Path.join("*.toml")
    |> Path.wildcard()
    |> Enum.reject(&(Path.basename(&1, ".toml") in keep_names))
    |> Enum.each(&File.rm!/1)
  end

  defp git(dir, args) do
    case System.cmd("git", ["-C", dir | args], stderr_to_stdout: true) do
      {out, 0} -> String.trim(out)
      {out, _} -> Mix.raise("git #{Enum.join(args, " ")} failed in #{dir}: #{out}")
    end
  end

  defp snapshot(priv) do
    priv
    |> Path.join("{builtin,community,extra}/*.toml")
    |> Path.wildcard()
    |> Map.new(fn path -> {Path.relative_to(path, priv), :erlang.md5(File.read!(path))} end)
  end

  defp report_diff(before, after_) do
    added = Map.keys(after_) -- Map.keys(before)
    removed = Map.keys(before) -- Map.keys(after_)

    changed =
      for {path, hash} <- after_, Map.has_key?(before, path), before[path] != hash, do: path

    for {label, paths} <- [added: added, removed: removed, changed: changed], paths != [] do
      Mix.shell().info("#{label} (#{length(paths)}):")
      paths |> Enum.sort() |> Enum.each(&Mix.shell().info("  " <> &1))
    end

    if added == [] and removed == [] and changed == [] do
      Mix.shell().info("themes unchanged (#{map_size(after_)} vendored)")
    else
      Mix.shell().info("#{map_size(after_)} themes vendored")
    end
  end
end
