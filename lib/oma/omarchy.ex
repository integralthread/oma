defmodule Oma.Omarchy do
  @moduledoc """
  The built-in themes of `omacom/omarchy`, read without cloning the repo.

  The checkout is over 300 MB, almost all of it history and background
  images, while the built-ins are 22 small `colors.toml` files. `fetch/1`
  resolves the branch to a commit and lists its tree through the GitHub
  API (two requests), then reads each `themes/<name>/colors.toml` from
  `raw.githubusercontent.com` pinned to that commit. `from_dir/1` reads
  the same thing from a local checkout for offline use.

  Both return `{:ok, %Oma.Omarchy{}}` whose `themes` map each name to the
  vendored content: the file verbatim, except that a `light.mode` marker
  with no `mode` key becomes an explicit `mode = "light"` so the vendored
  file stands alone.

  The GitHub API allows 60 anonymous requests an hour per address; set
  `GITHUB_TOKEN` (or `GH_TOKEN`) to raise that.
  """

  alias Oma.Palette.Parser

  @repo "omacom/omarchy"
  @branch "quattro"
  @api "https://api.github.com"
  @raw "https://raw.githubusercontent.com"

  @type t :: %__MODULE__{commit: String.t(), themes: %{String.t() => String.t()}}

  defstruct [:commit, themes: %{}]

  def repo, do: @repo
  def repo_url, do: "https://github.com/" <> @repo
  def branch, do: @branch

  @doc """
  Fetch the built-ins over HTTPS.

  Options: `:ref` (branch, tag or commit, default `branch/0`), `:repo`
  (`owner/name`, default `repo/0`), `:api_base` and `:raw_base` for
  tests.
  """
  @spec fetch(keyword) :: {:ok, t} | {:error, term}
  def fetch(opts \\ []) do
    repo = Keyword.get(opts, :repo, @repo)
    ref = Keyword.get(opts, :ref, @branch)
    api = opts |> Keyword.get(:api_base, @api) |> String.trim_trailing("/")
    raw = opts |> Keyword.get(:raw_base, @raw) |> String.trim_trailing("/")

    with {:ok, commit} <- resolve(api, repo, ref),
         {:ok, paths} <- tree(api, repo, commit),
         {:ok, themes} <- fetch_themes(raw, repo, commit, theme_files(paths)) do
      {:ok, %__MODULE__{commit: commit, themes: themes}}
    end
  end

  @doc "Read the built-ins from a local checkout."
  @spec from_dir(Path.t()) :: {:ok, t} | {:error, term}
  def from_dir(dir) do
    themes_dir = Path.join(dir, "themes")

    if File.dir?(themes_dir) do
      themes =
        themes_dir
        |> Path.join("*/colors.toml")
        |> Path.wildcard()
        |> Map.new(fn path ->
          name = path |> Path.dirname() |> Path.basename()
          light? = path |> Path.dirname() |> Path.join("light.mode") |> File.exists?()
          {name, content(File.read!(path), light?)}
        end)

      case System.cmd("git", ["-C", dir, "rev-parse", "HEAD"], stderr_to_stdout: true) do
        {out, 0} -> {:ok, %__MODULE__{commit: String.trim(out), themes: themes}}
        {out, _} -> {:error, {:git, String.trim(out)}}
      end
    else
      {:error, {:no_themes_dir, themes_dir}}
    end
  end

  @doc """
  The theme files in a list of repository paths: `%{name => %{colors:
  path, light?: boolean}}` for every `themes/<name>/colors.toml`.
  """
  @spec theme_files([String.t()]) :: %{String.t() => %{colors: String.t(), light?: boolean}}
  def theme_files(paths) do
    set = MapSet.new(paths)

    for "themes/" <> rest <- paths,
        [name, "colors.toml"] <- [String.split(rest, "/")],
        into: %{} do
      light? = MapSet.member?(set, "themes/#{name}/light.mode")
      {name, %{colors: "themes/#{name}/colors.toml", light?: light?}}
    end
  end

  @doc "The vendored content of a `colors.toml`, given whether a `light.mode` marker sits beside it."
  @spec content(binary, boolean) :: binary
  def content(colors, light?) do
    if light? and not Map.has_key?(Parser.parse(colors), "mode") do
      ~s(mode = "light"\n\n) <> colors
    else
      colors
    end
  end

  # -- GitHub ------------------------------------------------------------------

  defp resolve(api, repo, ref) do
    case api_get("#{api}/repos/#{repo}/commits/#{ref}") do
      {:ok, %{"sha" => sha}} when is_binary(sha) -> {:ok, sha}
      {:ok, _} -> {:error, {:unexpected_response, :commit}}
      error -> error
    end
  end

  defp tree(api, repo, commit) do
    case api_get("#{api}/repos/#{repo}/git/trees/#{commit}?recursive=1") do
      {:ok, %{"truncated" => true}} -> {:error, :tree_truncated}
      {:ok, %{"tree" => entries}} when is_list(entries) -> {:ok, Enum.map(entries, & &1["path"])}
      {:ok, _} -> {:error, {:unexpected_response, :tree}}
      error -> error
    end
  end

  defp fetch_themes(raw, repo, commit, files) do
    files
    |> Enum.sort()
    |> Task.async_stream(
      fn {name, %{colors: path, light?: light?}} ->
        case Oma.HTTP.get("#{raw}/#{repo}/#{commit}/#{path}") do
          {:ok, body} -> {:ok, {name, content(body, light?)}}
          {:error, reason} -> {:error, {name, reason}}
        end
      end,
      max_concurrency: 8,
      ordered: true,
      timeout: 120_000
    )
    |> Enum.reduce_while({:ok, %{}}, fn
      {:ok, {:ok, {name, body}}}, {:ok, acc} -> {:cont, {:ok, Map.put(acc, name, body)}}
      {:ok, {:error, reason}}, _ -> {:halt, {:error, reason}}
      {:exit, reason}, _ -> {:halt, {:error, {:exit, reason}}}
    end)
  end

  defp api_get(url) do
    headers = [{"accept", "application/vnd.github+json"} | auth_header()]

    case Oma.HTTP.get(url, headers: headers) do
      {:ok, body} ->
        case JSON.decode(body) do
          {:ok, map} when is_map(map) -> {:ok, map}
          {:ok, _} -> {:error, {:unexpected_response, url}}
          {:error, reason} -> {:error, {:json, reason, url}}
        end

      {:error, {:status, status, _}} when status in [403, 429] ->
        {:error, {:rate_limited, url}}

      error ->
        error
    end
  end

  defp auth_header do
    case System.get_env("GITHUB_TOKEN") || System.get_env("GH_TOKEN") do
      nil -> []
      "" -> []
      token -> [{"authorization", "Bearer " <> token}]
    end
  end
end
