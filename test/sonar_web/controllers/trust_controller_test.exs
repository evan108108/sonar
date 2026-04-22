defmodule SonarWeb.TrustControllerTest do
  use SonarWeb.ConnCase

  import Sonar.Fixtures

  test "PUT /api/trust/:peer_id promotes a peer to 'trusted'", %{conn: conn} do
    p = peer(%{name: "scout", hostname: "scout.local", trust_level: "basic"})

    conn = put(conn, "/api/trust/#{p.id}", %{trust_level: "trusted"})
    body = json_response(conn, 200)

    assert body["peer_id"] == p.id
    assert body["trust_level"] == "trusted"
  end

  test "PUT /api/trust/:peer_id allows 'intimate'", %{conn: conn} do
    p = peer(%{name: "sona", hostname: "sona.local"})

    conn = put(conn, "/api/trust/#{p.id}", %{trust_level: "intimate"})
    assert json_response(conn, 200)["trust_level"] == "intimate"
  end

  test "PUT /api/trust/:peer_id rejects invalid levels", %{conn: conn} do
    p = peer(%{name: "scout", hostname: "scout.local"})

    conn = put(conn, "/api/trust/#{p.id}", %{trust_level: "godmode"})
    assert json_response(conn, 400)["error"] =~ "trust_level"
  end

  test "PUT /api/trust/:peer_id returns 404 for unknown peer", %{conn: conn} do
    conn = put(conn, "/api/trust/nonexistent", %{trust_level: "trusted"})
    assert json_response(conn, 404)["error"] == "peer_not_found"
  end
end
