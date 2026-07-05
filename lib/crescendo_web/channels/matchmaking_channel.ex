defmodule CrescendoWeb.MatchmakingChannel do
  @moduledoc """
  `"matchmaking:lobby"` — thin adapter over `Crescendo.Games.Matchmaking`.
  `join_pool` either replies `queued` or ends with a `matched` push (both for
  the instant match on the joining side and via `{:matched, match_id}` for
  the player who was already waiting).
  """

  use Phoenix.Channel

  alias Crescendo.Games.Matchmaking

  @impl true
  def join("matchmaking:lobby", _payload, socket), do: {:ok, socket}

  @impl true
  def handle_in("join_pool", %{"pool" => slug}, socket) do
    case Matchmaking.join(slug, socket.assigns.user_id, self()) do
      {:ok, :queued} ->
        {:reply, {:ok, %{status: "queued"}}, socket}

      {:ok, {:matched, match_id}} ->
        push(socket, "matched", %{match_id: match_id})
        {:reply, {:ok, %{status: "matched"}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  @impl true
  def handle_info({:matched, match_id}, socket) do
    push(socket, "matched", %{match_id: match_id})
    {:noreply, socket}
  end
end
