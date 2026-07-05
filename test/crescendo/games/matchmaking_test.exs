defmodule Crescendo.Games.MatchmakingTest do
  use Crescendo.DataCase, async: true

  alias Crescendo.Games.{DuelServer, Matchmaking}
  alias Crescendo.MusicCatalog

  defp create_pool do
    {:ok, pool} =
      MusicCatalog.create_pool(%{
        slug: "mm-#{System.unique_integer([:positive])}",
        name: "MM",
        type: "genre"
      })

    pool
  end

  test "first player queues, second player matches; both get the same match_id" do
    pool = create_pool()

    assert {:ok, :queued} = Matchmaking.join(pool.slug, 1, self())
    assert {:ok, {:matched, match_id}} = Matchmaking.join(pool.slug, 2, self())

    # the waiting player's channel is notified
    assert_receive {:matched, ^match_id}
    assert DuelServer.whereis(match_id) != nil
  end

  test "waiting player is dropped from the queue when their channel dies" do
    pool = create_pool()

    fake_channel = spawn(fn -> Process.sleep(:infinity) end)
    assert {:ok, :queued} = Matchmaking.join(pool.slug, 1, fake_channel)

    Process.exit(fake_channel, :kill)
    # give the queue a moment to process :DOWN, then join: must queue, not match
    Process.sleep(20)
    assert {:ok, :queued} = Matchmaking.join(pool.slug, 2, self())
    refute_receive {:matched, _}, 20
  end

  test "unknown pool is rejected" do
    assert {:error, :unknown_pool} = Matchmaking.join("no-such-pool", 1, self())
  end
end
