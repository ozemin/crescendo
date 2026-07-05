defmodule Crescendo.Games.Matchmaking do
  @moduledoc """
  Entry point for matchmaking: resolves the pool, lazily starts the per-pool
  queue process and delegates the join. Queue processes register under
  `"pool:" <> slug` in `Crescendo.Registry`.
  """

  alias Crescendo.Games.Matchmaking.QueueServer
  alias Crescendo.MusicCatalog

  @doc """
  Queue `player_id` for a duel in the pool named by `slug`. `channel_pid` is
  monitored while the player waits — if their channel dies they are dropped.

  Returns `{:ok, :queued}` or `{:ok, {:matched, match_id}}` (the previously
  waiting player is notified with a `{:matched, match_id}` message).
  """
  def join(slug, player_id, channel_pid) do
    case MusicCatalog.get_pool_by_slug(slug) do
      nil -> {:error, :unknown_pool}
      pool -> GenServer.call(ensure_queue(slug), {:join, player_id, channel_pid, pool.id})
    end
  end

  defp ensure_queue(slug) do
    case Registry.lookup(Crescendo.Registry, "pool:" <> slug) do
      [{pid, _}] ->
        pid

      [] ->
        case DynamicSupervisor.start_child(Crescendo.QueueSupervisor, {QueueServer, slug}) do
          {:ok, pid} -> pid
          {:error, {:already_started, pid}} -> pid
        end
    end
  end
end
