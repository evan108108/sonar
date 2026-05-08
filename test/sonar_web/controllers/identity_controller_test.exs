defmodule SonarWeb.IdentityControllerTest do
  use SonarWeb.ConnCase

  test "GET /api/identity returns agent identity", %{conn: conn} do
    conn = get(conn, "/api/identity")
    body = json_response(conn, 200)

    assert is_binary(body["name"])
    assert is_binary(body["instance_id"])
    assert is_list(body["capabilities"])
    assert body["version"] == "0.1.0"
  end

  test "PUT /api/identity updates name", %{conn: conn} do
    conn = put(conn, "/api/identity", %{name: "test-agent"})
    body = json_response(conn, 200)
    assert body["name"] == "test-agent"
  end

  test "PUT /api/identity updates capabilities", %{conn: conn} do
    conn = put(conn, "/api/identity", %{capabilities: ["memory", "search"]})
    body = json_response(conn, 200)
    # User-supplied capabilities round-trip; built-in ones (e.g. dm_v1) are
    # always advertised on top — see Sonar.Identity.merge_capabilities/1.
    assert "memory" in body["capabilities"]
    assert "search" in body["capabilities"]
    assert "dm_v1" in body["capabilities"]
  end

  test "GET /api/identity advertises built-in dm_v1 capability", %{conn: conn} do
    conn = get(conn, "/api/identity")
    body = json_response(conn, 200)
    assert "dm_v1" in body["capabilities"]
  end
end
