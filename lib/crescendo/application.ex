defmodule Crescendo.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CrescendoWeb.Telemetry,
      Crescendo.Repo,
      {DNSCluster, query: Application.get_env(:crescendo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Crescendo.PubSub},
      # match_id → DuelServer pid, "pool:" <> slug → matchmaking queue pid
      {Registry, keys: :unique, name: Crescendo.Registry},
      {DynamicSupervisor, name: Crescendo.DuelSupervisor, strategy: :one_for_one},
      {DynamicSupervisor, name: Crescendo.QueueSupervisor, strategy: :one_for_one},
      {Oban, Application.fetch_env!(:crescendo, Oban)},
      # Start to serve requests, typically the last entry
      CrescendoWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Crescendo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CrescendoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
