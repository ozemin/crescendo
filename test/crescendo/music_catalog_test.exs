defmodule Crescendo.MusicCatalogTest do
  use Crescendo.DataCase, async: true
  use Oban.Testing, repo: Crescendo.Repo

  alias Crescendo.MusicCatalog
  alias Crescendo.MusicCatalog.{ITunes, RefreshWorker, Track}

  defp create_pool(type \\ "genre") do
    {:ok, pool} =
      MusicCatalog.create_pool(%{
        slug: "cat-#{System.unique_integer([:positive])}",
        name: "Cat",
        type: type
      })

    pool
  end

  defp insert_track!(pool, attrs) do
    defaults = %{
      pool_id: pool.id,
      apple_track_id: System.unique_integer([:positive]),
      title: "Song #{System.unique_integer([:positive])}",
      artist_name: "Artist",
      preview_url: "https://example.com/p.m4a",
      artwork_url: "https://example.com/a.jpg",
      fetched_at: DateTime.utc_now(:second)
    }

    %Track{} |> Track.changeset(Map.merge(defaults, attrs)) |> Repo.insert!()
  end

  describe "normalize_title/1 and variant?/1" do
    test "strips parentheticals and dash qualifiers" do
      assert MusicCatalog.normalize_title("Song (Live at Wembley)") == "song"
      assert MusicCatalog.normalize_title("Song - 2011 Remaster") == "song"
      assert MusicCatalog.normalize_title("Song [Karaoke Version]") == "song"
      assert MusicCatalog.normalize_title("  Song  Title ") == "song title"
    end

    test "flags live/remix/karaoke variants" do
      assert MusicCatalog.variant?("Song (Live)")
      assert MusicCatalog.variant?("Song - Club Remix")
      assert MusicCatalog.variant?("Song (Karaoke Version)")
      refute MusicCatalog.variant?("Livin' on a Prayer")
      refute MusicCatalog.variant?("Plain Song")
    end
  end

  describe "get_round_payload/1" do
    test "returns a random track, 4 shuffled options and the answer index" do
      pool = create_pool()
      for _ <- 1..6, do: insert_track!(pool, %{})

      assert {:ok, %{track: track, options: options, answer_index: idx}} =
               MusicCatalog.get_round_payload(pool.id)

      assert length(options) == 4
      assert idx in 0..3
      assert Enum.at(options, idx) == %{title: track.title, artist: track.artist_name}
      assert options == Enum.uniq(options)
    end

    test "inactive tracks never enter a round" do
      pool = create_pool()
      for _ <- 1..4, do: insert_track!(pool, %{active: false})

      assert {:error, :not_enough_tracks} = MusicCatalog.get_round_payload(pool.id)
    end
  end

  describe "seed_pool/2" do
    test "upserts deduped, variant-free tracks from iTunes search" do
      pool = create_pool("artist")

      results = [
        song(1, "Bohemian Rhapsody"),
        song(2, "Bohemian Rhapsody (Live at Wembley)"),
        song(3, "Bohemian Rhapsody - 2011 Remaster"),
        song(4, "Under Pressure"),
        Map.delete(song(5, "No Preview"), "previewUrl"),
        song(6, "Under Pressure (Karaoke Version)")
      ]

      Req.Test.stub(ITunes, fn conn ->
        Req.Test.json(conn, %{"resultCount" => length(results), "results" => results})
      end)

      assert {:ok, 2} = MusicCatalog.seed_pool(pool, pages: 1, sleep_ms: 0)

      titles = Repo.all(from t in Track, where: t.pool_id == ^pool.id, select: t.title)
      assert Enum.sort(titles) == ["Bohemian Rhapsody", "Under Pressure"]
    end
  end

  describe "RefreshWorker" do
    test "refreshes stale tracks and deactivates ones missing from lookup" do
      pool = create_pool()
      old = DateTime.add(DateTime.utc_now(:second), -10, :day)

      stale_kept = insert_track!(pool, %{apple_track_id: 100, fetched_at: old})
      stale_gone = insert_track!(pool, %{apple_track_id: 200, fetched_at: old})

      fresh =
        insert_track!(pool, %{apple_track_id: 300, preview_url: "https://example.com/fresh.m4a"})

      Req.Test.stub(ITunes, fn conn ->
        # lookup only returns track 100 → 200 is gone from iTunes
        Req.Test.json(conn, %{
          "resultCount" => 1,
          "results" => [song(100, "Kept", "https://example.com/new.m4a")]
        })
      end)

      assert :ok = perform_job(RefreshWorker, %{})

      assert Repo.get!(Track, stale_kept.id).preview_url == "https://example.com/new.m4a"
      refute Repo.get!(Track, stale_gone.id).active
      # fresh track untouched
      assert Repo.get!(Track, fresh.id).preview_url == "https://example.com/fresh.m4a"
    end
  end

  defp song(id, title, preview \\ "https://example.com/p.m4a") do
    %{
      "wrapperType" => "track",
      "kind" => "song",
      "trackId" => id,
      "trackName" => title,
      "artistName" => "Queen",
      "previewUrl" => preview,
      "artworkUrl100" => "https://example.com/a.jpg"
    }
  end
end
