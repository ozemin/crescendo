defmodule Crescendo.Repo.Migrations.CreateTracks do
  use Ecto.Migration

  def change do
    create table(:tracks) do
      add :pool_id, references(:pools, on_delete: :delete_all), null: false
      add :apple_track_id, :bigint, null: false
      add :title, :string, null: false
      add :artist_name, :string, null: false
      add :preview_url, :text, null: false
      add :artwork_url, :text
      add :fetched_at, :utc_datetime, null: false
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tracks, [:pool_id, :apple_track_id])
    create index(:tracks, [:pool_id, :active])
    create index(:tracks, [:fetched_at])
  end
end
