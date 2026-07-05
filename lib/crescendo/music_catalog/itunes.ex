defmodule Crescendo.MusicCatalog.ITunes do
  @moduledoc """
  Thin Req client for the iTunes Search API (no auth, ~20 req/min — callers
  are responsible for rate limiting between requests).

  Tests inject `plug: {Req.Test, __MODULE__}` via config so no request ever
  hits the network. iTunes answers with `text/javascript`, so the JSON body is
  decoded manually when Req leaves it as a binary.
  """

  @base_url "https://itunes.apple.com"

  @doc "Search songs. Returns `{:ok, results}` with raw iTunes result maps."
  def search(term, opts \\ []) do
    params =
      %{
        term: term,
        media: "music",
        entity: "song",
        limit: opts[:limit] || 50,
        offset: opts[:offset] || 0
      }
      |> maybe_put(:attribute, opts[:attribute])

    request(url: "/search", params: params)
  end

  @doc "Lookup tracks by Apple track ids. Ids missing from results are gone (404)."
  def lookup(ids) when is_list(ids) do
    request(url: "/lookup", params: %{id: Enum.join(ids, ","), entity: "song"})
  end

  defp request(opts) do
    injected = Application.get_env(:crescendo, __MODULE__, [])

    case Req.request([base_url: @base_url, retry: false] ++ injected ++ opts) do
      {:ok, %Req.Response{status: 200, body: body}} -> decode(body)
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode(%{"results" => results}), do: {:ok, results}

  defp decode(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"results" => results}} -> {:ok, results}
      _ -> {:error, :invalid_body}
    end
  end

  defp decode(_), do: {:error, :invalid_body}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
