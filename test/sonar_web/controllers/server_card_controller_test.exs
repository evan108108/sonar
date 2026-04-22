defmodule SonarWeb.ServerCardControllerTest do
  use SonarWeb.ConnCase

  test "GET /.well-known/sonar/card.json returns 200", %{conn: conn} do
    conn = get(conn, "/.well-known/sonar/card.json")
    assert conn.status == 200
  end

  test "response has correct structure", %{conn: conn} do
    conn = get(conn, "/.well-known/sonar/card.json")
    body = json_response(conn, 200)

    assert body["version"] == "1.0"

    assert is_map(body["agent"])
    assert is_binary(body["agent"]["name"])
    assert is_binary(body["agent"]["instance_id"])
    assert is_binary(body["agent"]["version"])
    assert body["agent"]["description"] == "Sonar peer-to-peer agent relay"

    assert is_list(body["capabilities"])

    assert is_map(body["transport"])
    assert body["transport"]["type"] == "http"
    assert is_binary(body["transport"]["endpoint"])

    assert is_map(body["authentication"])
    assert body["authentication"]["type"] == "bearer"
    assert body["authentication"]["pairing_required"] == true
  end

  test "agent.name matches identity", %{conn: conn} do
    conn = get(conn, "/.well-known/sonar/card.json")
    body = json_response(conn, 200)

    identity = Sonar.Identity.get()
    assert body["agent"]["name"] == identity.name
    assert body["agent"]["instance_id"] == identity.instance_id
  end

  test "Cache-Control header is set", %{conn: conn} do
    conn = get(conn, "/.well-known/sonar/card.json")
    assert get_resp_header(conn, "cache-control") == ["public, max-age=3600"]
  end
end
