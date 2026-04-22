defmodule Sonar.AuditTest do
  use ExUnit.Case, async: false

  alias Sonar.Audit

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Sonar.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  test "log/1 writes a row and recent/1 returns it" do
    :ok =
      Audit.log(%{
        action: "token.issued",
        peer_id: nil,
        peer_name: "scout",
        response_status: 201,
        response_time_ms: 12
      })

    rows = Audit.recent(5)
    assert Enum.any?(rows, fn r -> r.action == "token.issued" and r.peer_name == "scout" end)
  end

  test "log/1 truncates oversized request_body" do
    big = String.duplicate("x", 20_000)
    assert :ok = Audit.log(%{action: "relay.message.received", request_body: big})
  end

  test "log/1 handles missing fields without raising" do
    assert :ok = Audit.log(%{action: "something"})
  end
end
