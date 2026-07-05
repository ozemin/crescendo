defmodule Crescendo.Games.DuelServer do
  @moduledoc """
  Holds ALL live state of one best-of-5 duel. The database is only touched at
  `:finished` (match persistence) and when loading a round payload between
  rounds — never while a round is in play.

  ## State

    * `players` — `%{player_id => %{score, ready, locked}}` (two entries)
    * `round` — `%{track, options, answer_index, answered}` for the current round
    * `round_no` — 1..5; baked into every timer message so stale timers are ignored
    * `rounds` — accumulated per-round summaries, persisted as jsonb at the end

  ## Phase transitions

      :lobby      --both ready (once per match)--> :countdown
      :countdown  --timer-------------> :playing   (round timeout armed)
      :playing    --first correct / both wrong / timeout--> :resolved (round_result broadcast)
      :resolved   --timer-------------> :countdown (next round)  |  :finished
      :finished   --persist match, broadcast match_over, {:stop, :normal}

  `player_ready/2` is sent exactly once per player, in `:lobby`. The
  `:loading` step is transient: the payload fetch happens synchronously inside
  the transition into `:countdown`, which broadcasts `round_loading` and
  `countdown(start_at)` back to back — the countdown buffer doubles as the
  client's window to download the preview.

  Ordering guarantee: the GenServer mailbox. Every mutation goes through
  `GenServer.call`; the first correct `submit_answer` to reach the mailbox
  wins the round. No extra locks. Restart is `:temporary`.
  """

  use GenServer, restart: :temporary

  alias Crescendo.Games

  @best_of 5
  @needed_wins div(@best_of, 2) + 1

  defstruct [
    :match_id,
    :pool_id,
    :player_order,
    :players,
    :round,
    :timings,
    :payload_fun,
    :persist_fun,
    phase: :lobby,
    round_no: 0,
    rounds: []
  ]

  ## Client API — always addressed via Registry, never by pid

  def via(match_id), do: {:via, Registry, {Crescendo.Registry, match_id}}

  def whereis(match_id) do
    case Registry.lookup(Crescendo.Registry, match_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: via(Keyword.fetch!(opts, :match_id)))
  end

  def player_ready(match_id, player_id), do: safe_call(match_id, {:player_ready, player_id})

  def submit_answer(match_id, player_id, index),
    do: safe_call(match_id, {:submit_answer, player_id, index})

  def participant?(match_id, player_id), do: safe_call(match_id, {:participant?, player_id})

  defp safe_call(match_id, msg) do
    try do
      GenServer.call(via(match_id), msg)
    catch
      :exit, {:noproc, _} -> {:error, :match_not_found}
    end
  end

  ## Server

  @impl true
  def init(opts) do
    [a, b] = Keyword.fetch!(opts, :players)
    config = Application.get_env(:crescendo, :duel, [])
    timings = Map.merge(config_timings(config), Keyword.get(opts, :timings, %{}))

    {:ok,
     %__MODULE__{
       match_id: Keyword.fetch!(opts, :match_id),
       pool_id: Keyword.fetch!(opts, :pool_id),
       player_order: [a, b],
       players: %{a => new_player(), b => new_player()},
       timings: timings,
       payload_fun: Keyword.get(opts, :payload_fun, mfa_fun(config[:payload_mfa])),
       persist_fun: Keyword.get(opts, :persist_fun, &Games.persist_match/1)
     }}
  end

  @impl true
  def handle_call({:participant?, player_id}, _from, state) do
    {:reply, {:ok, Map.has_key?(state.players, player_id)}, state}
  end

  def handle_call({:player_ready, player_id}, _from, state) do
    cond do
      not Map.has_key?(state.players, player_id) ->
        {:reply, {:error, :unknown_player}, state}

      state.phase != :lobby ->
        {:reply, {:error, :not_ready_phase}, state}

      true ->
        state = put_in(state.players[player_id].ready, true)

        if Enum.all?(state.players, fn {_id, p} -> p.ready end) do
          broadcast(state, :all_ready, %{})

          case start_round(state) do
            {:noreply, state} -> {:reply, :ok, state}
            {:stop, :normal, state} -> {:stop, :normal, :ok, state}
          end
        else
          {:reply, :ok, state}
        end
    end
  end

  def handle_call({:submit_answer, player_id, index}, _from, state) do
    cond do
      not Map.has_key?(state.players, player_id) ->
        {:reply, {:error, :unknown_player}, state}

      state.phase != :playing ->
        {:reply, {:error, :not_playing}, state}

      state.players[player_id].locked ->
        {:reply, {:error, :locked}, state}

      index == state.round.answer_index ->
        case resolve_round(state, player_id) do
          {:cont, state} -> {:reply, {:ok, :correct}, state}
          {:stop, state} -> {:stop, :normal, {:ok, :correct}, state}
        end

      true ->
        state = put_in(state.players[player_id].locked, true)

        if Enum.all?(state.players, fn {_id, p} -> p.locked end) do
          case resolve_round(state, nil) do
            {:cont, state} -> {:reply, {:ok, :locked}, state}
            {:stop, state} -> {:stop, :normal, {:ok, :locked}, state}
          end
        else
          {:reply, {:ok, :locked}, state}
        end
    end
  end

  # Timer-generation pattern: every timer message carries the round_no it was
  # armed for; a mismatch (or wrong phase) means the timer is stale — ignore.

  @impl true
  def handle_info({:countdown_over, round_no}, %{phase: :countdown, round_no: round_no} = state) do
    Process.send_after(self(), {:round_timeout, round_no}, state.timings.round_ms)
    {:noreply, %{state | phase: :playing}}
  end

  def handle_info({:round_timeout, round_no}, %{phase: :playing, round_no: round_no} = state) do
    case resolve_round(state, nil) do
      {:cont, state} -> {:noreply, state}
      {:stop, state} -> {:stop, :normal, state}
    end
  end

  def handle_info({:next_round, round_no}, %{phase: :resolved, round_no: round_no} = state) do
    start_round(state)
  end

  def handle_info(_stale_or_unknown, state), do: {:noreply, state}

  ## Phase transitions

  defp start_round(state) do
    round_no = state.round_no + 1

    case state.payload_fun.(state.pool_id) do
      {:ok, payload} ->
        state = %{
          state
          | phase: :countdown,
            round_no: round_no,
            round: Map.put(payload, :answered, false),
            players: unlock_players(state.players)
        }

        # Anti-cheat invariant: title/artist of the playing track are NOT in
        # this payload — only the shuffled options and media URLs.
        broadcast(state, :round_loading, %{
          round_no: round_no,
          preview_url: payload.track.preview_url,
          artwork_url: payload.track.artwork_url,
          options: payload.options
        })

        start_at = System.system_time(:millisecond) + state.timings.countdown_ms
        broadcast(state, :countdown, %{round_no: round_no, start_at: start_at})
        Process.send_after(self(), {:countdown_over, round_no}, state.timings.countdown_ms)

        {:noreply, state}

      {:error, reason} ->
        broadcast(state, :match_over, %{
          winner: nil,
          reason: to_string(reason),
          scores: scores(state)
        })

        {:stop, :normal, state}
    end
  end

  defp resolve_round(state, winner_id) do
    state =
      if winner_id,
        do: update_in(state.players[winner_id].score, &(&1 + 1)),
        else: state

    track = state.round.track

    entry = %{
      round_no: state.round_no,
      winner_id: winner_id,
      apple_track_id: track.apple_track_id,
      title: track.title,
      artist: track.artist_name,
      correct_index: state.round.answer_index
    }

    state = %{
      state
      | phase: :resolved,
        round: %{state.round | answered: true},
        rounds: [entry | state.rounds]
    }

    broadcast(state, :round_result, %{
      round_no: state.round_no,
      winner: winner_id,
      correct_index: state.round.answer_index,
      correct: %{title: track.title, artist: track.artist_name},
      scores: scores(state)
    })

    if finished?(state) do
      {:stop, finish(state)}
    else
      Process.send_after(self(), {:next_round, state.round_no}, state.timings.resolved_ms)
      {:cont, state}
    end
  end

  defp finished?(state) do
    state.round_no >= @best_of or
      Enum.any?(state.players, fn {_id, p} -> p.score >= @needed_wins end)
  end

  defp finish(state) do
    winner_id = overall_winner(state)
    [a, b] = state.player_order

    {:ok, _match} =
      state.persist_fun.(%{
        pool_id: state.pool_id,
        player_a: a,
        player_b: b,
        winner_id: winner_id,
        rounds: Enum.reverse(state.rounds),
        finished_at: DateTime.utc_now(:second)
      })

    broadcast(state, :match_over, %{winner: winner_id, scores: scores(state)})
    %{state | phase: :finished}
  end

  defp overall_winner(state) do
    case Enum.sort_by(state.players, fn {_id, p} -> -p.score end) do
      [{_id, %{score: s}}, {_id2, %{score: s}}] -> nil
      [{id, _} | _] -> id
    end
  end

  ## Helpers

  defp new_player, do: %{score: 0, ready: false, locked: false}

  defp unlock_players(players) do
    Map.new(players, fn {id, p} -> {id, %{p | locked: false}} end)
  end

  defp scores(state), do: Map.new(state.players, fn {id, p} -> {id, p.score} end)

  defp broadcast(state, event, payload) do
    Phoenix.PubSub.broadcast(
      Crescendo.PubSub,
      "duel:" <> state.match_id,
      {:duel_event, event, payload}
    )
  end

  defp config_timings(config) do
    %{
      countdown_ms: config[:countdown_ms] || 3_000,
      round_ms: config[:round_ms] || 30_000,
      resolved_ms: config[:resolved_ms] || 3_000
    }
  end

  defp mfa_fun({mod, fun}), do: &apply(mod, fun, [&1])
end
