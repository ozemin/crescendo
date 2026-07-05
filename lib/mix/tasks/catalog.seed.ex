defmodule Mix.Tasks.Catalog.Seed do
  @shortdoc "Seeds a track pool from the iTunes Search API"

  @moduledoc """
  Fills an existing pool with tracks from iTunes:

      mix catalog.seed <slug>

  The pool's `name` is used as the search term (with `attribute=artistTerm`
  for artist pools). Requests are spaced with `Process.sleep` to respect the
  ~20 req/min limit.
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run([slug]) do
    case Crescendo.MusicCatalog.get_pool_by_slug(slug) do
      nil ->
        Mix.raise(
          "No active pool with slug #{inspect(slug)}. Run `mix run priv/repo/seeds.exs` first."
        )

      pool ->
        Mix.shell().info("Seeding pool #{pool.slug} (#{pool.type}: #{pool.name}) from iTunes…")
        {:ok, count} = Crescendo.MusicCatalog.seed_pool(pool)
        Mix.shell().info("Upserted #{count} tracks.")
    end
  end

  def run(_), do: Mix.raise("Usage: mix catalog.seed <slug>")
end
