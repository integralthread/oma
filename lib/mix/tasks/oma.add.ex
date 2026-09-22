defmodule Mix.Tasks.Oma.Add do
  @shortdoc "Vendor an unlisted theme from a git repository"

  @moduledoc """
  Does what `omarchy theme install <url>` does, into `priv/themes/extra/`:

      mix oma.add <git-url> [--name SLUG] [--ref REF]
      mix oma.add --local DIR [--name SLUG]

  The slug is derived from the repository name the way the installer
  derives it (`omarchy-` prefix and `-theme` suffix stripped, lowercased)
  unless `--name` is given. Built-in names are reserved. The repository is
  shallow-cloned to a temporary directory; its `colors.toml` is vendored,
  or a palette is derived from a legacy `alacritty.toml`. A `light.mode`
  marker is honoured. `index.json` gains an entry with the source commit.

  `--local DIR` reads a theme directory instead of cloning. `--priv DIR`
  targets another `priv/themes` (used by the tests).
  """

  use Mix.Task

  alias Mix.Tasks.Oma.Sync
  alias Oma.Palette
  alias Oma.Palette.Parser

  @switches [name: :string, ref: :string, local: :string, priv: :string]

  @impl true
  def run(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: @switches)
    if invalid != [], do: Mix.raise("unknown options: #{inspect(invalid)}")

    priv = opts[:priv] || Sync.priv_dir()

    {source_dir, repo, cleanup} =
      case {opts[:local], rest} do
        {dir, []} when is_binary(dir) -> {dir, nil, fn -> :ok end}
        {nil, [url]} -> clone(url, opts[:ref])
        _ -> Mix.raise("usage: mix oma.add <git-url> | mix oma.add --local DIR")
      end

    try do
      slug = opts[:name] || Oma.Slug.from_url(repo || Path.expand(source_dir))
      unless Oma.Slug.valid?(slug), do: Mix.raise("#{inspect(slug)} is not a usable theme name")

      builtin =
        priv
        |> Path.join("builtin/*.toml")
        |> Path.wildcard()
        |> Enum.map(&Path.basename(&1, ".toml"))

      if slug in builtin,
        do: Mix.raise("#{slug} is a built-in theme name; pick another with --name")

      {raw, source} = read_palette(source_dir)
      marker = File.exists?(Path.join(source_dir, "light.mode"))

      raw =
        if marker and not Map.has_key?(raw, "mode"), do: Map.put(raw, "mode", "light"), else: raw

      palette =
        case Palette.from_raw(raw, name: slug, tier: :extra) do
          {:ok, p} -> p
          {:error, errors} -> Mix.raise("#{slug}: invalid palette: #{inspect(errors)}")
        end

      out = Path.join(priv, "extra")
      File.mkdir_p!(out)
      File.write!(Path.join(out, slug <> ".toml"), Parser.encode(raw))

      commit = git_sha(source_dir)

      meta =
        %{
          "tier" => "extra",
          "name" => Oma.Slug.display(slug),
          "repo" => repo,
          "commit" => commit,
          "source" => source,
          "mode" => Atom.to_string(palette.mode),
          "hue" => Atom.to_string(Oma.Color.hue_bucket(palette.accent)),
          "complete" => palette.complete?,
          "added_at" => Date.to_iso8601(Date.utc_today())
        }
        |> Enum.reject(fn {_, v} -> is_nil(v) end)
        |> Map.new()

      index = Sync.read_index(priv)
      Sync.write_index(priv, Map.put(index, slug, meta))

      Mix.shell().info(
        "added #{slug} (#{palette.mode}, #{if palette.complete?, do: "complete", else: "partial"}, from #{source}) " <>
          "to #{Path.relative_to_cwd(out)}"
      )

      if palette.warnings != [], do: Mix.shell().info("  dropped: #{inspect(palette.warnings)}")
    after
      cleanup.()
    end
  end

  defp clone(url, ref) do
    if String.starts_with?(url, "-"), do: Mix.raise("refusing a URL that looks like a git option")

    tmp = Path.join(System.tmp_dir!(), "oma-add-#{System.unique_integer([:positive])}")
    branch = if ref, do: ["--branch", ref], else: []

    case System.cmd("git", ["clone", "--depth", "1", "--quiet"] ++ branch ++ ["--", url, tmp],
           stderr_to_stdout: true
         ) do
      {_, 0} -> {tmp, url, fn -> File.rm_rf!(tmp) end}
      {out, _} -> Mix.raise("git clone failed: #{String.trim(out)}")
    end
  end

  defp read_palette(dir) do
    colors = Path.join(dir, "colors.toml")
    alacritty = Path.join(dir, "alacritty.toml")

    cond do
      File.regular?(colors) ->
        {colors |> File.read!() |> Parser.parse(), "colors.toml"}

      File.regular?(alacritty) ->
        {alacritty |> File.read!() |> Oma.Palette.Alacritty.parse(), "alacritty.toml"}

      true ->
        Mix.raise("no colors.toml or alacritty.toml at the root of #{dir}")
    end
  end

  defp git_sha(dir) do
    case System.cmd("git", ["-C", dir, "rev-parse", "HEAD"], stderr_to_stdout: true) do
      {out, 0} -> String.trim(out)
      _ -> nil
    end
  end
end
