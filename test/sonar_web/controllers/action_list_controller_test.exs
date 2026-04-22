defmodule SonarWeb.ActionListControllerTest do
  use SonarWeb.ConnCase

  test "GET /api/actions returns all actions", %{conn: conn} do
    conn = get(conn, "/api/actions")
    actions = json_response(conn, 200)

    assert is_list(actions)
    assert length(actions) > 0

    # Check that known actions are present (with sonar_ prefix stripped)
    names = Enum.map(actions, & &1["name"])
    assert "identity" in names
    assert "send" in names
    assert "inbox" in names
    assert "reply" in names
    assert "health" in names
    assert "peers" in names
  end

  test "GET /api/actions returns correct action shape", %{conn: conn} do
    conn = get(conn, "/api/actions")
    actions = json_response(conn, 200)

    send_action = Enum.find(actions, &(&1["name"] == "send"))
    assert send_action
    assert send_action["description"]
    assert send_action["method"] == "post"
    assert send_action["path"] == "/api/messages/send"
    assert is_list(send_action["params"])

    # Check params have the right shape
    peer_param = Enum.find(send_action["params"], &(&1["name"] == "peer_id"))
    assert peer_param
    assert peer_param["type"] == "string"
    assert peer_param["required"] == true
    assert is_binary(peer_param["description"])
  end

  test "GET /api/actions strips sonar_ prefix from names", %{conn: conn} do
    conn = get(conn, "/api/actions")
    actions = json_response(conn, 200)

    # None should have the sonar_ prefix
    names = Enum.map(actions, & &1["name"])
    refute Enum.any?(names, &String.starts_with?(&1, "sonar_"))
  end
end
