defmodule Crescendo.MusicCatalog do
  @moduledoc """
  Track pools and round payloads.

  Seeding (`mix catalog.seed <slug>`) pulls songs from the iTunes Search API,
  normalizes titles to drop live/remix/karaoke duplicates, and upserts them.
  `get_round_payload/1` picks a random track plus 3 distractors from the same
  pool — preview/artwork URLs ship in the payload so the client never talks to
  Apple, and the correct answer never leaves the server before `round_result`.
  """

  import Ecto.Query

  alias Crescendo.MusicCatalog.{ITunes, Pool, Track}
  alias Crescendo.Repo

  @variant_re ~r/\b(live|remix|remixed|karaoke|acoustic|instrumental|unplugged|demo|tribute|cover|remaster(ed)?)\b/i

  ## Pools

  def get_pool_by_slug(slug), do: Repo.get_by(Pool, slug: slug, active: true)

  def create_pool(attrs) do
    %Pool{}
    |> Pool.changeset(attrs)
    |> Repo.insert()
  end

  ## Round payloads

  @doc """
  Random track + 3 distractors from the same pool. Options are shuffled
  `%{title, artist}` maps; `answer_index` stays server-side.
  """
  def get_round_payload(pool_id) do
    tracks =
      Repo.all(
        from t in Track,
          where: t.pool_id == ^pool_id and t.active == true,
          order_by: fragment("RANDOM()"),
          limit: 4
      )

    case tracks do
      [answer | _] = four when length(four) == 4 ->
        shuffled = Enum.shuffle(four)

        {:ok,
         %{
           track: answer,
           options: Enum.map(shuffled, &%{title: &1.title, artist: &1.artist_name}),
           answer_index: Enum.find_index(shuffled, &(&1.id == answer.id))
         }}

      _ ->
        {:error, :not_enough_tracks}
    end
  end

  ## Seeding

  @doc """
  Fill a pool from iTunes search. Paginates with `Process.sleep` between
  requests (single-process one-off task — deliberate, see CLAUDE.md).
  Returns `{:ok, upserted_count}`.
  """
  def seed_pool(%Pool{} = pool, opts \\ []) do
    pages = opts[:pages] || 4
    per_page = opts[:per_page] || 50
    sleep_ms = Keyword.get(opts, :sleep_ms, 3_500)
    search_opts = if pool.type == "artist", do: [attribute: "artistTerm"], else: []

    results =
      0..(pages - 1)
      |> Enum.flat_map(fn page ->
        if page > 0, do: Process.sleep(sleep_ms)

        case ITunes.search(pool.name, search_opts ++ [limit: per_page, offset: page * per_page]) do
          {:ok, results} -> results
          {:error, _} -> []
        end
      end)

    now = DateTime.utc_now(:second)

    tracks =
      results
      |> Enum.filter(&playable?/1)
      |> Enum.reject(&variant?(&1["trackName"]))
      |> Enum.uniq_by(&normalize_title(&1["trackName"]))
      |> Enum.map(fn r ->
        %{
          pool_id: pool.id,
          apple_track_id: r["trackId"],
          title: r["trackName"],
          artist_name: r["artistName"],
          preview_url: r["previewUrl"],
          artwork_url: r["artworkUrl100"],
          fetched_at: now,
          active: true,
          inserted_at: now,
          updated_at: now
        }
      end)

    {count, _} =
      Repo.insert_all(Track, tracks,
        on_conflict:
          {:replace,
           [:title, :artist_name, :preview_url, :artwork_url, :fetched_at, :active, :updated_at]},
        conflict_target: [:pool_id, :apple_track_id]
      )

    {:ok, count}
  end

  defp playable?(result) do
    result["kind"] == "song" and is_binary(result["previewUrl"]) and is_integer(result["trackId"])
  end

  @doc """
  Dedupe key for a track title: lowercased, parentheticals and ` - Suffix`
  qualifiers stripped ("Song (Live)", "Song - 2011 Remaster" → "song").
  """
  def normalize_title(title) do
    title
    |> String.downcase()
    |> String.replace(~r/\s*[(\[][^)\]]*[)\]]/, "")
    |> String.split(" - ")
    |> hd()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @doc "True for live/remix/karaoke/etc. variants that must not enter a pool."
  def variant?(title), do: Regex.match?(@variant_re, title)

  ## Refresh (used by the weekly Oban worker)

  def stale_tracks(cutoff) do
    Repo.all(from t in Track, where: t.active == true and t.fetched_at < ^cutoff)
  end

  def refresh_tracks(tracks, chunk_size \\ 100) do
    tracks
    |> Enum.chunk_every(chunk_size)
    |> Enum.each(fn chunk ->
      case ITunes.lookup(Enum.map(chunk, & &1.apple_track_id)) do
        {:ok, results} ->
          found = Map.new(results, &{&1["trackId"], &1})
          Enum.each(chunk, &apply_refresh(&1, found[&1.apple_track_id]))

        {:error, _} ->
          # transient API failure: leave the chunk for the next weekly run
          :ok
      end
    end)
  end

  # iTunes no longer knows the track (404 / missing from lookup) → deactivate
  defp apply_refresh(track, nil) do
    track |> Track.changeset(%{active: false}) |> Repo.update()
  end

  defp apply_refresh(track, result) do
    track
    |> Track.changeset(%{
      preview_url: result["previewUrl"] || track.preview_url,
      artwork_url: result["artworkUrl100"] || track.artwork_url,
      fetched_at: DateTime.utc_now(:second)
    })
    |> Repo.update()
  end
end
