defmodule Crescendo.Games.Matchmaking.QueueServer do
  @moduledoc """
  Per-pool matchmaking queue, lazily started on first join and registered as
  `"pool:" <> slug`.

  State: `%{slug, waiting: nil | %{player_id, channel_pid, ref}}` — at most
  one waiting player. A second, different player triggers a `DuelServer`
  spawn; both sides receive the match id. The waiting player's channel pid is
  monitored and dropped on `:DOWN`.
  """

  use GenServer, restart: :temporary

  alias Crescendo.Games

  def start_link(slug) do
    GenServer.start_link(__MODULE__, slug,
      name: {:via, Registry, {Crescendo.Registry, "pool:" <> slug}}
    )
  end

  @impl true
  def init(slug), do: {:ok, %{slug: slug, waiting: nil}}

  @impl true
  def handle_call({:join, player_id, channel_pid, _pool_id}, _from, %{waiting: nil} = state) do
    {:reply, {:ok, :queued}, %{state | waiting: monitor_waiting(player_id, channel_pid)}}
  end

  # Same player re-joining (e.g. after a reconnect): track the new channel pid.
  def handle_call(
        {:join, player_id, channel_pid, _pool_id},
        _from,
        %{waiting: %{player_id: player_id}} = state
      ) do
    Process.demonitor(state.waiting.ref, [:flush])
    {:reply, {:ok, :queued}, %{state | waiting: monitor_waiting(player_id, channel_pid)}}
  end

  def handle_call({:join, player_id, _channel_pid, pool_id}, _from, %{waiting: waiting} = state) do
    Process.demonitor(waiting.ref, [:flush])
    {:ok, match_id} = Games.start_duel(pool_id, waiting.player_id, player_id)
    send(waiting.channel_pid, {:matched, match_id})
    {:reply, {:ok, {:matched, match_id}}, %{state | waiting: nil}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{waiting: %{ref: ref}} = state) do
    {:noreply, %{state | waiting: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp monitor_waiting(player_id, channel_pid) do
    %{player_id: player_id, channel_pid: channel_pid, ref: Process.monitor(channel_pid)}
  end
end
