defmodule Crescendo.Repo.Migrations.CreateMatches do
  use Ecto.Migration

  def change do
    create table(:matches) do
      add :pool_id, references(:pools, on_delete: :nilify_all)
      add :player_a, references(:users, on_delete: :nilify_all)
      add :player_b, references(:users, on_delete: :nilify_all)
      add :winner_id, references(:users, on_delete: :nilify_all)
      # jsonb array of per-round summaries
      add :rounds, :map, null: false, default: fragment("'[]'::jsonb")
      add :finished_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:matches, [:player_a])
    create index(:matches, [:player_b])
  end
end
