defmodule SonarWeb.RelayCardTest do
  use SonarWeb.ConnCase

  test "GET /relay/card returns this instance's server card (public, no auth)", %{conn: conn} do
    conn = get(conn, "/relay/card")
    body = json_response(conn, 200)

    assert body["version"] == "1.0"
    assert is_map(body["agent"])
    assert is_binary(body["agent"]["name"])
    assert is_binary(body["agent"]["instance_id"])
    assert is_map(body["authentication"])
    assert body["authentication"]["type"] == "bearer"
  end

  test "GET /.well-known/sonar/card.json returns the same card", %{conn: conn} do
    conn = get(conn, "/.well-known/sonar/card.json")
    body = json_response(conn, 200)

    assert body["version"] == "1.0"
    assert is_map(body["agent"])
  end
end
