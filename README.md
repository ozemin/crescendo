# Crescendo

API-only Phoenix backend for a real-time, 2-player, best-of-5 music guessing
duel. The iOS client lives elsewhere; this server exposes Phoenix Channels
only. Live match state lives exclusively in a `DuelServer` GenServer — the
database stores finished matches only.

## Setup

```sh
mix setup                # deps + db create/migrate + sample pools/users
mix catalog.seed queen   # fill a pool from the iTunes Search API
mix phx.server           # ws://localhost:4000/socket
mix test
```

Requires Postgres on `localhost:5432` (`postgres`/`postgres`).

## Channel protocol

Connect with `{"user_id": <id>}` (Game Center verification: TODO).

- `"matchmaking:lobby"` — push `join_pool {pool}`; receive `matched {match_id}`.
- `"duel:{match_id}"` — push `ready` (once per match) and `answer {index}`; receive
  `round_loading (preview_url, artwork_url, options)`, `all_ready`,
  `countdown (start_at)`, `round_result (winner, correct_index, scores)`,
  `match_over (winner, scores)`.

Clients schedule preview playback against the server-issued `start_at`; the
correct answer never reaches a client before `round_result`.

## Layout

- `Crescendo.MusicCatalog` — pools/tracks, iTunes client (Req), round
  payloads, weekly Oban refresh of stale tracks, `mix catalog.seed <slug>`.
- `Crescendo.Games` — `DuelServer` (all live game logic), per-pool
  matchmaking queues, match persistence. `DynamicSupervisor` + `Registry`,
  `restart: :temporary`.
- `CrescendoWeb` — thin channels: deserialize → GenServer call → serialize.
