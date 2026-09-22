defmodule Oma.HTTP do
  @moduledoc """
  Minimal HTTPS GET on top of `:httpc` with certificate verification, so the
  sync and add tasks need no dependencies and work from a consumer's
  `deps/` directory as well as from this repository.
  """

  @doc """
  GET a URL and return the body on a 200.

  Options: `:headers` (a list of `{name, value}` strings, added to the
  defaults; a caller's `accept` replaces the default), `:timeout`,
  `:connect_timeout`.
  """
  @spec get(String.t(), keyword) :: {:ok, binary} | {:error, term}
  def get(url, opts \\ []) do
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    extra = for {k, v} <- Keyword.get(opts, :headers, []), do: {String.downcase(k), v}

    headers =
      [{"user-agent", "oma (Elixir httpc)"}, {"accept", "*/*"}]
      |> Enum.reject(fn {k, _} -> List.keymember?(extra, k, 0) end)
      |> Kernel.++(extra)
      |> Enum.map(fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    http_opts = [
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        depth: 3,
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      ],
      timeout: Keyword.get(opts, :timeout, 60_000),
      connect_timeout: Keyword.get(opts, :connect_timeout, 15_000),
      autoredirect: true
    ]

    case :httpc.request(:get, {String.to_charlist(url), headers}, http_opts, body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} -> {:ok, body}
      {:ok, {{_, status, _}, _headers, _body}} -> {:error, {:status, status, url}}
      {:error, reason} -> {:error, {reason, url}}
    end
  end
end
