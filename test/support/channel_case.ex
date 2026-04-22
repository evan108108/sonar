defmodule SonarWeb.ChannelCase do
  @moduledoc """
  Test case for channel tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint SonarWeb.Endpoint

      import Phoenix.ChannelTest
      import SonarWeb.ChannelCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Sonar.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
