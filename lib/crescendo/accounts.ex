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
end
