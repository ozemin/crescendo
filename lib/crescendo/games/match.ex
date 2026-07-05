defmodule Crescendo.Games.Match do
  @moduledoc """
  A *finished* duel. Live match state lives only in `Crescendo.Games.DuelServer`;
  this row is written once, when the match reaches `:finished`. `rounds` is a
  jsonb list of per-round summaries; `winner_id` is nil on a draw.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "matches" do
    field :player_a, :id
    field :player_b, :id
    field :winner_id, :id
    field :rounds, {:array, :map}, default: []
    field :finished_at, :utc_datetime

    belongs_to :pool, Crescendo.MusicCatalog.Pool

    timestamps(type: :utc_datetime)
  end

  def changeset(match, attrs) do
    match
    |> cast(attrs, [:pool_id, :player_a, :player_b, :winner_id, :rounds, :finished_at])
    |> validate_required([:player_a, :player_b, :finished_at])
  end
end
