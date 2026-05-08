defmodule Sonar.SessionListActionTest do
  @moduledoc """
  Tests for the `sonar_session_list` MCP action surface (plan §8.2).
  """

  use ExUnit.Case

  alias Sonar.{ActionRegistry, Peers}

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Sonar.Repo, shared: false)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  test "registry exposes sonar_session_list" do
    action = ActionRegistry.find("sonar_session_list")
    assert action != nil
    assert action.method == :get
    assert action.path == "/api/sessions"
  end

  test "no peer_id → routes to local listing" do
    {:ok, payload} = ActionRegistry.execute("sonar_session_list", %{})
    assert is_list(payload.sessions)
    assert is_integer(payload.queried_at)
  end

  test "empty peer_id is treated as local" do
    {:ok, payload} = ActionRegistry.execute("sonar_session_list", %{"peer_id" => ""})
    assert is_list(payload.sessions)
  end

  test "non-paired peer → peer_not_paired" do
    {:ok, peer} =
      Peers.create(%{
        "name" => "scout",
        "hostname" => "scout.local",
        "connection_status" => "discovered"
      })

    assert {:error, :peer_not_paired} =
             ActionRegistry.execute("sonar_session_list", %{"peer_id" => peer.id})
  end
end
