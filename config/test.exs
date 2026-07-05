import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :crescendo, Crescendo.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "crescendo_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :crescendo, CrescendoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "+8O8+nRVLfZaP33gq3DnU/HFqz4OA/fouHRlPbU2xhnCuavvGM0Q7OuGvrJ7fI0h",
  server: false

# Oban: never run jobs automatically in tests; call perform/1 via Oban.Testing
config :crescendo, Oban, testing: :manual

# Millisecond game timers + deterministic round payload stub (answer_index is
# always 0) so channel tests never sleep through real game timers.
config :crescendo, :duel,
  countdown_ms: 50,
  round_ms: 2_000,
  resolved_ms: 20,
  payload_mfa: {Crescendo.TestSupport.Payloads, :get_round_payload}

# Route all iTunes requests through Req.Test — tests never hit the network
config :crescendo, Crescendo.MusicCatalog.ITunes, plug: {Req.Test, Crescendo.MusicCatalog.ITunes}

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
