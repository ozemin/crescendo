defmodule Crescendo.Accounts do
  @moduledoc """
  Minimal user context: create/fetch players. No ELO calculation here (out of
  scope); the `elo` column just holds its default until that ships.
  """

  alias Crescendo.Accounts.User
  alias Crescendo.Repo

  def get_user(id), do: Repo.get(User, id)

  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Registers a web player from a bare display name. Each registration is a
  fresh user (`web:` prefixed synthetic game_center_id); the web client keeps
  the returned id in localStorage, so re-registration only happens when the
  player clears it or changes their name.
  """
  def register_web_player(name) when is_binary(name) do
    name = name |> String.trim() |> String.slice(0, 24)

    if name == "" do
      {:error, :name_required}
    else
      create_user(%{game_center_id: "web:" <> Ecto.UUID.generate(), display_name: name})
    end
  end

  def register_web_player(_), do: {:error, :name_required}
end
