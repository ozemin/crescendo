defmodule Crescendo.MusicCatalog.Track do
  @moduledoc """
  One playable 30s preview inside a pool, sourced from the iTunes Search API.
  `fetched_at` drives the weekly refresh; `active: false` means iTunes no
  longer serves the track (404 on lookup) and it must not enter rounds.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "tracks" do
    field :apple_track_id, :integer
    field :title, :string
    field :artist_name, :string
    field :preview_url, :string
    field :artwork_url, :string
    field :fetched_at, :utc_datetime
    field :active, :boolean, default: true

    belongs_to :pool, Crescendo.MusicCatalog.Pool

    timestamps(type: :utc_datetime)
  end

  def changeset(track, attrs) do
    track
    |> cast(attrs, [
      :pool_id,
      :apple_track_id,
      :title,
      :artist_name,
      :preview_url,
      :artwork_url,
      :fetched_at,
      :active
    ])
    |> validate_required([
      :pool_id,
      :apple_track_id,
      :title,
      :artist_name,
      :preview_url,
      :fetched_at
    ])
    |> unique_constraint([:pool_id, :apple_track_id])
  end
end
