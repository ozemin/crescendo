defmodule Crescendo.MusicCatalog.RefreshWorker do
  @moduledoc """
  Weekly Oban cron job (`0 5 * * 1`): re-lookup tracks whose `fetched_at` is
  older than 7 days, refresh preview/artwork URLs, and deactivate tracks that
  iTunes no longer returns.
  """

  use Oban.Worker, queue: :catalog, max_attempts: 3

  alias Crescendo.MusicCatalog

  @impl Oban.Worker
  def perform(_job) do
    cutoff = DateTime.add(DateTime.utc_now(), -7, :day)

    cutoff
    |> MusicCatalog.stale_tracks()
    |> MusicCatalog.refresh_tracks()

    :ok
  end
end
