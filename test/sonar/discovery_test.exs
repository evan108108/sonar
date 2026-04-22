defmodule Sonar.DiscoveryTest do
  use ExUnit.Case

  alias Sonar.Peers
  alias Sonar.Schema.Peer

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Sonar.Repo, shared: false)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  describe "peer discovered handling" do
    test "new peer is inserted into DB" do
      # Simulate what Discovery does when it finds a peer
      {:ok, peer} =
        Peers.create(%{
          "name" => "scout",
          "hostname" => "scout.local",
          "port" => 8400,
          "instance_id" => "abc123",
          "discovery_method" => "mdns",
          "connection_status" => "discovered"
        })

      assert peer.name == "scout"
      assert peer.hostname == "scout.local"
      assert peer.discovery_method == "mdns"
      assert peer.connection_status == "discovered"
    end

    test "existing peer is found by instance_id" do
      {:ok, peer} =
        Peers.create(%{
          "name" => "scout",
          "hostname" => "scout.local",
          "instance_id" => "abc123"
        })

      found = Peers.find_by_instance_id("abc123")
      assert found.id == peer.id
    end

    test "find_by_instance_id returns nil for unknown" do
      assert Peers.find_by_instance_id("nonexistent") == nil
    end

    test "find_by_hostname returns the peer" do
      {:ok, peer} =
        Peers.create(%{
          "name" => "scout",
          "hostname" => "scout.local"
        })

      found = Peers.find_by_hostname("scout.local")
      assert found.id == peer.id
    end

    test "offline peer is updated on rediscovery" do
      {:ok, peer} =
        Peers.create(%{
          "name" => "scout",
          "hostname" => "scout.local",
          "instance_id" => "abc123",
          "connection_status" => "offline"
        })

      {:ok, updated} =
        Peers.update(peer, %{
          "connection_status" => "discovered",
          "last_seen_at" => DateTime.utc_now()
        })

      assert updated.connection_status == "discovered"
      assert updated.last_seen_at != nil
    end
  end
end
