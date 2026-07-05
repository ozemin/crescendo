# Seeds sample pools and two demo users. Idempotent — safe to re-run.
#
#     mix run priv/repo/seeds.exs
#     mix catalog.seed rock          # then fill a pool from iTunes

alias Crescendo.Repo
alias Crescendo.Accounts.User
alias Crescendo.MusicCatalog.Pool

pools = [
  %{slug: "rock", name: "Rock", type: "genre"},
  %{slug: "pop", name: "Pop", type: "genre"},
  %{slug: "queen", name: "Queen", type: "artist"},
  %{slug: "tarkan", name: "Tarkan", type: "artist"}
]

for attrs <- pools do
  Repo.insert!(
    Pool.changeset(%Pool{}, attrs),
    on_conflict: {:replace, [:name, :type]},
    conflict_target: :slug
  )
end

users = [
  %{game_center_id: "G:demo-player-1", display_name: "Player One"},
  %{game_center_id: "G:demo-player-2", display_name: "Player Two"}
]

for attrs <- users do
  Repo.insert!(
    User.changeset(%User{}, attrs),
    on_conflict: :nothing,
    conflict_target: :game_center_id
  )
end

IO.puts("Seeded #{length(pools)} pools and #{length(users)} demo users.")
