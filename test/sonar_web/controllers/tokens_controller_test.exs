defmodule SonarWeb.TokensControllerTest do
  use SonarWeb.ConnCase

  import Sonar.Fixtures

  alias Sonar.Repo
  alias Sonar.Schema.PeerToken

  describe "POST /api/peers/:peer_id/tokens" do
    test "returns the raw token in the response", %{conn: conn} do
      p = peer()
      conn = post(conn, "/api/peers/#{p.id}/tokens", %{})
      body = json_response(conn, 201)

      assert is_binary(body["token"])
      assert String.starts_with?(body["token"], "sonar_")
      assert body["peer_id"] == p.id
      assert body["scopes"] == "query"
      assert is_binary(body["id"])
    end

    test "stores only the hash, not the raw token", %{conn: conn} do
      p = peer()
      conn = post(conn, "/api/peers/#{p.id}/tokens", %{})
      body = json_response(conn, 201)

      stored = Repo.get!(PeerToken, body["id"])
      refute stored.token_hash == body["token"]
      expected_hash = :crypto.hash(:sha256, body["token"]) |> Base.encode16(case: :lower)
      assert stored.token_hash == expected_hash
    end

    test "accepts optional scopes", %{conn: conn} do
      p = peer()
      conn = post(conn, "/api/peers/#{p.id}/tokens", %{scopes: "query,write"})
      body = json_response(conn, 201)
      assert body["scopes"] == "query,write"
    end

    test "accepts optional expires_at", %{conn: conn} do
      p = peer()
      future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

      conn =
        post(conn, "/api/peers/#{p.id}/tokens", %{expires_at: DateTime.to_iso8601(future)})

      body = json_response(conn, 201)
      assert body["expires_at"] != nil
    end

    test "returns 404 for nonexistent peer", %{conn: conn} do
      conn = post(conn, "/api/peers/nonexistent/tokens", %{})
      assert json_response(conn, 404)["error"] == "Peer not found"
    end
  end

  describe "GET /api/peers/:peer_id/tokens" do
    test "lists tokens for a peer without exposing hashes", %{conn: conn} do
      p = peer()
      {token, _raw} = peer_token(%{peer: p})

      conn = get(conn, "/api/peers/#{p.id}/tokens")
      body = json_response(conn, 200)

      assert length(body) == 1
      [entry] = body
      assert entry["id"] == token.id
      assert entry["scopes"] == "query"
      refute Map.has_key?(entry, "token_hash")
      refute Map.has_key?(entry, "token")
    end

    test "returns empty list for peer with no tokens", %{conn: conn} do
      p = peer()
      conn = get(conn, "/api/peers/#{p.id}/tokens")
      assert json_response(conn, 200) == []
    end

    test "returns 404 for nonexistent peer", %{conn: conn} do
      conn = get(conn, "/api/peers/nonexistent/tokens")
      assert json_response(conn, 404)["error"] == "Peer not found"
    end
  end

  describe "DELETE /api/peers/:peer_id/tokens/:token_id" do
    test "sets revoked_at instead of deleting", %{conn: conn} do
      p = peer()
      {token, _raw} = peer_token(%{peer: p})

      conn = delete(conn, "/api/peers/#{p.id}/tokens/#{token.id}")
      body = json_response(conn, 200)
      assert body["id"] == token.id
      assert body["revoked_at"] != nil

      stored = Repo.get!(PeerToken, token.id)
      assert %DateTime{} = stored.revoked_at
    end

    test "returns 404 for nonexistent token", %{conn: conn} do
      p = peer()
      conn = delete(conn, "/api/peers/#{p.id}/tokens/nonexistent")
      assert json_response(conn, 404)["error"] == "Token not found"
    end

    test "returns 404 when token belongs to a different peer", %{conn: conn} do
      p1 = peer(%{name: "one", hostname: "one.local"})
      p2 = peer(%{name: "two", hostname: "two.local"})
      {token, _raw} = peer_token(%{peer: p1})

      conn = delete(conn, "/api/peers/#{p2.id}/tokens/#{token.id}")
      assert json_response(conn, 404)["error"] == "Token not found"
    end
  end
end
