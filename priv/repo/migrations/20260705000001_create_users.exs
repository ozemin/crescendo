defmodule Crescendo.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :game_center_id, :string, null: false
      add :display_name, :string, null: false
      add :elo, :integer, null: false, default: 1000

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:game_center_id])
  end
end
