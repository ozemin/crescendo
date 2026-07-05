defmodule CrescendoWeb.PageController do
  use CrescendoWeb, :controller

  def home(conn, _params), do: redirect(conn, to: "/play.html")
end
