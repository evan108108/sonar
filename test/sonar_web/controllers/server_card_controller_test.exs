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
    assert is_integer(body["transport"]["port"])
    # `endpoint` is either a string URL (when SONAR_PUBLIC_HOST is set) or
    # nil (when it isn't). Both are valid shapes — see the dedicated tests
    # below for the behavior of each.
    assert is_binary(body["transport"]["endpoint"]) or is_nil(body["transport"]["endpoint"])

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

  describe "SONAR_PUBLIC_HOST override" do
    setup do
      prior = System.get_env("SONAR_PUBLIC_HOST")

      on_exit(fn ->
        case prior do
          nil -> System.delete_env("SONAR_PUBLIC_HOST")
          val -> System.put_env("SONAR_PUBLIC_HOST", val)
        end
      end)

      :ok
    end

    test "advertises SONAR_PUBLIC_HOST when set", %{conn: conn} do
      System.put_env("SONAR_PUBLIC_HOST", "evans-macbook-pro.tail079090.ts.net")
      conn = get(conn, "/.well-known/sonar/card.json")
      body = json_response(conn, 200)
      port = body["transport"]["port"]

      assert body["transport"]["endpoint"] ==
               "http://evans-macbook-pro.tail079090.ts.net:#{port}"
    end

    test "empty SONAR_PUBLIC_HOST yields nil endpoint", %{conn: conn} do
      System.put_env("SONAR_PUBLIC_HOST", "")
      conn = get(conn, "/.well-known/sonar/card.json")
      body = json_response(conn, 200)

      assert is_nil(body["transport"]["endpoint"])
      assert is_integer(body["transport"]["port"])
    end

    test "unset SONAR_PUBLIC_HOST yields nil endpoint", %{conn: conn} do
      System.delete_env("SONAR_PUBLIC_HOST")
      conn = get(conn, "/.well-known/sonar/card.json")
      body = json_response(conn, 200)

      assert is_nil(body["transport"]["endpoint"])
      assert is_integer(body["transport"]["port"])
    end
  end
end
