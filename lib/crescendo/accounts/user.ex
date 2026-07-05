defmodule Crescendo.Accounts.User do
  @moduledoc """
  A player. `game_center_id` is the external identity; verification of the
  Game Center signature is out of scope for now (see `CrescendoWeb.UserSocket`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :game_center_id, :string
    field :display_name, :string
    field :elo, :integer, default: 1000

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:game_center_id, :display_name, :elo])
    |> validate_required([:game_center_id, :display_name])
    |> unique_constraint(:game_center_id)
  end
end
