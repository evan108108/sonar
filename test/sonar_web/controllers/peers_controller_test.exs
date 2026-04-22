defmodule SonarWeb.PeersControllerTest do
  use SonarWeb.ConnCase

  import Sonar.Fixtures

  test "GET /api/peers returns empty list initially", %{conn: conn} do
    conn = get(conn, "/api/peers")
    assert json_response(conn, 200) == []
  end

  test "POST /api/peers creates a peer", %{conn: conn} do
    conn = post(conn, "/api/peers", %{name: "scout", hostname: "scouts-mbp.local", port: 8400})
    body = json_response(conn, 201)

    assert body["name"] == "scout"
    assert body["hostname"] == "scouts-mbp.local"
    assert body["port"] == 8400
    assert body["connection_status"] == "discovered"
    assert body["trust_level"] == "basic"
  end

  test "POST /api/peers validates required fields", %{conn: conn} do
    conn = post(conn, "/api/peers", %{name: "scout"})
    assert json_response(conn, 422)["error"] != nil
  end

  test "GET /api/peers/:id returns a specific peer", %{conn: conn} do
    p = peer(%{name: "scout", hostname: "scout.local"})
    conn = get(conn, "/api/peers/#{p.id}")
    assert json_response(conn, 200)["name"] == "scout"
  end

  test "GET /api/peers/:id returns 404 for unknown", %{conn: conn} do
    conn = get(conn, "/api/peers/nonexistent")
    assert json_response(conn, 404)["error"] == "Peer not found"
  end

  test "PUT /api/peers/:id updates trust level", %{conn: conn} do
    p = peer()
    conn = put(conn, "/api/peers/#{p.id}", %{trust_level: "trusted"})
    assert json_response(conn, 200)["trust_level"] == "trusted"
  end

  test "DELETE /api/peers/:id removes a peer", %{conn: conn} do
    p = peer()
    conn = delete(conn, "/api/peers/#{p.id}")
    assert json_response(conn, 200)["ok"] == true

    conn = get(build_conn(), "/api/peers/#{p.id}")
    assert json_response(conn, 404)
  end

  test "GET /api/peers lists multiple peers", %{conn: conn} do
    peer(%{name: "scout", hostname: "scout.local"})
    peer(%{name: "sona", hostname: "sona.local"})

    conn = get(conn, "/api/peers")
    assert length(json_response(conn, 200)) == 2
  end
end
