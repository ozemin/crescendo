# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :crescendo,
  ecto_repos: [Crescendo.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :crescendo, CrescendoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: CrescendoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Crescendo.PubSub,
  live_view: [signing_salt: "p6Mil1Pr"]

# Oban background jobs: catalog queue + weekly refresh of stale pool tracks
config :crescendo, Oban,
  engine: Oban.Engines.Basic,
  repo: Crescendo.Repo,
  queues: [catalog: 5],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 5 * * 1", Crescendo.MusicCatalog.RefreshWorker}
     ]}
  ]

# Duel timing knobs are injected via config so tests can run in milliseconds.
config :crescendo, :duel,
  countdown_ms: 3_000,
  round_ms: 30_000,
  resolved_ms: 3_000,
  payload_mfa: {Crescendo.MusicCatalog, :get_round_payload}

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
