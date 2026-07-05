defmodule CrescendoWeb.UserSocket do
  @moduledoc """
  Single socket for the iOS client. Authenticates (for now) with a bare
  `user_id` connect param.
  """

  use Phoenix.Socket

  channel "matchmaking:lobby", CrescendoWeb.MatchmakingChannel
  channel "duel:*", CrescendoWeb.DuelChannel

  @impl true
  def connect(%{"user_id" => user_id}, socket, _connect_info) do
    # TODO: Game Center signature verification goes here. Until then the
    # client-supplied user_id is trusted as-is.
    case parse_id(user_id) do
      {:ok, id} -> {:ok, assign(socket, :user_id, id)}
      :error -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"

  defp parse_id(id) when is_integer(id), do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_id(_), do: :error
end
