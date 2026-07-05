# Duel — Real-time Music Quiz Backend

API-only Phoenix server for a 2-player, best-of-5 music guessing duel. iOS client lives elsewhere; this repo exposes Phoenix Channels only (no HTML/assets/mailer). Stack: Phoenix + Postgres/Ecto, Req for HTTP, Oban for background jobs.

## Architecture rules (fixed decisions)

- **Live match state lives only in a `DuelServer` GenServer.** The database stores finished matches only. No Ecto access during a round.
- **Process pattern:** `DynamicSupervisor` + `Registry` (`keys: :unique`, `match_id → pid`), via-tuples for addressing. Restart is `:temporary` — in-memory state cannot be rebuilt after a crash, so restarting an empty process is worse than letting the match die (reconnect-resume is out of scope).
- **Never store a game pid in socket assigns.** Look up via Registry/via-tuple on every call; pids go stale, names don't.
- **GenServer mailbox serialization is the only ordering guarantee.** All state mutations go through `GenServer.call`. No extra locks. First correct `submit_answer` to reach the mailbox wins the round.
- **Timers:** `Process.send_after` with the `round_no` baked into the message; a timeout carrying a stale `round_no` is ignored (timer-generation pattern).
- **Matchmaking queues** are per-pool GenServers, lazily started, registered via `"pool:" <> slug`. `Process.monitor` the queued player's channel pid; drop them on `:DOWN`.
- **Channels are thin:** deserialize → delegate to GenServer → serialize. All game logic lives in contexts (`MusicCatalog`, `Games`). Broadcasts go through `Phoenix.PubSub`, never computed in the channel.
- **Anti-cheat invariant:** track title/artist are never sent to the client before `round_result`. Round payloads (preview_url, artwork_url, options) are prepared server-side; the client never talks to Apple.
- Countdown sync: server broadcasts `start_at` (server epoch + 3s buffer); clients schedule playback against it.

## External API (iTunes)

- iTunes Search API: no auth, ~20 req/min. The seed task (`mix catalog.seed <slug>`) rate-limits with `Process.sleep` between requests (~3.5s) — fine for a single-process, one-off task; don't add Hammer/ExRated unless requests become concurrent.
- Track titles are normalized to dedupe live/remix/karaoke variants.
- The Req client accepts an injectable `plug` option so tests can stub responses with `Req.Test` — never hit the network in tests.
- Weekly Oban cron job (`Oban.Plugins.Cron`) refreshes tracks with `fetched_at` older than 7 days via /lookup; 404 → deactivate the row.

## Testing conventions

- **DuelServer tests spawn their own GenServer instance per test** so `async: true` stays safe — no shared processes between tests.
- **Ecto sandbox:** GenServers that touch the DB (match persistence on `:finished`) run in a separate process — grant sandbox access with `Ecto.Adapters.SQL.Sandbox.allow/3` or tests will fail with ownership errors. This is the most common trap here.
- **Timing values (countdown, round timeout) are injected via opts/config**, not hardcoded — tests use milliseconds, prod uses real durations. Never write tests that sleep through real game timers.
- Channel tests use `Phoenix.ChannelTest`: `assert_reply` / `assert_push` / `assert_broadcast`; catch async channel shutdowns with `Process.monitor` + `assert_receive {:DOWN, ...}`.
- Oban in test mode is `testing: :manual`; test workers by calling `perform/1` directly via `Oban.Testing`.

## Out of scope (do not build)

ELO calculation, reconnect-resume, clustering/Horde, Game Center signature verification (leave TODO in `UserSocket.connect/3`), admin panel, deploy config.
