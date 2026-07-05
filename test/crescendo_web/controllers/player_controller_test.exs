defmodule CrescendoWeb.PlayerControllerTest do
  use CrescendoWeb.ConnCase, async: true

  test "registers a web player from a display name", %{conn: conn} do
    conn = post(conn, ~p"/api/players", %{"name" => "  Emin  "})

    assert %{"id" => id, "name" => "Emin"} = json_response(conn, 201)
    user = Crescendo.Repo.get!(Crescendo.Accounts.User, id)
    assert String.starts_with?(user.game_center_id, "web:")
  end

  test "rejects a blank name", %{conn: conn} do
    conn = post(conn, ~p"/api/players", %{"name" => "   "})
    assert %{"error" => "name_required"} = json_response(conn, 422)
  end

  test "rejects a missing name", %{conn: conn} do
    conn = post(conn, ~p"/api/players", %{})
    assert %{"error" => "name_required"} = json_response(conn, 422)
  end
end
