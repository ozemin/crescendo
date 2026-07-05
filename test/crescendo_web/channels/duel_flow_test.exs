defmodule CrescendoWeb.DuelFlowTest do
  @moduledoc """
  End-to-end: two simulated players match up, play 5 rounds (A-B-A-B-A → 3:2)
  and receive match_over; the finished match lands in the matches table.

  async: false — matchmaking/duel processes share the test's sandbox
  connection via shared mode. Both players' channels push into this test
  process's mailbox, so every broadcast event is asserted twice.
  """

  use CrescendoWeb.ChannelCase, async: false

  alias Crescendo.Games.Match
  alias Crescendo.Repo
  alias Crescendo.TestSupport.Payloads
  alias CrescendoWeb.UserSocket

  @correct Payloads.answer_index()

  setup do
    {:ok, pool} =
      Crescendo.MusicCatalog.create_pool(%{
        slug: "e2e-#{System.unique_integer([:positive])}",
        name: "E2E",
        type: "genre"
      })

    {:ok, a} =
      Crescendo.Accounts.create_user(%{
        game_center_id: "gc-e2e-a-#{System.unique_integer()}",
        display_name: "A"
      })

    {:ok, b} =
      Crescendo.Accounts.create_user(%{
        game_center_id: "gc-e2e-b-#{System.unique_integer()}",
        display_name: "B"
      })

    %{pool: pool, a: a, b: b}
  end

  test "matchmaking → 5 rounds → match_over → persisted match", %{pool: pool, a: a, b: b} do
    {:ok, socket_a} = connect(UserSocket, %{"user_id" => a.id})
    {:ok, socket_b} = connect(UserSocket, %{"user_id" => b.id})

    # -- matchmaking ---------------------------------------------------------
    {:ok, _, mm_a} = subscribe_and_join(socket_a, "matchmaking:lobby", %{})
    ref = push(mm_a, "join_pool", %{"pool" => pool.slug})
    assert_reply ref, :ok, %{status: "queued"}

    {:ok, _, mm_b} = subscribe_and_join(socket_b, "matchmaking:lobby", %{})
    ref = push(mm_b, "join_pool", %{"pool" => pool.slug})
    assert_reply ref, :ok, %{status: "matched"}

    assert_push "matched", %{match_id: match_id}
    assert_push "matched", %{match_id: ^match_id}

    # -- join the duel, signal lobby-ready -----------------------------------
    {:ok, _, duel_a} = subscribe_and_join(socket_a, "duel:" <> match_id, %{})
    {:ok, _, duel_b} = subscribe_and_join(socket_b, "duel:" <> match_id, %{})

    ref_a = push(duel_a, "ready", %{})
    ref_b = push(duel_b, "ready", %{})
    assert_reply ref_a, :ok
    assert_reply ref_b, :ok

    # ready is once per match: both in → all_ready, then rounds flow on their own
    assert_push "all_ready", %{}
    assert_push "all_ready", %{}

    # -- 5 rounds, alternating winners: A B A B A → 3:2 ----------------------
    a_id = a.id
    b_id = b.id

    script = [
      {1, duel_a, a_id},
      {2, duel_b, b_id},
      {3, duel_a, a_id},
      {4, duel_b, b_id},
      {5, duel_a, a_id}
    ]

    for {round_no, winner_channel, winner_id} <- script do
      # one push per player channel for every broadcast
      assert_push "round_loading",
                  %{round_no: ^round_no, preview_url: _, artwork_url: _, options: options},
                  1_000

      assert_push "round_loading", %{round_no: ^round_no}, 1_000
      assert length(options) == 4

      assert_push "countdown", %{round_no: ^round_no, start_at: start_at}
      assert_push "countdown", %{round_no: ^round_no}
      assert is_integer(start_at)

      assert {:ok, %{result: "correct"}} = submit_when_playing(winner_channel, @correct)

      assert_push "round_result",
                  %{round_no: ^round_no, winner: ^winner_id, correct_index: @correct, scores: _},
                  1_000

      assert_push "round_result", %{round_no: ^round_no, winner: ^winner_id}, 1_000
    end

    assert_push "match_over", %{winner: ^a_id, scores: scores}, 1_000
    assert_push "match_over", %{winner: ^a_id}, 1_000
    assert scores[a_id] == 3 and scores[b_id] == 2

    # persisted before match_over was broadcast
    match = Repo.get_by!(Match, player_a: a_id, player_b: b_id)
    assert match.winner_id == a_id
    assert match.pool_id == pool.id
    assert length(match.rounds) == 5
  end

  # The server never announces :playing (clients schedule against start_at),
  # so retry while the reply is not_playing — the countdown is 50ms in test.
  defp submit_when_playing(channel, index, attempts \\ 50)

  defp submit_when_playing(_channel, _index, 0), do: flunk("round never reached :playing")

  defp submit_when_playing(channel, index, attempts) do
    ref = push(channel, "answer", %{"index" => index})

    receive do
      %Phoenix.Socket.Reply{ref: ^ref, status: :ok, payload: payload} ->
        {:ok, payload}

      %Phoenix.Socket.Reply{ref: ^ref, status: :error, payload: %{reason: "not_playing"}} ->
        Process.sleep(10)
        submit_when_playing(channel, index, attempts - 1)
    after
      1_000 -> flunk("no reply to answer push")
    end
  end
end
