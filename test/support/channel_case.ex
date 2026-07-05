defmodule CrescendoWeb.ChannelCase do
  @moduledoc """
  Test case for channel tests: `Phoenix.ChannelTest` imports plus Ecto SQL
  sandbox. Non-async tests get shared sandbox mode so spawned processes
  (DuelServer, matchmaking queues) can touch the database.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import CrescendoWeb.ChannelCase

      @endpoint CrescendoWeb.Endpoint
    end
  end

  setup tags do
    Crescendo.DataCase.setup_sandbox(tags)
    :ok
  end
end
