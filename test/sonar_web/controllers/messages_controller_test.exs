defmodule SonarWeb.MessagesControllerTest do
  use SonarWeb.ConnCase

  import Sonar.Fixtures

  setup do
    p = peer(%{name: "scout", hostname: "scout.local"})
    {:ok, peer: p}
  end

  test "POST /api/messages/send creates an outbound message", %{conn: conn, peer: p} do
    conn =
      post(conn, "/api/messages/send", %{
        peer_id: p.id,
        question: "What is your architecture?"
      })

    body = json_response(conn, 202)
    assert body["status"] == "pending"
    assert is_binary(body["message_id"])
    assert body["poll_url"] =~ body["message_id"]
  end

  test "POST /api/messages/send requires peer_id and question", %{conn: conn} do
    conn = post(conn, "/api/messages/send", %{})
    assert json_response(conn, 400)["error"] =~ "Missing"
  end

  test "GET /api/messages/:id returns a message", %{conn: conn, peer: p} do
    msg = outbound_message(%{peer: p, question: "Hello?"})
    conn = get(conn, "/api/messages/#{msg.id}")
    body = json_response(conn, 200)

    assert body["question"] == "Hello?"
    assert body["status"] == "pending"
    assert body["direction"] == "outbound"
  end

  test "GET /api/messages/:id returns 404 for unknown", %{conn: conn} do
    conn = get(conn, "/api/messages/nonexistent")
    assert json_response(conn, 404)["error"] == "Message not found"
  end

  test "GET /api/messages/inbox returns only inbound messages", %{conn: conn, peer: p} do
    message(%{peer: p, direction: "inbound", question: "Inbound Q"})
    outbound_message(%{peer: p, question: "Outbound Q"})

    conn = get(conn, "/api/messages/inbox")
    messages = json_response(conn, 200)

    assert length(messages) == 1
    assert hd(messages)["question"] == "Inbound Q"
  end

  test "POST /api/messages/:id/reply answers a message", %{conn: conn, peer: p} do
    msg = message(%{peer: p, question: "What is 2+2?"})

    conn = post(conn, "/api/messages/#{msg.id}/reply", %{answer: "4"})
    body = json_response(conn, 200)

    assert body["answer"] == "4"
    assert body["status"] == "answered"
    assert body["answered_at"] != nil
  end

  test "inbox filters by status", %{conn: conn, peer: p} do
    message(%{peer: p, status: "pending", question: "Q1"})
    message(%{peer: p, status: "answered", question: "Q2"})

    conn = get(conn, "/api/messages/inbox?status=pending")
    messages = json_response(conn, 200)

    assert length(messages) == 1
    assert hd(messages)["status"] == "pending"
  end
end
