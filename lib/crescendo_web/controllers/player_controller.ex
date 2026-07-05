defmodule CrescendoWeb.PlayerController do
  @moduledoc """
  Lightweight registration for web players: a display name in, a player id
  out. Game Center identity (for the iOS client) is a separate, future path.
  """

  use CrescendoWeb, :controller

  alias Crescendo.Accounts

  def create(conn, %{"name" => name}) do
    case Accounts.register_web_player(name) do
      {:ok, user} ->
        conn
        |> put_status(:created)
        |> json(%{id: user.id, name: user.display_name})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: to_string(reason)})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "name_required"})
  end
end
