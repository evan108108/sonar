defmodule SonarWeb.HealthControllerTest do
  use SonarWeb.ConnCase

  test "GET /api/health returns ok", %{conn: conn} do
    conn = get(conn, "/api/health")
    body = json_response(conn, 200)

    assert body["status"] == "ok"
    assert body["app"] == "sonar"
    assert body["version"] == "0.1.0"
    assert is_binary(body["node"])
  end
end
