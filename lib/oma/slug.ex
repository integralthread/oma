defmodule Oma.Slug do
  @moduledoc """
  Theme names as Omarchy derives them.

  `from_url/1` mirrors `bin/omarchy-theme-install`: strip an scp-style
  `user@host:` prefix, take the path's basename without `.git`, drop a
  leading `omarchy-` and a trailing `-theme`, lowercase. `valid?/1` is the
  character rule the installer enforces on the result.
  """

  @slug_re ~r/^[a-z0-9_][a-z0-9._+-]*$/

  @doc "Derive the theme slug from a git URL."
  @spec from_url(String.t()) :: String.t()
  def from_url(url) when is_binary(url) do
    path = String.trim(url)

    path =
      if not String.contains?(path, "://") and String.contains?(path, ":") and
           not (path |> String.split(":", parts: 2) |> hd() |> String.contains?("/")) do
        path |> String.split(":", parts: 2) |> List.last()
      else
        path
      end

    path
    |> String.trim_trailing("/")
    |> String.split("/")
    |> List.last()
    |> String.replace_suffix(".git", "")
    |> String.replace_prefix("omarchy-", "")
    |> String.replace_suffix("-theme", "")
    |> String.downcase()
  end

  @doc "True when the slug satisfies the upstream installer's character rule."
  @spec valid?(term) :: boolean
  def valid?(slug) when is_binary(slug), do: Regex.match?(@slug_re, slug)
  def valid?(_), do: false

  @doc ~S"""
  Display name the way `omarchy-theme-list` prints it: hyphens to spaces,
  each word capitalised.

      iex> Oma.Slug.display("tokyo-night")
      "Tokyo Night"
  """
  @spec display(String.t()) :: String.t()
  def display(slug) do
    slug
    |> String.split("-")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
