defmodule CrescendoWeb.DuelChannel do
  @moduledoc """
  `"duel:{match_id}"` — deserialize → `DuelServer` call → serialize. No game
  logic lives here. The DuelServer broadcasts `{:duel_event, event, payload}`
  tuples on the same PubSub topic; they arrive in `handle_info/2` and are
  pushed verbatim (events: round_loading, all_ready, countdown, round_result,
  match_over).
  """

  use Phoenix.Channel

  alias Crescendo.Games.DuelServer

  @impl true
  def join("duel:" <> match_id, _payload, socket) do
    # Registry lookup happens inside the call; never cache a game pid here.
    case DuelServer.participant?(match_id, socket.assigns.user_id) do
      {:ok, true} -> {:ok, assign(socket, :match_id, match_id)}
      {:ok, false} -> {:error, %{reason: "unauthorized"}}
      {:error, :match_not_found} -> {:error, %{reason: "not_found"}}
    end
  end

  @impl true
  def handle_in("ready", _payload, socket) do
    case DuelServer.player_ready(socket.assigns.match_id, socket.assigns.user_id) do
      :ok -> {:reply, :ok, socket}
      {:error, reason} -> {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  def handle_in("answer", %{"index" => index}, socket) when is_integer(index) do
    case DuelServer.submit_answer(socket.assigns.match_id, socket.assigns.user_id, index) do
      {:ok, result} -> {:reply, {:ok, %{result: to_string(result)}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  def handle_in("answer", _payload, socket) do
    {:reply, {:error, %{reason: "invalid_payload"}}, socket}
  end

  @impl true
  def handle_info({:duel_event, event, payload}, socket) do
    push(socket, to_string(event), payload)
    {:noreply, socket}
  end
end
