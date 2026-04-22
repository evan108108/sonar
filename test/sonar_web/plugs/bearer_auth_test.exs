defmodule SonarWeb.Plugs.BearerAuthTest do
  use SonarWeb.ConnCase

  import Sonar.Fixtures

  alias Sonar.Repo
  alias Sonar.Schema.PeerToken

  describe "GET /relay/health (protected)" do
    test "without Authorization header → 401", %{conn: conn} do
      conn = get(conn, "/relay/health")
      assert json_response(conn, 401) == %{"error" => "unauthorized"}
      assert get_resp_header(conn, "www-authenticate") == [~s(Bearer realm="sonar")]
    end

    test "with invalid token → 401", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer sonar_notarealtoken")
        |> get("/relay/health")

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
      assert get_resp_header(conn, "www-authenticate") == [~s(Bearer realm="sonar")]
    end

    test "with malformed Authorization header → 401", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Basic user:pass")
        |> get("/relay/health")

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end

    test "with valid token → passes, assigns current_peer and current_token", %{conn: conn} do
      p = peer(%{name: "authorized"})
      {token, raw} = peer_token(%{peer: p})

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw}")
        |> get("/relay/health")

      assert json_response(conn, 200)["status"] == "ok"
      assert conn.assigns.current_peer.id == p.id
      assert conn.assigns.current_token.id == token.id
    end

    test "with expired token → 401", %{conn: conn} do
      p = peer()
      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      {_token, raw} = peer_token(%{peer: p, expires_at: past})

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw}")
        |> get("/relay/health")

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end

    test "with revoked token → 401", %{conn: conn} do
      p = peer()
      {token, raw} = peer_token(%{peer: p})

      token
      |> Ecto.Changeset.change(revoked_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update!()

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw}")
        |> get("/relay/health")

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end

    test "updates last_used_at on successful auth", %{conn: conn} do
      p = peer()
      {token, raw} = peer_token(%{peer: p})
      assert is_nil(token.last_used_at)

      conn
      |> put_req_header("authorization", "Bearer #{raw}")
      |> get("/relay/health")

      refreshed = Repo.get!(PeerToken, token.id)
      assert %DateTime{} = refreshed.last_used_at
    end

    test "with future-expiring token → passes", %{conn: conn} do
      p = peer()
      future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
      {_token, raw} = peer_token(%{peer: p, expires_at: future})

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw}")
        |> get("/relay/health")

      assert json_response(conn, 200)["status"] == "ok"
    end
  end
end
