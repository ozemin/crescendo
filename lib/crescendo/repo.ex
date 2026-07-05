defmodule Crescendo.Repo do
  use Ecto.Repo,
    otp_app: :crescendo,
    adapter: Ecto.Adapters.Postgres
end
