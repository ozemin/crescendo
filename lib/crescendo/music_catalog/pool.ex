defmodule Crescendo.MusicCatalog.Pool do
  @moduledoc """
  A themed track pool players queue into. `type` is `"genre"` or `"artist"`;
  `name` doubles as the iTunes search term when seeding.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @types ~w(genre artist)

  schema "pools" do
    field :slug, :string
    field :name, :string
    field :type, :string
    field :active, :boolean, default: true

    has_many :tracks, Crescendo.MusicCatalog.Track

    timestamps(type: :utc_datetime)
  end

  def changeset(pool, attrs) do
    pool
    |> cast(attrs, [:slug, :name, :type, :active])
    |> validate_required([:slug, :name, :type])
    |> validate_inclusion(:type, @types)
    |> unique_constraint(:slug)
  end
end
