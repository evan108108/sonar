defmodule SonarWeb.ReceivePortTest do
  use SonarWeb.ConnCase

  import Sonar.Fixtures

  alias Sonar.Repo
  alias Sonar.Schema.Peer

  setup do
    {:ok, peer: peer(%{name: "scout", hostname: "scout-cloud", port: 4001})}
  end

  test "an inbound message with from_port moves the sender's row", %{conn: conn, peer: p} do
    conn =
      post(conn, "/api/messages/receive", %{
        from_instance_id: p.instance_id,
        from_port: 4006,
        message: %{message_id: "remote-1", question: "still there?"}
      })

    assert json_response(conn, 201)["ok"]
    assert Repo.get(Peer, p.id).port == 4006
  end

  test "an inbound message without from_port leaves the port alone", %{conn: conn, peer: p} do
    conn =
      post(conn, "/api/messages/receive", %{
        from_instance_id: p.instance_id,
        message: %{message_id: "remote-2", question: "still there?"}
      })

    assert json_response(conn, 201)["ok"]
    assert Repo.get(Peer, p.id).port == 4001
  end

  test "an unknown sender's from_port is ignored", %{conn: conn, peer: p} do
    conn =
      post(conn, "/api/messages/receive", %{
        from_instance_id: "not-a-peer",
        from_port: 4009,
        message: %{message_id: "remote-3", question: "hi"}
      })

    assert json_response(conn, 404)
    assert Repo.get(Peer, p.id).port == 4001
  end

  test "an ack with from_port moves the sender's row", %{conn: conn, peer: p} do
    conn =
      post(conn, "/api/messages/receive_ack", %{
        from_instance_id: p.instance_id,
        from_port: "4007",
        message: %{message_id: "m-1", acked_at_ms: 1}
      })

    assert json_response(conn, 200)["ok"]
    assert Repo.get(Peer, p.id).port == 4007
  end
end
