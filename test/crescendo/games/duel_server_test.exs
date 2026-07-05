defmodule Crescendo.Games.DuelServerTest do
  use Crescendo.DataCase, async: true

  alias Crescendo.Games.{DuelServer, Match}
  alias Crescendo.TestSupport.Payloads

  @p1 1
  @p2 2
  @correct Payloads.answer_index()
  @wrong @correct + 1

  # Each test spawns its own DuelServer with huge timers; phase transitions
  # driven by timers are triggered manually with `send/2`, so nothing sleeps.
  defp start_duel(opts \\ []) do
    match_id = Ecto.UUID.generate()
    test_pid = self()

    opts =
      Keyword.merge(
        [
          match_id: match_id,
          pool_id: 999,
          players: [@p1, @p2],
          timings: %{countdown_ms: 60_000, round_ms: 60_000, resolved_ms: 60_000},
          payload_fun: fn _pool_id -> Payloads.get_round_payload(nil) end,
          persist_fun: fn attrs ->
            send(test_pid, {:persisted, attrs})
            {:ok, attrs}
          end
        ],
        opts
      )

    pid = start_supervised!({DuelServer, opts})
    Phoenix.PubSub.subscribe(Crescendo.PubSub, "duel:" <> match_id)
    {match_id, pid}
  end

  # lobby ready ×2 (once per match) → round_loading + countdown → playing
  defp to_playing({match_id, pid}, round_no) do
    :ok = DuelServer.player_ready(match_id, @p1)
    :ok = DuelServer.player_ready(match_id, @p2)
    assert_receive {:duel_event, :all_ready, _}
    assert_receive {:duel_event, :round_loading, %{round_no: ^round_no}}
    assert_receive {:duel_event, :countdown, %{round_no: ^round_no, start_at: _}}
    send(pid, {:countdown_over, round_no})
    # a synchronous call guarantees the countdown_over message was processed
    {:ok, true} = DuelServer.participant?(match_id, @p1)
    :ok
  end

  test "first correct answer to reach the mailbox wins the round" do
    {match_id, _pid} = duel = start_duel()
    to_playing(duel, 1)

    assert {:ok, :correct} = DuelServer.submit_answer(match_id, @p1, @correct)
    # round already resolved — the second correct answer bounces off
    assert {:error, :not_playing} = DuelServer.submit_answer(match_id, @p2, @correct)

    assert_receive {:duel_event, :round_result,
                    %{winner: @p1, correct_index: @correct, scores: %{@p1 => 1, @p2 => 0}}}
  end

  test "a wrong answer locks the player; their second attempt is rejected" do
    {match_id, _pid} = duel = start_duel()
    to_playing(duel, 1)

    assert {:ok, :locked} = DuelServer.submit_answer(match_id, @p1, @wrong)
    assert {:error, :locked} = DuelServer.submit_answer(match_id, @p1, @correct)

    # the round is still open for the other player
    refute_receive {:duel_event, :round_result, _}, 20
    assert {:ok, :correct} = DuelServer.submit_answer(match_id, @p2, @correct)
    assert_receive {:duel_event, :round_result, %{winner: @p2}}
  end

  test "two wrong answers close the round as a draw" do
    {match_id, _pid} = duel = start_duel()
    to_playing(duel, 1)

    assert {:ok, :locked} = DuelServer.submit_answer(match_id, @p1, @wrong)
    assert {:ok, :locked} = DuelServer.submit_answer(match_id, @p2, @wrong)

    assert_receive {:duel_event, :round_result, %{winner: nil, scores: %{@p1 => 0, @p2 => 0}}}
  end

  test "timeout closes the round; a stale round_no timeout is a no-op" do
    {match_id, pid} = duel = start_duel()
    to_playing(duel, 1)

    # stale timer from a previous round generation: ignored
    send(pid, {:round_timeout, 0})
    refute_receive {:duel_event, :round_result, _}, 20
    assert :sys.get_state(pid).phase == :playing

    send(pid, {:round_timeout, 1})
    assert_receive {:duel_event, :round_result, %{winner: nil}}
    assert {:error, :not_playing} = DuelServer.submit_answer(match_id, @p1, @correct)
  end

  test "submit_answer outside :playing is rejected" do
    {match_id, _pid} = start_duel()

    # :lobby
    assert {:error, :not_playing} = DuelServer.submit_answer(match_id, @p1, @correct)

    :ok = DuelServer.player_ready(match_id, @p1)
    :ok = DuelServer.player_ready(match_id, @p2)
    assert_receive {:duel_event, :round_loading, _}
    assert_receive {:duel_event, :countdown, _}

    # :countdown
    assert {:error, :not_playing} = DuelServer.submit_answer(match_id, @p1, @correct)

    # ready is once per match — a second one is rejected, not re-processed
    assert {:error, :not_ready_phase} = DuelServer.player_ready(match_id, @p1)
  end

  test "finished match is written to the matches table" do
    {:ok, pool} =
      Crescendo.MusicCatalog.create_pool(%{
        slug: "t-#{System.unique_integer([:positive])}",
        name: "T",
        type: "genre"
      })

    {:ok, u1} =
      Crescendo.Accounts.create_user(%{
        game_center_id: "gc-#{System.unique_integer()}",
        display_name: "A"
      })

    {:ok, u2} =
      Crescendo.Accounts.create_user(%{
        game_center_id: "gc-#{System.unique_integer()}",
        display_name: "B"
      })

    match_id = Ecto.UUID.generate()

    pid =
      start_supervised!(
        {Crescendo.Games.DuelServer,
         match_id: match_id,
         pool_id: pool.id,
         players: [u1.id, u2.id],
         timings: %{countdown_ms: 60_000, round_ms: 60_000, resolved_ms: 60_000},
         payload_fun: fn _ -> Crescendo.TestSupport.Payloads.get_round_payload(nil) end}
      )

    Ecto.Adapters.SQL.Sandbox.allow(Crescendo.Repo, self(), pid)
    Phoenix.PubSub.subscribe(Crescendo.PubSub, "duel:" <> match_id)
    ref = Process.monitor(pid)

    # u1 wins rounds 1-3 → 3:0, match over
    :ok = DuelServer.player_ready(match_id, u1.id)
    :ok = DuelServer.player_ready(match_id, u2.id)

    for round_no <- 1..3 do
      assert_receive {:duel_event, :round_loading, %{round_no: ^round_no}}
      assert_receive {:duel_event, :countdown, _}
      send(pid, {:countdown_over, round_no})
      assert {:ok, :correct} = DuelServer.submit_answer(match_id, u1.id, @correct)
      assert_receive {:duel_event, :round_result, _}
      if round_no < 3, do: send(pid, {:next_round, round_no})
    end

    winner_id = u1.id
    assert_receive {:duel_event, :match_over, %{winner: ^winner_id}}
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

    match = Repo.get_by!(Match, player_a: u1.id, player_b: u2.id)
    assert match.winner_id == u1.id
    assert match.pool_id == pool.id
    assert length(match.rounds) == 3
    assert Enum.all?(match.rounds, &(&1["winner_id"] == u1.id))
    assert match.finished_at
  end
end
