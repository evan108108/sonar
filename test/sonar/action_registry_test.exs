defmodule Sonar.ActionRegistryTest do
  use ExUnit.Case

  alias Sonar.ActionRegistry

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Sonar.Repo, shared: false)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  describe "registry" do
    test "all/0 returns a list of actions" do
      actions = ActionRegistry.all()
      assert is_list(actions)
      assert length(actions) > 0
    end

    test "every action has required fields" do
      for action <- ActionRegistry.all() do
        assert is_binary(action.name), "#{inspect(action)} missing name"
        assert is_binary(action.description), "#{action.name} missing description"
        assert action.method in [:get, :post, :put, :delete], "#{action.name} bad method"
        assert is_binary(action.path), "#{action.name} missing path"
        assert is_list(action.params), "#{action.name} missing params"
        assert is_function(action.handler, 1), "#{action.name} missing handler"
      end
    end

    test "find/1 returns an action by name" do
      action = ActionRegistry.find("sonar_health")
      assert action.name == "sonar_health"
    end

    test "find/1 returns nil for unknown" do
      assert ActionRegistry.find("nonexistent") == nil
    end

    test "mcp_tool_schemas/0 returns valid schemas" do
      schemas = ActionRegistry.mcp_tool_schemas()
      assert is_list(schemas)

      for schema <- schemas do
        assert is_binary(schema["name"])
        assert is_binary(schema["description"])
        assert is_map(schema["inputSchema"])
        assert schema["inputSchema"]["type"] == "object"
      end
    end

    test "action names are unique" do
      names = ActionRegistry.all() |> Enum.map(& &1.name)
      assert names == Enum.uniq(names)
    end
  end

  describe "execute" do
    test "sonar_health returns ok" do
      {:ok, result} = ActionRegistry.execute("sonar_health")
      assert result.status == "ok"
      assert result.app == "sonar"
    end

    test "sonar_identity returns identity" do
      {:ok, result} = ActionRegistry.execute("sonar_identity")
      assert is_binary(result.name)
      assert is_binary(result.instance_id)
    end

    test "sonar_peers returns list" do
      {:ok, result} = ActionRegistry.execute("sonar_peers")
      assert is_list(result)
    end

    test "sonar_peer_register creates a peer" do
      {:ok, peer} = ActionRegistry.execute("sonar_peer_register", %{
        "name" => "test-peer",
        "hostname" => "test.local"
      })
      assert peer.name == "test-peer"
    end

    test "sonar_send creates a message" do
      {:ok, peer} = ActionRegistry.execute("sonar_peer_register", %{
        "name" => "scout",
        "hostname" => "scout.local"
      })

      {:ok, msg} = ActionRegistry.execute("sonar_send", %{
        "peer_id" => peer.id,
        "question" => "Hello from registry test"
      })
      assert msg.question == "Hello from registry test"
      assert msg.direction == "outbound"
    end

    test "sonar_message returns not_found for unknown" do
      {:error, :not_found} = ActionRegistry.execute("sonar_message", %{
        "message_id" => "nonexistent"
      })
    end

    test "unknown action returns error" do
      {:error, msg} = ActionRegistry.execute("fake_action")
      assert msg =~ "Unknown action"
    end
  end
end
