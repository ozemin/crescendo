defmodule Crescendo.Games do
  @moduledoc """
  Game context: starting duels under the DynamicSupervisor/Registry pair and
  persisting finished matches. This is the only module that writes matches —
  and it only ever writes *finished* ones (see `Crescendo.Games.DuelServer`).
  """

  alias Crescendo.Games.{DuelServer, Match}
  alias Crescendo.Repo

  @doc """
  Spawns a `DuelServer` for two matched players and returns the match id used
  as its Registry key. Restart is `:temporary`: in-memory state cannot be
  rebuilt after a crash, so the match dies with the process.
  """
  def start_duel(pool_id, player_a, player_b, opts \\ []) do
    match_id = Ecto.UUID.generate()

    spec =
      {DuelServer, [match_id: match_id, pool_id: pool_id, players: [player_a, player_b]] ++ opts}

    with {:ok, _pid} <- DynamicSupervisor.start_child(Crescendo.DuelSupervisor, spec) do
      {:ok, match_id}
    end
  end

  @doc "Writes a finished match. Called exactly once by DuelServer at `:finished`."
  def persist_match(attrs) do
    %Match{}
    |> Match.changeset(attrs)
    |> Repo.insert()
  end
end
