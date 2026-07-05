defmodule Crescendo.Repo.Migrations.CreatePools do
  use Ecto.Migration

  def change do
    create table(:pools) do
      add :slug, :string, null: false
      add :name, :string, null: false
      add :type, :string, null: false
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:pools, [:slug])
  end
end
