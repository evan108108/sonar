defmodule SonarWeb.ConnCase do
  @moduledoc """
  Test case for controller tests. Sets up database sandbox
  so each test gets a clean database.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint SonarWeb.Endpoint

      use SonarWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import SonarWeb.ConnCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Sonar.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
